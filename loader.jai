Pre_Rendering_Info :: struct {
	name: string;
	fileptr: *struct{};
	width, height: s64;
	metadata: string;
}

Provided_Registration_Entry :: struct {
	name_filetype: string;
	function_prefix: string;
	extension: string;
	magic_number: string;
	bytes_before_magic_number: int;
	extension_is_case_sensitive: bool;
}

Registration_Entry :: struct {
	filepath: string;
	using provided: Provided_Registration_Entry;
}

Registration_Procedure :: #type (registration: *Provided_Registration_Entry) -> s64 #c_call;

all_registrations: [..]Registration_Entry;
register_dynlib :: (dynlib_name: string) {
	dynlib_cname := temp_c_string(dynlib_name);

	handle := libc.dlopen(dynlib_cname, libc.RTLD_NOW);
	if !handle {
		print("Dynamic library loading error: %s\n", to_string(libc.dlerror()));
		exit(1);
	}
	libc.dlerror();

	reg_proc: Registration_Procedure = libc.dlsym(handle, "registration_procedure");
	loading_error := to_string(libc.dlerror());
	if loading_error {
		print("Dynamic function loading error: %s\n", loading_error);
		exit(1);
	}

	while true {
		registration := Registration_Entry.{filepath = dynlib_name};
		amount := reg_proc(*(registration.provided));
		array_add(*all_registrations, registration);
		print("%\n", registration);

		if amount == 0 break;
	}


	libc.dlclose(handle);
}

libc :: #import "POSIX";
