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

Bitmap_Info_Header :: struct {
	dib_header_size, width, height: u32;
	planes, bits_per_pixel: u16;
	compression, image_size,
	x_pixels_per_meter, y_pixels_per_meter,
	colors_in_color_table, important_color_count: u32;
}

HEADER_SIZE :: size_of(Bitmap_File_Header) + size_of(Bitmap_Info_Header);

#add_context bmp_full_header: *Bitmap_Full_Header;
#add_context metadata_backing: [..][2]string;

Bitmap_Full_Header :: struct {
	file: Bitmap_File_Header;
	info: Bitmap_Info_Header #align 2;
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
	posix.fread(*(full_header.info), size_of(Bitmap_Info_Header), 1, info.fileptr);

	if file_length != full_header.file.file_size {
		return .{.ERROR, sprint("The header says this file should be % bytes, but it is % bytes.", full_header.file.file_size, file_length)};
	}

	info.width = full_header.info.width;
	info.height = full_header.info.height;
	info.bit_depth = xx (full_header.info.bits_per_pixel/3);
	info.channels = 3;

	log := Log.{};

	if full_header.info.image_size == 0 && info.width != 0 && info.height != 0 {
		line_width := info.width*full_header.info.bits_per_pixel/8;
		line_width += (4 - line_width%4)%4;
		full_header.info.image_size = xx (line_width*info.height);
	}

	if full_header.file.offset_to_pixels != HEADER_SIZE {
		log = .{.WARNING, sprint("Header size is nonstandard (expected % bytes, got % bytes).", HEADER_SIZE, full_header.file.offset_to_pixels)};
	}

	array_add(*context.metadata_backing, string.["bits per pixel", sprint("%", full_header.info.bits_per_pixel)]);
	array_add(*context.metadata_backing, string.["planes", sprint("%", full_header.info.planes)]);
	array_add(*context.metadata_backing, string.["compression", sprint("%", full_header.info.compression)]);
	array_add(*context.metadata_backing, string.["pixels/meter (X)", sprint("%", full_header.info.x_pixels_per_meter)]);
	array_add(*context.metadata_backing, string.["pixels/meter (Y)", sprint("%", full_header.info.y_pixels_per_meter)]);
	array_add(*context.metadata_backing, string.["colors in table", sprint("%", full_header.info.colors_in_color_table)]);
	array_add(*context.metadata_backing, string.["DIB header size", sprint("%", full_header.info.dib_header_size)]);
	if full_header.file.reserved[0] || full_header.file.reserved[1] {
		array_add(*context.metadata_backing, string.["Reserved 1", sprint("%", full_header.file.reserved[0])]);
		array_add(*context.metadata_backing, string.["Reserved 2", sprint("%", full_header.file.reserved[1])]);
	}
	info.metadata = .{context.metadata_backing.count, context.metadata_backing.data};

	context.bmp_full_header = full_header;

	// new_print_style := context.print_style;
	// new_print_style.default_format_struct.use_newlines_if_long_form = true;
	// new_print_style.default_format_array.stop_printing_after_this_many_elements = 4;
	// print("%: %\n", info.name, context.bmp_full_header.*,, print_style = new_print_style);

	return log;
}

#program_export
bmp_render :: (pre_info: *Pre_Rendering_Info, render_info: *Rendering_Info) -> Log #c_call {
	push_context,defer_pop pre_info.user_ptr.(*#Context);
	// new_print_style := context.print_style;
	// new_print_style.default_format_struct.use_newlines_if_long_form = true;
	// new_print_style.default_format_array.stop_printing_after_this_many_elements = 4;
	// log := Log.{.LOG, sprint("%", context.bmp_full_header.*,, print_style = new_print_style)};
	// log := Log.{.LOG, sprint("%", HEADER_SIZE)};
	log := Log.{};

	posix.fseek(pre_info.fileptr, context.bmp_full_header.file.offset_to_pixels, posix.SEEK_SET);

	buffer := NewArray(context.bmp_full_header.info.image_size, u8);
	defer array_reset(*buffer);

	posix.fread(buffer.data, 1, xx buffer.count, pre_info.fileptr);

	line_width := pre_info.width*context.bmp_full_header.info.bits_per_pixel/8;
	line_width += (4 - line_width%4)%4;

	pixel := u8.[0, 0, 0, 255];
	if context.bmp_full_header.info.bits_per_pixel == 24 for y: 0..pre_info.height-1 for x: 0..pre_info.width-1 {
		pixel[0] = buffer[0 + x*3 + y*line_width];
		pixel[1] = buffer[1 + x*3 + y*line_width];
		pixel[2] = buffer[2 + x*3 + y*line_width];
		render_info.buffer[x + (pre_info.height - y - 1)*pre_info.width] = pixel;
	} else if context.bmp_full_header.info.bits_per_pixel == 16 for y: 0..pre_info.height-1 for x: 0..pre_info.width-1 {
		p: u16 = buffer[x*2 + y*line_width] + buffer[1 + x*2 + y*line_width] << 8;
		pixel[0] = xx (( p        & 0x11111)*20);
		pixel[1] = xx (((p >> 5 ) & 0x11111)*20);
		pixel[2] = xx (((p >> 10) & 0x11111)*20);
		render_info.buffer[x + (pre_info.height - y - 1)*pre_info.width] = pixel;
	}

	return log;
}

#program_export
bmp_cleanup :: (info: *Pre_Rendering_Info) -> Log #c_call {
//	if !info.user_ptr info.user_ptr = __jai_runtime_init(0, null);
	push_context,defer_pop info.user_ptr.(*#Context);

	if context.bmp_full_header then free(context.bmp_full_header);
	if context.metadata_backing {
		for context.metadata_backing free(it[1].data);
		array_reset(*context.metadata_backing);
	}
	return .{};
}

/* unused as it is less common */
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

#import "Basic";
