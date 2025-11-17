/* global variables */
all_registrations: [..]Registration_Entry;
/* /global variables */

#load "plugins/MIV.jai";

Registration_Entry :: struct {
	plugin_filename: string;
	dynlib_handle: *void;
	plugin_provided: Plugin_Registration_Entry;
	pre_render: Pre_Rendering_Procedure;
	render: Rendering_Procedure;
	setting: Setting_Procedure;
	cleanup: Cleanup_Procedure;

	settings: []Plugin_Setting;
}

Registration_Procedure :: #type (registration: *Plugin_Registration_Entry) -> s64 #c_call;
Pre_Rendering_Procedure :: #type (info: *Pre_Rendering_Info) -> Log #c_call;
Rendering_Procedure :: #type (pre_info: *Pre_Rendering_Info, render_info: *Rendering_Info) -> Log #c_call;
Setting_Procedure :: #type (pre_info: *Pre_Rendering_Info, render_info: *Rendering_Info, settings: *Setting_Info) -> s32 #c_call;
Cleanup_Procedure :: #type (pre_info: *Pre_Rendering_Info) -> Log #c_call;

register_dynlib :: (dynlib_name: string, newly_imported: bool, content_log_plugins: bool) -> bool {
	exe_path := path_strip_filename(system.get_path_of_running_executable());
	new_dynlib_path := tprint("%plugins/%", exe_path, isolate_name(dynlib_name));
	if newly_imported {
		file_delete(new_dynlib_path);
		file_move(dynlib_name, new_dynlib_path);
	}

	dynlib_cname := temp_c_string(new_dynlib_path);

	dynlib_handle := posix.dlopen(dynlib_cname, posix.RTLD_NOW);
	if !dynlib_handle {
		log_error("Dynamic library loading error: %", to_string(posix.dlerror()));
		return false;
	}
	posix.dlerror();

	reg_proc: Registration_Procedure = posix.dlsym(dynlib_handle, "registration_procedure");
	loading_error := to_string(posix.dlerror());
	if loading_error {
		log_error("Dynamic function loading error: %", loading_error);
		return false;
	}

	success := true;
	while true {
		p: Plugin_Registration_Entry;
		amount := reg_proc(*p);
		if amount < 0 break;

		pre_render_cname := temp_c_string(tprint("%1%2", p.procedure_prefix, "pre_render"));
		pre_render_handle := posix.dlsym(dynlib_handle, pre_render_cname);
		if !pre_render_handle {
			log_error("Dynamic function loading error: %", to_string(posix.dlerror()));
			success = false;
		}
		posix.dlerror();

		render_cname := temp_c_string(tprint("%1%2", p.procedure_prefix, "render"));
		render_handle := posix.dlsym(dynlib_handle, render_cname);
		if !render_handle {
			log_error("Dynamic function loading error: %", to_string(posix.dlerror()));
			success = false;
		}
		posix.dlerror();

		setting_handle: *void;
		if p.has_settings {
			setting_cname := temp_c_string(tprint("%1%2", p.procedure_prefix, "setting"));
			setting_handle = posix.dlsym(dynlib_handle, setting_cname);
			if !setting_handle {
				log_error("Dynamic function loading error: %", to_string(posix.dlerror()));
				success = false;
			}
			posix.dlerror();
		}

		cleanup_cname := temp_c_string(tprint("%1%2", p.procedure_prefix, "cleanup"));
		cleanup_handle := posix.dlsym(dynlib_handle, cleanup_cname);
		if !cleanup_handle {
			log_error("Dynamic function loading error: %", to_string(posix.dlerror()));
			success = false;
		}
		posix.dlerror();

		registration := Registration_Entry.{
			plugin_filename = isolate_name(dynlib_name),
			dynlib_handle = dynlib_handle,
			plugin_provided = p,
			pre_render = pre_render_handle,
			render = render_handle,
			setting = setting_handle,
			cleanup = cleanup_handle,
		};
		array_add(*all_registrations, registration);

		log("Plugin for '%' succesfully loaded.", p.name_of_filetype, flags = ifx content_log_plugins then .CONTENT else .VERBOSE_ONLY);

		if amount <= 0 break;
	}
	return success;
}

Settings_File_0 :: struct {
	version: u8 = 0;
	pers_between_files: Persistence_Setting;
	pers_between_restarts: Persistence_Setting;
	aa_setting_on_previous_close: bool;
	scale_on_previous_close: float #align 1;
	offset_on_previous_close: Vector2 #align 1;
}

Zoom_Alignment_Setting :: enum u8 {CENTER; POINTER;}
Settings_File_1 :: struct {
	version: u8 = 1;
	pers_between_files: Persistence_Setting;
	pers_between_restarts: Persistence_Setting;
	aa_setting_on_previous_close: bool;
	scale_on_previous_close: float #align 1;
	offset_on_previous_close: Vector2 #align 1;
	zoom_alignment_on_previous_close: Zoom_Alignment_Setting;
}

Settings_File_2 :: struct {
	version: u8 = 2;
	pers_between_files: Persistence_Setting;
	pers_between_restarts: Persistence_Setting;
	aa_setting_on_previous_close: bool;
	downscaling_on_previous_close: bool;
	scale_on_previous_close: float #align 1;
	offset_on_previous_close: Vector2 #align 1;
	zoom_alignment_on_previous_close: Zoom_Alignment_Setting;
}

Persistence_Setting :: struct {
	of_aa: bool;
	of_scale: bool;
	of_offset: bool;
}

Setting_Header :: struct {
	name_hash: u32;
	data_length: s32;
}

Settings_File_3 :: struct {
	version: u8 = 3;
	pers_between_files: Persistence_Setting;
	pers_between_restarts: Persistence_Setting;
	smoothing_setting_on_previous_close: bool;
	downscaling_on_previous_close: bool = true;
	elaborate_tips: bool;
	queues_loop: bool = true;

	scale_on_previous_close: float #align 1;
	offset_on_previous_close: Vector2 #align 1;
	angle_on_previous_close: float #align 1;
	zoom_alignment_on_previous_close: Zoom_Alignment_Setting;
	target_frame_time_on_previous_close: float64 #align 1;
	window_size_on_previous_close: [2]int #align 1;
	bg_color: [3]u8 = .[30, 25, 30];
}

Default_Settings :: Settings_File_3.{};

load_registrations :: () -> Settings_File_3 {
	path := path_strip_filename(system.get_path_of_running_executable());
	path = tprint("%plugins/", path);
	make_directory_if_it_does_not_exist(path);
	plugin_filenames: [..]string;
	discover_directory(*plugin_filenames, path);
	for plugin_filenames if it.count != 0 && get_extension(it) == "so" then register_dynlib(it, false, false);

	settings_filename := tprint("%0%0", path, "settings.miv");
	settings_file_string, exists := read_entire_file(settings_filename, log_errors = false);
	if !exists return Default_Settings;

	settings_file_buffer := cast([]u8, settings_file_string);
	settings_file: Settings_File_3;
	if settings_file_buffer[0] == {
	case 0;
		if settings_file_buffer.count != size_of(Settings_File_0) return Default_Settings;
		sf0 := cast(*Settings_File_0, settings_file_buffer.data).*;
		settings_file.pers_between_files = sf0.pers_between_files;
		settings_file.pers_between_restarts = sf0.pers_between_restarts;
		settings_file.smoothing_setting_on_previous_close = sf0.aa_setting_on_previous_close;
		settings_file.scale_on_previous_close = sf0.scale_on_previous_close;
		settings_file.offset_on_previous_close = sf0.offset_on_previous_close;
	case 1;
		if settings_file_buffer.count != size_of(Settings_File_1) return Default_Settings;
		sf1 := cast(*Settings_File_1, settings_file_buffer.data).*;
		settings_file.pers_between_files = sf1.pers_between_files;
		settings_file.pers_between_restarts = sf1.pers_between_restarts;
		settings_file.smoothing_setting_on_previous_close = sf1.aa_setting_on_previous_close;
		settings_file.scale_on_previous_close = sf1.scale_on_previous_close;
		settings_file.offset_on_previous_close = sf1.offset_on_previous_close;
	case 2;
		if settings_file_buffer.count != size_of(Settings_File_2) return Default_Settings;
		sf2 := cast(*Settings_File_2, settings_file_buffer.data).*;
		settings_file.pers_between_files = sf2.pers_between_files;
		settings_file.pers_between_restarts = sf2.pers_between_restarts;
		settings_file.smoothing_setting_on_previous_close = sf2.aa_setting_on_previous_close;
		settings_file.downscaling_on_previous_close = sf2.downscaling_on_previous_close;
		settings_file.scale_on_previous_close = sf2.scale_on_previous_close;
		settings_file.offset_on_previous_close = sf2.offset_on_previous_close;
	case 3;
		progress := 1;
		while settings_file_buffer.count - progress - 1  > size_of(Setting_Header) {
			header := (settings_file_buffer.data + progress).(*Setting_Header).*;
			was_normal_setting := false;
			for member: type_info(Settings_File_3).members {
				if it_index == 0 continue member;
				hash := Hash.sdbm_hash(member.name.data, member.name.count);
				if hash == header.name_hash {
					if member.type.runtime_size != header.data_length continue member;
					if settings_file_buffer.count - progress - 1 - header.data_length < 1 break member;
					dst := (*settings_file).(*u8) + member.offset_in_bytes;
					src := settings_file_buffer.data + progress + size_of(Setting_Header);
					memcpy(dst, src, header.data_length);
//					was_normal_setting = true;
					break member;
				}
			}
			if !was_normal_setting for registration: all_registrations {
				plugin_code := tprint("%.%.%", registration.plugin_filename, registration.plugin_provided.name_of_filetype, registration.plugin_provided.extension);
				hash := Hash.sdbm_hash(plugin_code.data, plugin_code.count);
				if hash == header.name_hash {

				}
				//print("%, %\n", plugin_code, hash);
			}
			progress += header.data_length + size_of(Setting_Header);;
		}
	case;
		log("Unsupported settings file version '%'.", settings_file_buffer[0], flags = .WARNING);
		return Default_Settings;
	}

	return settings_file;
}

write_settings_file :: (settings_file: Settings_File_3) {
	buffer: [..]u8;
	array_add(*buffer, settings_file.version);
	for member: type_info(type_of(settings_file)).members {
		if it_index == 0 continue;
		header := Setting_Header.{Hash.sdbm_hash(member.name.data, member.name.count), xx member.type.runtime_size};
		array_add(*buffer, ..[]u8.{size_of(Setting_Header), (*header).(*u8)});
		array_add(*buffer, ..[]u8.{header.data_length, (*settings_file).(*u8) + member.offset_in_bytes});
	}
	// for registration: all_registrations {
	// 	plugin_code := tprint("%.%.%", registration.plugin_filename, registration.plugin_provided.name_of_filetype, registration.plugin_provided.extension);
	// 	hash := Hash.sdbm_hash(plugin_code.data, plugin_code.count);
	// 	byte_count := 0;
	// 	for setting: registration.settings {

	// 	}
	// }

	path := tprint("%plugins/settings.miv", path_strip_filename(system.get_path_of_running_executable()));
	write_entire_file(path, buffer.data, buffer.count);
}

cleanup_registrations :: (settings_file: Settings_File_3) {
	sb: String_Builder;

	closed_handles: [..]*void;
	registered_names: [..]string;
	for all_registrations {
		if !array_find(registered_names, it.plugin_filename) {
			array_add(*registered_names, it.plugin_filename);
			print(*sb, "%\n", it.plugin_filename);
		}
		if !array_find(closed_handles, it.dynlib_handle) {
			posix.dlclose(it.dynlib_handle);
			array_add(*closed_handles, it.dynlib_handle);
		}
	}
	write_settings_file(settings_file);
}

get_loading :: (filepath: string, extension: string, img_ctx: *Image_Context, do_logging: bool) -> bool {
	new_plugin: *Registration_Entry = null;
	ok := true;
	if extension {
		push_allocator(temp);
		for * all_registrations {
			registered_ext := it.plugin_provided.extension;
			found_ext := extension;
			registered_ext = to_lower_copy(registered_ext);
			found_ext = to_lower_copy(found_ext);
			if registered_ext == found_ext {
				new_plugin = it;
				break;
			}
		}
	}

	file_handle: *posix.FILE;
	file_handle = posix.fopen(temp_c_string(filepath), "r");
	if !file_handle {
		if do_logging log_error("File does not exist or could not be opened: %", filepath);
		ok = false;
		return false;
	}
	pre_info := Pre_Rendering_Info.{
		name = filepath,
		fileptr = file_handle,
	};

	defer if !ok {
		log("'%' closed because it could not be loaded.", filepath, flags = .VERBOSE_ONLY);
		posix.fclose(file_handle);
	}

	if !new_plugin {
		push_allocator(temp);
		for * all_registrations {
			found_mn := cast(string, NewArray(it.plugin_provided.magic_number.count, u8));
			posix.fread(found_mn.data, 1, xx found_mn.count, file_handle);
			posix.fseek(file_handle, 0, posix.SEEK_SET);
			if it.plugin_provided.magic_number && found_mn == it.plugin_provided.magic_number {
				new_plugin = it;
				break;
			}
		}
	}

	if !new_plugin {
		if do_logging log_error("Could not load file '%' with any available plugin.", filepath);
		ok = false;
		return false;
	}

	found_mn := cast(string, NewArray(new_plugin.plugin_provided.magic_number.count, u8));
	defer array_reset(*cast([]u8, found_mn));

	if new_plugin.plugin_provided.magic_number {
		posix.fread(found_mn.data, 1, xx found_mn.count, file_handle);
		posix.fseek(file_handle, 0, posix.SEEK_SET);
		if found_mn != new_plugin.plugin_provided.magic_number {
			expe, foun: string;
			if valid_ascii(new_plugin.plugin_provided.magic_number) expe = new_plugin.plugin_provided.magic_number;
			else expe = tprint("%", cast([]u8, new_plugin.plugin_provided.magic_number));
			if valid_ascii(found_mn) foun = found_mn;
			else foun = tprint("%", cast([]u8, found_mn));

			if do_logging log_error("Mismatched magic number. The file type '%' expected the magic number '%', but got '%'.", new_plugin.plugin_provided.name_of_filetype, expe, foun);
			// Also do the whole magic number checking here so that the user can choose
			ok = false;
			return false;
		}
	}

	pre_info_log := new_plugin.pre_render(*pre_info);
	defer if !ok {
		plugin_log(new_plugin.cleanup(*pre_info));
	}

	posix.fseek(file_handle, 0, posix.SEEK_SET);
	if pre_info_log.type == .ERROR {
		if do_logging log_error("File type '%' metadata reading error: %", new_plugin.plugin_provided.name_of_filetype, pre_info_log.message);
		ok = false;
		return false;
	}
	if do_logging plugin_log(pre_info_log);

	if img_ctx.watcher.callback {
		deinit(img_ctx.watcher);
		if !init(*img_ctx.watcher, file_change_callback, img_ctx, events_to_watch = .ALL_EVENTS, merge_window_seconds = 2*DEFAULT_FRAME_TIME, verbose = false, watch_recursively = false) {
			if do_logging log_error("Could not initialize watcher");
			ok = false;
			return false;
		}

		dir := path_strip_filename(filepath);
		if !dir then dir = "./";
		if !add_directories(*img_ctx.watcher, dir) {
			if do_logging log_error("The directory of '%' could not be opened for tracking file changes", filepath);
			ok = false;
			return false;
		}
	}

	if img_ctx.plugin plugin_log(img_ctx.plugin.cleanup(*img_ctx.pre_info));

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

discover_directory :: (directory: *[..]string, file: string) -> bool {
	dir_name := path_strip_filename(file);
	if !dir_name.count dir_name = "./";
	c_dir_name := temp_c_string(dir_name);
	namelist: **posix.dirent;
	filter :: (name: *posix.dirent) -> s32 #c_call { return 1; };

	namelist_count := posix.scandir(c_dir_name, *namelist, filter, posix.alphasort);
	if namelist_count == -1 {
		log_error("Could not scan directory '%'.", dir_name);
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

sanitize_file_list :: (list: *[..]string, file: string, index: *int, do_logging: bool) {
	new_list: [..]string;
	dummy_img_ctx: Image_Context;
	for list.* {
		if !get_loading(it, get_extension(it), *dummy_img_ctx, do_logging) continue;
		plugin_log(dummy_img_ctx.plugin.cleanup(*dummy_img_ctx.pre_info));
		posix.fclose(dummy_img_ctx.pre_info.fileptr);
		array_add(*new_list, it);
	}
	array_reset(list);
	list.* = new_list;

	if file {
		found: bool;
		found, index.* = array_find(list.*, file);
		if !found {
			index.* = list.count - 1;
		}
	}
}

system :: #import "System";
