#include "MIV.h"

static int called_n_times;
const int TOTAL_IMAGE_FORMATS = 2;

int64_t registration_procedure(Provided_Registration_Entry *registration) {
	switch (called_n_times) {
	case 0:
		registration->name_filetype = to_string("Netpbm binary PPM");

		registration->procedure_prefix = to_string("ppm_");

		registration->extension = to_string("PPM");

		registration->magic_number = to_string("P6");

		registration->extension_is_case_sensitive = 0;
		break;
	case 1:
		registration->name_filetype = to_string("Netpbm PFM");

		registration->procedure_prefix = to_string("pfm_");

		registration->extension = to_string("PFM");

		registration->magic_number = to_string("PF");

		registration->extension_is_case_sensitive = 0;
		break;
	}
	called_n_times += 1;
	return TOTAL_IMAGE_FORMATS - called_n_times;
}

string ppm_pre_render(Pre_Rendering_Info *pre_info) {
	pre_info->width = 10;
	pre_info->height = 12;
	return (string){0};
}

string ppm_render(Pre_Rendering_Info *pre_info, Rendering_Info *render_info) {
	return (string){0};
}

string pfm_pre_render(Pre_Rendering_Info *pre_info) {
	pre_info->width = 20;
	pre_info->height = 22;
	return (string){0};
}

string pfm_render(Pre_Rendering_Info *pre_info, Rendering_Info *render_info) {
	return (string){0};
}
