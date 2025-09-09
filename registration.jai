/* global variables */
all_registrations: [..]Registration_Entry;
/* /global variables */

#load "plugins/MIV.jai";

Registration_Entry :: struct {
	plugin_filename: string;
	handle: *void;
	using provided: Provided_Registration_Entry;
	pre_render: Pre_Rendering_Procedure;
	render: Rendering_Procedure;
	settings: Settings_Procedure;
	cleanup: Cleanup_Procedure;
}

Registration_Procedure :: #type (registration: *Provided_Registration_Entry) -> s64 #c_call;
Pre_Rendering_Procedure :: #type (info: *Pre_Rendering_Info) -> string #c_call;
Rendering_Procedure :: #type (pre_info: *Pre_Rendering_Info, render_info: *Rendering_Info) -> string #c_call;
Settings_Procedure :: #type (pre_info: *Pre_Rendering_Info, render_info: *Rendering_Info, settings_info: *Settings_Info) -> string #c_call;
Cleanup_Procedure :: #type (pre_info: *Pre_Rendering_Info) -> string #c_call;

register_dynlib :: (dynlib_name: string, newly_imported: bool, errors: *[..]Error) -> bool {
	exe_path := path_strip_filename(system.get_path_of_running_executable());
	new_dynlib_path := tprint("%plugins/%", exe_path, isolate_name(dynlib_name));
	if newly_imported {
		file_move(dynlib_name, new_dynlib_path);
	}

	dynlib_cname := temp_c_string(new_dynlib_path);

	handle := posix.dlopen(dynlib_cname, posix.RTLD_NOW);
	if !handle {
		give_error(errors, "Dynamic library loading error: %", to_string(posix.dlerror()));
		return false;
	}
	posix.dlerror();

	reg_proc: Registration_Procedure = posix.dlsym(handle, "registration_procedure");
	loading_error := to_string(posix.dlerror());
	if loading_error {
		give_error(errors, "Dynamic function loading error: %", loading_error);
		return false;
	}

	success := true;
	while true {
		p: Provided_Registration_Entry;
		amount := reg_proc(*p);
		if amount < 0 break;

		pre_render_cname := temp_c_string(tprint("%1%2", p.procedure_prefix, "pre_render"));
		pre_render_handle := posix.dlsym(handle, pre_render_cname);
		if !pre_render_handle {
			give_error(errors, "Dynamic function loading error: %", to_string(posix.dlerror()));
			success = false;
		}
		posix.dlerror();

		render_cname := temp_c_string(tprint("%1%2", p.procedure_prefix, "render"));
		render_handle := posix.dlsym(handle, render_cname);
		if !render_handle {
			give_error(errors, "Dynamic function loading error: %", to_string(posix.dlerror()));
			success = false;
		}
		posix.dlerror();

		settings_handle: *void;
		if p.has_settings {
			settings_cname := temp_c_string(tprint("%1%2", p.procedure_prefix, "settings"));
			settings_handle := posix.dlsym(handle, settings_cname);
			if !settings_handle {
				give_error(errors, "Dynamic function loading error: %", to_string(posix.dlerror()));
				success = false;
			}
			posix.dlerror();
		}

		cleanup_cname := temp_c_string(tprint("%1%2", p.procedure_prefix, "cleanup"));
		cleanup_handle := posix.dlsym(handle, cleanup_cname);
		if !cleanup_handle {
			give_error(errors, "Dynamic function loading error: %", to_string(posix.dlerror()));
			success = false;
		}
		posix.dlerror();

		registration := Registration_Entry.{
			plugin_filename = isolate_name(dynlib_name),
			handle = handle,
			provided = p,
			pre_render = pre_render_handle,
			render = render_handle,
			settings = settings_handle,
			cleanup = cleanup_handle,
		};
		array_add(*all_registrations, registration);
		give_log(errors, "%", registration);

		if amount <= 0 break;
	}
	return success;
}


Settings_File_0 :: struct {
	version: u8;
	pers_between_files: Persistence_Setting;
	pers_between_restarts: Persistence_Setting;
	aa_setting_on_previous_close: bool;
	scale_on_previous_close: float #align 1;
	offset_on_previous_close: Vector2 #align 1;
}

Persistence_Setting :: struct {
	of_aa: bool;
	of_scale: bool;
	of_offset: bool;
}

Default_Settings :: Settings_File_0.{};

load_registrations :: (errors: *[..]Error) -> Settings_File_0 {
	path := path_strip_filename(system.get_path_of_running_executable());
	path = tprint("%plugins/", path);
	make_directory_if_it_does_not_exist(path);
	plugin_filenames: [..]string;
	discover_directory(*plugin_filenames, path, errors);
	for plugin_filenames if it.count != 0 && get_extension(it) == "so" then register_dynlib(it, false, errors);

	settings_filename := tprint("%0%0", path, "settings.miv");
	settings_file_string, exists := read_entire_file(settings_filename, log_errors = false);
	if !exists return Default_Settings;

	settings_file_buffer := cast([]u8, settings_file_string);
	settings_file: Settings_File_0;
	if settings_file_buffer[0] == {
	case 0;
		if settings_file_buffer.count != size_of(Settings_File_0) return Default_Settings;
		settings_file = cast(*Settings_File_0, settings_file_buffer.data).*;
	case;
		log("Unsupported settings file version '%'.", settings_file_buffer[0]);
		return Default_Settings;
	}

	return settings_file;
}

write_settings_file :: (settings_file: Settings_File_0) {
	path := tprint("%plugins/settings.miv", path_strip_filename(system.get_path_of_running_executable()));
	write_entire_file(path, *settings_file, size_of(type_of(settings_file)));
}

cleanup_registrations :: (settings_file: Settings_File_0) {
	sb: String_Builder;

	closed_handles: [..]*void;
	registered_names: [..]string;
	for all_registrations {
		if !array_find(registered_names, it.plugin_filename) {
			array_add(*registered_names, it.plugin_filename);
			print(*sb, "%\n", it.plugin_filename);
		}
		if !array_find(closed_handles, it.handle) {
			posix.dlclose(it.handle);
			array_add(*closed_handles, it.handle);
		}
	}
	write_settings_file(settings_file);
}

get_loading :: (filepath: string, extension: string, img_ctx: *Image_Context, errors: *[..]Error) -> bool {
	new_plugin: *Registration_Entry = null;
	ok := true;
	if extension {
		push_allocator(temp);
		for * all_registrations {
			registered_ext := it.extension;
			found_ext := extension;
			if !it.extension_is_case_sensitive {
				registered_ext = to_lower_copy(registered_ext);
				found_ext = to_lower_copy(found_ext);
			}
			if registered_ext == found_ext {
				new_plugin = it;
				break;
			}
		}
	}
	file_handle: *posix.FILE;
	file_handle = posix.fopen(temp_c_string(filepath), "r");
	if !file_handle {
		give_error(errors, "File does not exist or could not be opened: %", filepath);
		ok = false;
		return false;
	}
	pre_info := Pre_Rendering_Info.{
		name = filepath,
		fileptr = file_handle,
	};

	defer if !ok {
		give_log(errors, "'%' closed because there was an error.", filepath);
		posix.fclose(file_handle);
	}

	if !new_plugin {
		push_allocator(temp);
		for * all_registrations {
			found_mn := cast(string, NewArray(it.magic_number.count, u8));
			posix.fread(found_mn.data, 1, xx found_mn.count, file_handle);
			posix.fseek(file_handle, 0, posix.SEEK_SET);
			if found_mn == it.magic_number {
				new_plugin = it;
				break;
			}
		}
	}

	if !new_plugin {
		give_error(errors, "Could not load file '%' with any available plugin.", filepath);
		ok = false;
		return false;
	}

	found_mn := cast(string, NewArray(new_plugin.magic_number.count, u8));
	defer array_reset(*cast([]u8, found_mn));

	if new_plugin.magic_number {
		posix.fread(found_mn.data, 1, xx found_mn.count, file_handle);
		posix.fseek(file_handle, 0, posix.SEEK_SET);
		if found_mn != new_plugin.magic_number {
			expe, foun: string;
			if valid_ascii(new_plugin.magic_number) expe = new_plugin.magic_number;
			else expe = tprint("%", cast([]u8, new_plugin.magic_number));
			if valid_ascii(found_mn) foun = found_mn;
			else foun = tprint("%", cast([]u8, found_mn));

			give_error(errors, "Mismatched magic number. The file type '%' expected the magic number '%', but got '%'.", new_plugin.name_filetype, expe, foun);
			// Also do the whole magic number checking here so that the user can choose
			ok = false;
			return false;
		}
	}

	pre_info_err := new_plugin.pre_render(*pre_info);
	posix.fseek(file_handle, 0, posix.SEEK_SET);
	if pre_info_err {
		give_error(errors, "% file metadata reading error: %", new_plugin.name_filetype, pre_info_err);
		ok = false;
		return false;
	}

	if img_ctx.watcher.callback {
		deinit(img_ctx.watcher);
		if !init(*img_ctx.watcher, file_change_callback, img_ctx, events_to_watch = .ALL_EVENTS, merge_window_seconds = 2*TARGET_FRAME_TIME, verbose = false, watch_recursively = false) {
			give_error(errors, "Could not initialize watcher");
			ok = false;
			return false;
		}

		dir := path_strip_filename(filepath);
		if !dir then dir = "./";
		if !add_directories(*img_ctx.watcher, dir) {
			give_error(errors, "The directory of '%' could not be opened for tracking file changes", filepath);
			ok = false;
			return false;
		}
	}

	img_ctx.pre_info = pre_info;
	img_ctx.plugin = new_plugin;

	return true;
}

file_change_callback :: (watcher: *File_Watcher(Image_Context), change: *File_Change, img_ctx: *Image_Context) {
	/* If the file change is in the dir, redo the dir */
	/* If the file change is in the history, change the correct filename */
	/* To do that second one, I need to first find the index, and then rename it */
	this_file := isolate_name(img_ctx.pre_info.name);
	changed_file := isolate_name(change.full_path);
	// log("% had a %", img_ctx.pre_info.name, change.*);
	// log("that is, '%' and '%'", this_file, changed_file);
	if changed_file == this_file && (change.events & .MODIFIED) {
		img_ctx.watcher_says_rerender = true;
	} else {
		img_ctx.watcher_says_something_moved_somewhere = true;
	}
}

valid_ascii :: (str: string) -> bool {
	for str {
		if #char "~" < it || it < #char " " return false;
	}
	return true;
}

get_extension :: (path: string) -> string {
	ext: string;
	ext.count = 0;
	ext.data = path.data + path.count;
	while ext.count != path.count {
		ext.count += 1;
		ext.data -= 1;
		if ext[0] == "." {
			ext.count -= 1;
			ext.data += 1;
			return ext;
		}
	}
	return "";
}

isolate_name :: (path: string) -> string {
	ext: string;
	ext.count = 0;
	ext.data = path.data + path.count;
	while ext.count != path.count {
		ext.count += 1;
		ext.data -= 1;
		if ext[0] == "/" {
			ext.count -= 1;
			ext.data += 1;
			return ext;
		}
	}
	return path;
}

discover_directory :: (directory: *[..]string, file: string, errors: *[..]Error) -> bool {
	dir_name := path_strip_filename(file);
	if !dir_name.count dir_name = "./";
	c_dir_name := temp_c_string(dir_name);
	namelist: **posix.dirent;
	filter :: (name: *posix.dirent) -> s32 #c_call { return 1; };

	namelist_count := posix.scandir(c_dir_name, *namelist, filter, posix.alphasort);
	if namelist_count == -1 {
		give_error(errors, "Could not scan directory '%'.", dir_name);
		return false;
	}
	array_reset(directory);

	crt :: #system_library "libc";
    c_free :: (memory: *void) #foreign crt "free";
	for 0..namelist_count-1 {
		//status: posix.stat_t;
		//posix.lstat(*namelist[it].d_name[0], *status);
		if namelist[it].d_type == .REG {
			array_add(directory, copy_string(tprint("%1%2", dir_name, to_string(*namelist[it].d_name[0]) )) );
		}

		c_free(namelist[it]);
	}
	c_free(namelist);

	return true;
}

sanitize_file_list :: (list: *[..]string, file: string, index: *int, errors: *[..]Error) {
	new_list: [..]string;
	dummy_img_ctx: Image_Context;
	dummy_errors: [..]Error;
	dummy_errors.allocator = temp;
	if !errors errors = *dummy_errors;
	for list.* {
		if !get_loading(it, get_extension(it), *dummy_img_ctx, errors) continue;
		posix.fclose(dummy_img_ctx.pre_info.fileptr);
		array_add(*new_list, it);
	}
	array_reset(list);
	list.* = new_list;

	found: bool;
	found, index.* = array_find(list.*, file);
	if !found {
		index.* = list.count - 1;
	}
}

Error :: struct {
	kind: enum{ERROR; LOG;};
	message: string;
	options: [2]string;
}

give_log :: (errors: *[..]Error, message: string, args: ..Any) {
	array_add(errors, .{.LOG, sprint(message, ..args), .[]});
}

give_error :: (errors: *[..]Error, message: string, args: ..Any) {
	array_add(errors, .{.ERROR, sprint(message, ..args), .["dismiss"]});
}

system :: #import "System";
