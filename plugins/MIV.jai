/*** The next three structs are used in the mandatory functions. ***/

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
	buffer_width: s64;
	buffer_height: s64;
	buffer: [][4]u8;
}

/*** From here it is about the optional features (like plugin settings). ***/

List_Item :: struct {
	selected: bool;
	name: string;
}

Option_Type :: enum u8 {
	TOGGLE; LIST;
}

Option :: struct {
	name: string;
	type: Option_Type;
	union {
		toggle: bool;
		list: []List_Item;
	};
}

Settings_Info :: struct {
	response: Settings_Response;
	changed_index: s32;
	changed_secondary_index: s32;
	options: []Option;
}

Settings_Response :: enum u8 {
	NOTHING; RE_RENDER;
}

posix :: #import "POSIX";
