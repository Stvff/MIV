/* global variables */
all_registrations: [..]Registration_Entry;
current_plugin: *Registration_Entry;
/* /global variables */

Pre_Rendering_Info :: struct {
	name: string;
	fileptr: *libc.FILE;
	width, height: s64;

	bit_depth: u8;
	channels: u8;
	metadata: string;
}

Rendering_Info :: struct {
	column_range: [2]s64;
	row_range: [2]s64;

	buffer_width: s64;
	buffer_height: s64;
	buffer_size: s64;
	buffer: *[4]u8;
}

Provided_Registration_Entry :: struct {
	name_filetype: string;
	procedure_prefix: string;
	extension: string;
	magic_number: string;
	bytes_before_magic_number: int;
	extension_is_case_sensitive: bool;
}

Registration_Entry :: struct {
	filepath: string;
	handle: *void;
	using provided: Provided_Registration_Entry;
	pre_render: Pre_Rendering_Procedure;
	render: Rendering_Procedure;
}

Registration_Procedure :: #type (registration: *Provided_Registration_Entry) -> s64 #c_call;
Pre_Rendering_Procedure :: #type (info: *Pre_Rendering_Info) -> string #c_call;
Rendering_Procedure :: #type (pre_info: *Pre_Rendering_Info, render_info: *Rendering_Info) -> string #c_call;

register_dynlib :: (dynlib_name: string) -> bool {
	dynlib_cname := temp_c_string(dynlib_name);

	handle := libc.dlopen(dynlib_cname, libc.RTLD_NOW);
	if !handle {
		log_error("Dynamic library loading error: %", to_string(libc.dlerror()));
		return false;
	}
	libc.dlerror();

	reg_proc: Registration_Procedure = libc.dlsym(handle, "registration_procedure");
	loading_error := to_string(libc.dlerror());
	if loading_error {
		log_error("Dynamic function loading error: %", loading_error);
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
			log_error("Dynamic function loading error: %", to_string(libc.dlerror()));
			success = false;
		}
		libc.dlerror();

		render_cname := temp_c_string(tprint("%1%2", p.procedure_prefix, "render"));
		render_handle := libc.dlsym(handle, render_cname);
		if !render_handle {
			log_error("Dynamic function loading error: %", to_string(libc.dlerror()));
			success = false;
		}
		libc.dlerror();

		registration := Registration_Entry.{
			filepath = dynlib_name,
			handle = handle,
			provided = p,
			pre_render = pre_render_handle,
			render = render_handle,
		};
		array_add(*all_registrations, registration);
		print("%\n", registration);

		if amount <= 0 break;
	}
	return success;
}

cleanup_registrations :: () {
	closed_handles: [..]*void;
	for all_registrations {
		if !array_find(closed_handles, it.handle) then libc.dlclose(it.handle);
		array_add(*closed_handles, it.handle);
	}
}

get_loading :: (filepath: string, extension: string) -> bool {
	new_plugin: *Registration_Entry = null;
	if extension.count {
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
		log_error("File does not exist or could not be opened: %", filepath);
		return false;
	}

	defer libc.fclose(file_handle);

	if !new_plugin {
		log_error("Could not recognize file");
		return false;
		// deal with that by checking possible magic numbers and otherwise returning
	}

	found_mn := cast(string, NewArray(new_plugin.magic_number.count, u8));
	defer array_reset(*cast([]u8, found_mn));

	if new_plugin.magic_number {
		libc.fread(found_mn.data, 1, xx found_mn.count, file_handle);
		libc.fseek(file_handle, 0, libc.SEEK_SET);
		if found_mn != new_plugin.magic_number {
			log_error("Mismatched magic number. The file type '%' expected the magic number '%', but got '%'.", new_plugin.name_filetype, cast([]u8, new_plugin.magic_number), cast([]u8, found_mn));
			// Also do the whole magic number checking here so that the user can choose
			return false;
		}
	}

	pre_info := Pre_Rendering_Info.{
		name = filepath,
		fileptr = file_handle,
	};
	pre_info_err := new_plugin.pre_render(*pre_info);
	if pre_info_err {
		log_error("File metadata reading error: %", pre_info_err);
		return false;
	}

	print("%\n", pre_info);
	current_plugin = new_plugin;
	return true;
}

libc :: #import "POSIX";
