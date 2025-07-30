/* global variables */
all_registrations: [..]Registration_Entry;
/* /global variables */

Pre_Rendering_Info :: struct {
	name: string;
	fileptr: *libc.FILE;
	width, height: s64;

	bit_depth: u8;
	channels: u8;
	metadata: string;

	user_ptr: *void;
}

Rendering_Info :: struct {
	column_range: [2]s64;
	row_range: [2]s64;

	buffer_width: s64;
	buffer_height: s64;
	buffer: [][4]u8;
}

Provided_Registration_Entry :: struct {
	name_filetype: string;
	procedure_prefix: string;
	extension: string;
	magic_number: string;
	bytes_before_magic_number: int;
	extension_is_case_sensitive: bool;
}

Error :: struct {
	kind: enum{ERROR; LOG;};
	message: string;
	options: [2]string;
}

Registration_Entry :: struct {
	plugin_filename: string;
	handle: *void;
	using provided: Provided_Registration_Entry;
	pre_render: Pre_Rendering_Procedure;
	render: Rendering_Procedure;
	cleanup: Cleanup_Procedure;
}

Registration_Procedure :: #type (registration: *Provided_Registration_Entry) -> s64 #c_call;
Pre_Rendering_Procedure :: #type (info: *Pre_Rendering_Info) -> string #c_call;
Rendering_Procedure :: #type (pre_info: *Pre_Rendering_Info, render_info: *Rendering_Info) -> string #c_call;
Cleanup_Procedure :: #type (pre_info: *Pre_Rendering_Info) -> string #c_call;

register_dynlib :: (dynlib_name: string, newly_imported: bool, errors: *[..]Error) -> bool {
	exe_path := path_strip_filename(system.get_path_of_running_executable());
	new_dynlib_path := tprint("%plugins/%", exe_path, isolate_name(dynlib_name));
	if newly_imported {
		file_move(dynlib_name, new_dynlib_path);
	}

	dynlib_cname := temp_c_string(new_dynlib_path);

	handle := libc.dlopen(dynlib_cname, libc.RTLD_NOW);
	if !handle {
		give_error(errors, "Dynamic library loading error: %", to_string(libc.dlerror()));
		return false;
	}
	libc.dlerror();

	reg_proc: Registration_Procedure = libc.dlsym(handle, "registration_procedure");
	loading_error := to_string(libc.dlerror());
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
		pre_render_handle := libc.dlsym(handle, pre_render_cname);
		if !pre_render_handle {
			give_error(errors, "Dynamic function loading error: %", to_string(libc.dlerror()));
			success = false;
		}
		libc.dlerror();

		render_cname := temp_c_string(tprint("%1%2", p.procedure_prefix, "render"));
		render_handle := libc.dlsym(handle, render_cname);
		if !render_handle {
			give_error(errors, "Dynamic function loading error: %", to_string(libc.dlerror()));
			success = false;
		}
		libc.dlerror();

		cleanup_cname := temp_c_string(tprint("%1%2", p.procedure_prefix, "cleanup"));
		cleanup_handle := libc.dlsym(handle, cleanup_cname);
		if !cleanup_handle {
			give_error(errors, "Dynamic function loading error: %", to_string(libc.dlerror()));
			success = false;
		}
		libc.dlerror();

		registration := Registration_Entry.{
			plugin_filename = isolate_name(dynlib_name),
			handle = handle,
			provided = p,
			pre_render = pre_render_handle,
			render = render_handle,
			cleanup = cleanup_handle,
		};
		array_add(*all_registrations, registration);
		give_log(errors, "%", registration);

		if amount <= 0 break;
	}
	return success;
}

load_registration_file :: (errors: *[..]Error) {
	path := path_strip_filename(system.get_path_of_running_executable());
	make_directory_if_it_does_not_exist(tprint("%plugins/", path));
	regfile_path := tprint("%plugins/registrations.miv", path);
	regfile, exists := read_entire_file(regfile_path, log_errors = false);
	if !exists return;

	plugin_filenames := split(regfile, cast(u8, #char "\n"));
	for plugin_filenames if it.count != 0 register_dynlib(it, false, errors);
}

cleanup_registrations :: () {
	sb: String_Builder;

	closed_handles: [..]*void;
	registered_names: [..]string;
	for all_registrations {
		if !array_find(registered_names, it.plugin_filename) {
			array_add(*registered_names, it.plugin_filename);
			print(*sb, "%\n", it.plugin_filename);
		}
		if !array_find(closed_handles, it.handle) {
			libc.dlclose(it.handle);
			array_add(*closed_handles, it.handle);
		}
	}

	path := path_strip_filename(system.get_path_of_running_executable());
	regfile_path := tprint("%plugins/registrations.miv", path);
	write_entire_file(regfile_path, builder_to_string(*sb));
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
	file_handle: *libc.FILE;
	file_handle = libc.fopen(temp_c_string(filepath), "r");
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
		libc.fclose(file_handle);
	}

	if !new_plugin {
		push_allocator(temp);
		for * all_registrations {
			found_mn := cast(string, NewArray(it.magic_number.count, u8));
			libc.fread(found_mn.data, 1, xx found_mn.count, file_handle);
			libc.fseek(file_handle, 0, libc.SEEK_SET);
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
		libc.fread(found_mn.data, 1, xx found_mn.count, file_handle);
		libc.fseek(file_handle, 0, libc.SEEK_SET);
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
	libc.fseek(file_handle, 0, libc.SEEK_SET);
	if pre_info_err {
		give_error(errors, "% file metadata reading error: %", new_plugin.name_filetype, pre_info_err);
		ok = false;
		return false;
	}

	img_ctx.pre_info = pre_info;
	img_ctx.plugin = new_plugin;
	return true;
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

give_log :: (errors: *[..]Error, message: string, args: ..Any) {
	array_add(errors, .{.LOG, sprint(message, ..args), .[]});
}

give_error :: (errors: *[..]Error, message: string, args: ..Any) {
	array_add(errors, .{.ERROR, sprint(message, ..args), .["ok"]});
}

libc :: #import "POSIX";
system :: #import "System";
