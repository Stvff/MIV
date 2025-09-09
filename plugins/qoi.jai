called_n_times := 0;
TOTAL_IMAGE_FORMATS :: 1;

#program_export
registration_procedure :: (registration: *Provided_Registration_Entry) -> s64 #c_call {
	registration.* = .{
		name_filetype = "Quite Ok Image Format",
		procedure_prefix = "qoi_",
		extension = "qoi",
		magic_number = "qoif",
		bytes_before_magic_number = 0,
		extension_is_case_sensitive = false,
		has_settings = true,
	};
	return 0;
}

#program_export
qoi_pre_render :: (info: *Pre_Rendering_Info) -> string #c_call {
	return "Not implemented";
}

#program_export
qoi_render :: (pre_info: *Pre_Rendering_Info, render_info: *Rendering_Info) -> string #c_call {
	return "Not implemented";
}

#program_export
qoi_settings :: (pre_info: *Pre_Rendering_Info, render_info: *Rendering_Info, settings_info: *Settings_Info) -> string #c_call {
	return "Not implemented";
}

#program_export
qoi_cleanup :: (pre_info: *Pre_Rendering_Info) -> string #c_call {
	return "Not implemented";
}

#load "MIV.jai";
