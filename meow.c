#include<stdint.h>

typedef struct {
	int64_t count;
	uint8_t *data;
} string;

typedef struct {
	string name_filetype;
	string function_prefix;
	string extension;
	string magic_number;
	int64_t bytes_before_magic_number;
	uint8_t has_magic_number;
	uint8_t extension_is_case_sensitive;
} Provided_Registration_Entry;

static int called_n_times;
const int TOTAL_IMAGE_FORMATS = 2;

int64_t registration_procedure(Provided_Registration_Entry *registration) {
	switch (called_n_times) {
	case 0:
		registration->name_filetype.count = 17;
		registration->name_filetype.data = "Netpbm binary PPM";

		registration->function_prefix.count = 4;
		registration->function_prefix.data = "ppm_";
	
		registration->extension.count = 3;
		registration->extension.data = "PPM";
	
		registration->magic_number.count = 2;
		registration->magic_number.data = "P6";
		
		registration->bytes_before_magic_number = 0;
		registration->extension_is_case_sensitive = 0;
		break;
	case 1:
		registration->name_filetype.count = 10;
		registration->name_filetype.data = "Netpbm PFM";

		registration->function_prefix.count = 4;
		registration->function_prefix.data = "pfm_";
	
		registration->extension.count = 3;
		registration->extension.data = "PFM";
	
		registration->magic_number.count = 2;
		registration->magic_number.data = "PF";
		
		registration->bytes_before_magic_number = 0;
		registration->extension_is_case_sensitive = 0;
		break;
	}
	called_n_times += 1;
	return TOTAL_IMAGE_FORMATS - called_n_times;
}
