#load "MIV.jai";

/* This is here because there is DIB and several different magic numbers that I want to support in the future */
called_n_times := 0;
TOTAL_IMAGE_FORMATS :: 1;

#program_export
registration_procedure :: (registration: *Plugin_Registration_Entry) -> s64 #c_call {
	if called_n_times == {
	case 0;
		registration.name_of_filetype = "Microsoft BitMap";
		registration.extension = "BMP";
		registration.magic_number = "BM";
		registration.procedure_prefix = "bmp_";
	}
	called_n_times += 1;
	return TOTAL_IMAGE_FORMATS - called_n_times;
}

Bitmap_File_Header :: struct {
	signature: [2]u8 = .["B", "M"];
	file_size: u32 #align 2;
	reserved: [2]u16;
	offset_to_pixels: u32 #align 2;
}

Bitmap_V5_Header :: struct {
	dib_header_size, width, height: u32;
	planes, bits_per_pixel: u16;
	compression, image_size,
	x_pixels_per_meter, y_pixels_per_meter,
	colors_in_color_table, important_color_count,
	red_channel_bitmask, green_channel_bitmask, blue_channel_bitmask, alpha_channel_bitmask,
	color_space_type: u32;
	color_space_endpoints: [36]u8;
	gamma_for_red_channel, gamma_for_green_channel, gamma_for_blue_channel,
	intent,
	icc_profile_data, icc_profile_size,
	reserved: u32;
}

HEADER_SIZE :: size_of(Bitmap_File_Header) + size_of(Bitmap_V5_Header);

Bitmap_Full_Header :: struct {
	file: Bitmap_File_Header;
	v5: Bitmap_V5_Header #align 2;
}

#program_export
bmp_pre_render :: (info: *Pre_Rendering_Info) -> Log #c_call {
	if !info.user_ptr info.user_ptr = __jai_runtime_init(0, null);
	push_context,defer_pop info.user_ptr.(*#Context);

	posix.fseek(info.fileptr, 0, posix.SEEK_END);
	file_length := posix.ftell(info.fileptr);
	if file_length < HEADER_SIZE {
		return .{.ERROR, sprint("Expected a filesize of at least % bytes, but found only % bytes.", HEADER_SIZE, file_length)};
	}
	posix.fseek(info.fileptr, 0, posix.SEEK_SET);

	full_header := New(Bitmap_Full_Header);
	posix.fread(*(full_header.file), size_of(Bitmap_File_Header), 1, info.fileptr);
	posix.fread(*(full_header.v5), size_of(Bitmap_V5_Header), 1, info.fileptr);

	if file_length != full_header.file.file_size {
		return .{.ERROR, sprint("The header says this file should be % bytes, but it is % bytes.", full_header.file.file_size, file_length)};
	}

	info.width = full_header.v5.width;
	info.height = full_header.v5.height;
	info.bit_depth = xx (full_header.v5.bits_per_pixel/3);
	info.channels = 3;

	new_print_style := context.print_style;
	new_print_style.default_format_struct.use_newlines_if_long_form = true;
	new_print_style.default_format_array.stop_printing_after_this_many_elements = 4;
	log := Log.{.LOG, sprint("%\n", full_header.*,, print_style = new_print_style)};

	//context.user_ptr = full_header;
	return log;
}

#program_export
bmp_render :: (pre_info: *Pre_Rendering_Info, render_info: *Rendering_Info) -> Log #c_call {
	log := Log.{};
	return log;
}

#program_export
bmp_cleanup :: (info: *Pre_Rendering_Info) -> Log #c_call {
	//if !info.user_ptr info.user_ptr = __jai_runtime_init(0, null);
	//push_context,defer_pop info.user_ptr.(*#Context);

	//if context.user_ptr then free(context.user_ptr);
	return .{};
}

#import "Basic";
