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

	QOI_HEADER_SIZE :: 14;
	/* reading the entire file first */
	posix.fseek(pre_info.fileptr, 0, posix.SEEK_END);
	file: []u8;
	file.count = posix.ftell(pre_info.fileptr) - QOI_HEADER_SIZE;
	file.data = alloc(file.count);
	defer free(file.data);
	posix.fseek(pre_info.fileptr, QOI_HEADER_SIZE, posix.SEEK_SET);
	posix.fread(file.data, 1, xx file.count, pre_info.fileptr);

	previous_pixel: [4]u8 = .[0, 0, 0, 255];
	previous_array: [64][4]u8;
	pixel_count := render_info.buffer.count;
	decoded := 0;
	coded := 0;
	while decoded < pixel_count {
		/* add possible corruption errors to this */
		if file[coded] == {
		case QOI_OP_RGB;
			previous_pixel[0] = file[coded+1];
			previous_pixel[1] = file[coded+2];
			previous_pixel[2] = file[coded+3];
			previous_array[index_hash(previous_pixel)] = previous_pixel;
			render_info.buffer[decoded] = previous_pixel;
			decoded += 1;
			coded += 4;
		case QOI_OP_RGBA;
			previous_pixel[0] = file[coded+1];
			previous_pixel[1] = file[coded+2];
			previous_pixel[2] = file[coded+3];
			previous_pixel[3] = file[coded+4];
			previous_array[index_hash(previous_pixel)] = previous_pixel;
			render_info.buffer[decoded] = previous_pixel;
			decoded += 1;
			coded += 5;
		case; op_value := file[coded] & QOI_6BIT_MASK;
			// print("%\n", op_value);
		if file[coded] & QOI_2BIT_MASK == {
		case QOI_OP_INDEX;
			previous_pixel = previous_array[op_value];
			render_info.buffer[decoded] = previous_pixel;
			decoded += 1;
			coded += 1;

		case QOI_OP_DIFF;
			diff := op_value & QOI_OP_DIFF_MASK; op_value >>= 2;
			previous_pixel[2] += diff - 2;
			diff = op_value & QOI_OP_DIFF_MASK; op_value >>= 2;
			previous_pixel[1] += diff - 2;
			diff = op_value & QOI_OP_DIFF_MASK;
			previous_pixel[0] += diff - 2;

			previous_array[index_hash(previous_pixel)] = previous_pixel;
			render_info.buffer[decoded] = previous_pixel;
			decoded += 1;
			coded += 1;

		case QOI_OP_LUMA;
			dg := op_value - 32;
			db_dg := (file[coded+1] & QOI_OP_LUMA_MASK) - 8;
			dr_dg := ((file[coded+1]>>4) & QOI_OP_LUMA_MASK) - 8;
			db := db_dg + dg;
			dr := dr_dg + dg;
			previous_pixel[0] += dr;
			previous_pixel[1] += dg;
			previous_pixel[2] += db;

			previous_array[index_hash(previous_pixel)] = previous_pixel;
			render_info.buffer[decoded] = previous_pixel;
			decoded += 1;
			coded += 2;

		case QOI_OP_RUN;
			for 0..op_value {
				render_info.buffer[decoded] = previous_pixel;
				decoded += 1;
			}
			coded += 1;
		}}
		if coded >= file.count break;
	}

	return "";
}

QOI_OP_RGB    :u8: 0b1111_1110;
QOI_OP_RGBA   :u8: 0b1111_1111;
QOI_2BIT_MASK :u8: 0b11_000000;
QOI_6BIT_MASK :u8: 0b00_111111;
QOI_OP_INDEX  :u8: 0b00_000000;
QOI_OP_DIFF   :u8: 0b01_000000; QOI_OP_DIFF_MASK :u8: 0b000000_11;
QOI_OP_LUMA   :u8: 0b10_000000; QOI_OP_LUMA_MASK :u8: 0b0000_1111;
QOI_OP_RUN    :u8: 0b11_000000;

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
