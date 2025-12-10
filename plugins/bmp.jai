#load "MIV.jai";

/* This is here because there is DIB and several different magic numbers that I want to support in the future */
called_n_times: int;
TOTAL_IMAGE_FORMATS :: 1;

registration_procedure :: (registration: *Plugin_Registration_Entry) -> s64 {
	if called_n_times == {
	case 0;
		registration.name_of_filetype = to_string("Microsoft BitMap");
		registration.extension = to_string("BMP");
		registration.magic_number = to_string("BM");
		registration.procedure_prefix = to_string("bmp_");
	}
	called_n_times += 1;
	return TOTAL_IMAGE_FORMATS - called_n_times;
}

Bitmap_File_Header :: struct {
	signature: [2]u8 = .["B", "M"];
}

bmp_pre_render :: (pre_info: *Pre_Rendering_Info) -> Log {
	log := Log.{};
	return log;
}

bmp_render :: (pre_info: *Pre_Rendering_Info, render_info: *Rendering_Info) -> Log {
	log := Log.{};
	return log;
}

bmp_cleanup :: (pre_info: *Pre_Rendering_Info) -> Log {
	return .{};
}
