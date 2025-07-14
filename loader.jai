Pre_Rendering_Info :: struct {
	name: string;
	fileptr: *struct{};
	width, height: s64;
	metadata: string;
}

Provided_Registration_Entry :: struct {
	function_prefix: string;
	extension: string;
	magic_number: string;
	bytes_before_magic_number: int;
}

Registration_Entry :: struct {
	filepath: string;
	using provided: Provided_Registration_Entry;
}
