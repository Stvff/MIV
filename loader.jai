Pre_Rendering_Info :: struct {
	name: string;
	fileptr: *struct{};
	width, height: s64;
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

all_registrations: [..]Registration_Entry;
register_dynlib :: (dynlib_name: string) -> bool {
	dynlib_cname := temp_c_string(dynlib_name);

	handle := libc.dlopen(dynlib_cname, libc.RTLD_NOW);
	if !handle {
		log("Dynamic library loading error: %", to_string(libc.dlerror()));
		return false;
	}
	libc.dlerror();

	reg_proc: Registration_Procedure = libc.dlsym(handle, "registration_procedure");
	loading_error := to_string(libc.dlerror());
	if loading_error {
		log("Dynamic function loading error: %", loading_error);
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
			log("Dynamic function loading error: %", to_string(libc.dlerror()));
			success = false;
		}
		libc.dlerror();

		render_cname := temp_c_string(tprint("%1%2", p.procedure_prefix, "render"));
		render_handle := libc.dlsym(handle, render_cname);
		if !render_handle {
			log("Dynamic function loading error: %", to_string(libc.dlerror()));
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

libc :: #import "POSIX";
