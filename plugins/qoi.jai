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
	info.metadata[0][0] = "colorspace";
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
	push_context,defer_pop pre_info.user_ptr.(*#Context);

	previous_pixel: [4]u8 = .[0, 0, 0, 255];
	previous_array: [64][4]u8;
	pixel_count := render_info.buffer.count;
	i := 0;
	while i < pixel_count {
		render_info.buffer[i] = .[200, 100, 100, 255];
		i += 1;
	}

	return "";
}

index_hash :: (pixel: [4]u8) -> u64 {
	return (pixel[0].(u64)*3 + pixel[1].(u64)*5 + pixel[2].(u64)*7 + pixel[3].(u64)*11) % 64;
}

#program_export
qoi_settings :: (pre_info: *Pre_Rendering_Info, render_info: *Rendering_Info, settings_info: *Settings_Info) -> string #c_call {
	push_context,defer_pop pre_info.user_ptr.(*#Context);
	if !settings_info.options {
		settings_info.options = NewArray(3, Option);

		settings_info.options[0] = .{
			name = "toggle setting",
			type = .TOGGLE,
			toggle = true
		};

		sec_list := NewArray(3, List_Item);
		sec_list[0] = .{true, "meow"};
		sec_list[1] = .{false, "wruff"};
		sec_list[2] = .{true, "nyaa"};
		settings_info.options[1] = .{
			name = "list of options",
			type = .LIST,
			list = sec_list
		};

		settings_info.options[2] = .{
			name = "toggle setting (sequel)",
			type = .TOGGLE,
			toggle = false
		};
		return "";
	}
	settings_info.response = .RE_RENDER;
	return "";
//	return "Settings not implemented.";
}

#program_export
qoi_cleanup :: (pre_info: *Pre_Rendering_Info) -> string #c_call {
	return "";
}

#load "MIV.jai";
#import "Basic";
#import "Bit_Operations";
