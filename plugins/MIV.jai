/*** The next three structs are used in the mandatory functions. ***/

/* Entirely filled in by the Plugin. */
Plugin_Registration_Entry :: struct {
	name_of_filetype: string;
	extension: string;
	magic_number: string;

	procedure_prefix: string;
	has_settings: bool;
}

Pre_Rendering_Info :: struct {
	/* <Provided by MIV> */
	name: string;
	fileptr: *posix.FILE;
	/* <Provided by MIV/> */
	/* <Provided by Plugin> */
	width, height: s64;
	bit_depth: u8;
	channels: u8;
	metadata: [][2]string;

	user_ptr: *void;
	/* <Provided by Plugin/> */
}

/* Entirely filled in by MIV, except for the values in the buffer. */
Rendering_Info :: struct {
	buffer: [][4]u8;
}

/*** From here it is about the optional features (like plugin settings). ***/
Settings_Response :: enum s32 {
	NOTHING; RE_RENDER;
}

Setting_Info :: struct {
	provided_ID: s32;

	name: string;
	type: enum u8 {TOGGLE; LIST; SLIDER;};
}

Setting_Toggle :: struct {
	#as using info: Setting_Info;
	active: bool;
}

List_Item :: struct {
	active: bool;
	name: string;
}
Setting_List :: struct {
	#as using info: Setting_Info;
	changed_item: s64;
	items: []List_Item;
}

Setting_Slider :: struct {
	#as using info: Setting_Info;
	value_text: string;
	value: float;
}

posix :: #import "POSIX";

/* For MIV internal usage */
Plugin_Setting :: union {
	info: Setting_Info;
	toggle: Setting_Toggle;
	list: Setting_List;
	slider: Setting_Slider;
}
