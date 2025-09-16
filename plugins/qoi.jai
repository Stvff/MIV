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
	if !info.user_ptr info.user_ptr = __jai_runtime_init(0, null);
	push_context,defer_pop info.user_ptr.(*#Context);

	posix.fseek(info.fileptr, 0, posix.SEEK_END);
	file_length := posix.ftell(info.fileptr);
	if file_length < 22 {
		return sprint("Expected a filesize of at least 22 bytes (14 header, 8 end token), but found only % bytes.",  file_length);
	}
	posix.fseek(info.fileptr, 4, posix.SEEK_SET);

	width: u32 = ---;
	posix.fread(*width, 4, 1, info.fileptr);
	byte_swap_in_place(*width);
	info.width = width;

	height: u32 = ---;
	posix.fread(*height, 4, 1, info.fileptr);
	byte_swap_in_place(*height);
	info.height = height;

	posix.fread(*info.channels, 1, 1, info.fileptr);
	info.bit_depth = 8;
	colorspace: u8 = ---;
	posix.fread(*colorspace, 1, 1, info.fileptr);
	info.metadata = NewArray(1, [2]string);
	info.metadata[0][0] = "Colorspace";
	if colorspace == {
	case 0;
		info.metadata[0][1] = "sRGB";
	case 1;
		info.metadata[0][1] = "Linear";
	case;
		info.metadata[0][1] = sprint("'%'");
	}
	return "";
}

#program_export
qoi_render :: (pre_info: *Pre_Rendering_Info, render_info: *Rendering_Info) -> string #c_call {
	return "";
}

#program_export
qoi_settings :: (pre_info: *Pre_Rendering_Info, render_info: *Rendering_Info, settings_info: *Settings_Info) -> string #c_call {
	return "settings not implemented";
}

#program_export
qoi_cleanup :: (pre_info: *Pre_Rendering_Info) -> string #c_call {
	return "";
}

#load "MIV.jai";
#import "Basic";
#import "Bit_Operations";
