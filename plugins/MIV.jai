Provided_Registration_Entry :: struct {
	name_filetype: string;
	procedure_prefix: string;
	extension: string;
	magic_number: string;
	bytes_before_magic_number: int;
	extension_is_case_sensitive: bool;
	has_settings: bool;
}

Pre_Rendering_Info :: struct {
	name: string;
	fileptr: *posix.FILE;
	width, height: s64;

	bit_depth: u8;
	channels: u8;
	metadata: [][2]string;

	user_ptr: *void;
}

Rendering_Info :: struct {
	column_range: [2]s64;
	row_range: [2]s64;

	buffer_width: s64;
	buffer_height: s64;
	buffer: [][4]u8;
}

Settings_Info :: struct {
	options: []bool;
}

posix :: #import "POSIX";
