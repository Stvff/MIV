#include "MIV.h"
#include <stdlib.h>

int64_t registration_procedure(Plugin_Registration_Entry *registration) {
	registration->name_of_filetype = to_string("Vanadis Image");
	registration->procedure_prefix = to_string("vaim_");
	registration->extension = to_string("VAIM");
	registration->magic_number = to_string("vaim");
	return 0;
}

static uint16_t bytes_per_pixel = 0;
string vaim_pre_render(Pre_Rendering_Info *pre_info) {
	fseek(pre_info->fileptr, 6, SEEK_SET);
	fread(&(pre_info->channels), 1, 2, pre_info->fileptr);
	bytes_per_pixel = pre_info->channels;
	pre_info->bit_depth = 8;
	fseek(pre_info->fileptr, 8, SEEK_CUR);
	fread(&(pre_info->width), 1, 8, pre_info->fileptr);
	fread(&(pre_info->height), 1, 8, pre_info->fileptr);

	return (string){0};
}

string vaim_render(Pre_Rendering_Info *pre_info, Rendering_Info *render_info) {
	fseek(pre_info->fileptr, 32, SEEK_SET);
	uint64_t data_count = pre_info->width*pre_info->height*bytes_per_pixel;
	uint8_t *data = malloc(data_count);
	fread(data, 1, data_count, pre_info->fileptr);

	uint64_t pixel_count = data_count/bytes_per_pixel;
	for (int i = 0; i < pixel_count; i += 1) {
		render_info->buffer[i][3] = 255;
		for (int ii = 0; ii < bytes_per_pixel && ii < 4; ii += 1) {
			render_info->buffer[i][ii] = data[(pixel_count - i - 1)*bytes_per_pixel + ii];
		}
	}

	free(data);
	return (string){0};
}

string vaim_cleanup(Pre_Rendering_Info *pre_info) {
	return (string){0};
}
