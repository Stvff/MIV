#include "MIV.h"
#include <stdlib.h>

/* This is here because there is DIB and several different magic numbers that I want to support in the future */
static int called_n_times;
const int TOTAL_IMAGE_FORMATS = 1;

int64_t registration_procedure(Plugin_Registration_Entry *registration) {
	switch (called_n_times) {
	case 0:
		registration->name_of_filetype = to_string("Microsoft BitMap");
		registration->extension = to_string("BMP");
		registration->magic_number = to_string("BM");
		registration->procedure_prefix = to_string("bmp_");
	}
	called_n_times += 1;
	return TOTAL_IMAGE_FORMATS - called_n_times;
}

Log bmp_pre_render(Pre_Rendering_Info *pre_info) {
	Log log = (Log){0};
	return log;
}

Log bmp_render(Pre_Rendering_Info *pre_info, Rendering_Info *render_info) {
	Log log = (Log){0};
	return log;
}

Log bmp_cleanup(Pre_Rendering_Info *pre_info) {
	return (Log){0};
}
