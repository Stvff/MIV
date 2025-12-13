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
}

#program_export
bmp_pre_render :: (pre_info: *Pre_Rendering_Info) -> Log #c_call {
	log := Log.{};
	return log;
}

#program_export
bmp_render :: (pre_info: *Pre_Rendering_Info, render_info: *Rendering_Info) -> Log #c_call {
	log := Log.{};
	return log;
}

#program_export
bmp_cleanup :: (pre_info: *Pre_Rendering_Info) -> Log #c_call {
	return .{};
}
