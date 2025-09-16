#include "MIV.h"
#include <stdlib.h>

/* helper functions */
uint8_t is_white_space(char c) {
	return c=='\n' || c=='\r' || c=='\t' || c==' ';
}

uint8_t is_digit(char c) {
	return '0' <= c && c <= '9';
}

void skip_white_space(FILE *fileptr) {
	char c = 0;
	do c = fgetc(fileptr);
	while (is_white_space(c));
	fseek(fileptr, -1, SEEK_CUR);
}

void skip_line(FILE *fileptr) {
	char c = 0;
	do c = fgetc(fileptr);
	while (c != '\n');
}

void skip_comments(FILE *fileptr) {
	char c = fgetc(fileptr);
	while (c == '#') {
		skip_line(fileptr);
		c = fgetc(fileptr);
	}
	fseek(fileptr, -1, SEEK_CUR);
}

/* the actual plugin */
static int called_n_times;
const int TOTAL_IMAGE_FORMATS = 2;

int64_t registration_procedure(Provided_Registration_Entry *registration) {
	switch (called_n_times) {
	case 0:
		registration->name_filetype = to_string("Netpbm Portable PixMap");
		registration->procedure_prefix = to_string("ppm_");
		registration->extension = to_string("PPM");
		registration->magic_number = to_string("P");
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

typedef struct {
	int max_ppm_value;
	int64_t start_of_image;
	bool is_binary;
	char pixel_value_string_buffer[16];
} Specifics;

string ppm_pre_render(Pre_Rendering_Info *pre_info) {
	Specifics *specifics;
	if (!pre_info->user_ptr) {
		specifics = malloc(sizeof(Specifics));
		*specifics = (Specifics){0};
		pre_info->user_ptr = specifics;
	} else specifics = pre_info->user_ptr;

	/* Checking the header */
	fseek(pre_info->fileptr, 0, SEEK_SET);
	char c = fgetc(pre_info->fileptr);
	if (c != 'P') {
		string warning = to_string("PPM files must start with either 'P3' or 'P6', but the first character was ' '.");
		char *bare_warning = warning.data;
		warning.data = malloc(warning.count + 1);
		memcpy(warning.data, bare_warning, warning.count+1);
		warning.data[warning.count - 2] = c;
		return warning;
	}
	c = fgetc(pre_info->fileptr);
	if (c != '3' && c != '6') {
		string warning = to_string("PPM files must start with either 'P3' or 'P6', but the second character was ' '.");
		char *bare_warning = warning.data;
		warning.data = malloc(warning.count + 1);
		memcpy(warning.data, bare_warning, warning.count+1);
		warning.data[warning.count - 2] = c;
		return warning;
	}
	if (c == '6') specifics->is_binary = 1;
	fseek(pre_info->fileptr, 3, SEEK_SET);

	/* read the width */
	c = '0';
	skip_white_space(pre_info->fileptr);
	skip_comments(pre_info->fileptr); /* these comments could be added to the metadata section imo */
	do {
		pre_info->width = pre_info->width*10 + (c - '0');
		c = fgetc(pre_info->fileptr);
	} while (is_digit(c));
	fseek(pre_info->fileptr, -1, SEEK_CUR);

	/* read the height */
	c = '0';
	skip_white_space(pre_info->fileptr);
	skip_comments(pre_info->fileptr); /* these comments could be added to the metadata section imo */
	do {
		pre_info->height = pre_info->height*10 + (c - '0');
		c = fgetc(pre_info->fileptr);
	} while (is_digit(c));
	fseek(pre_info->fileptr, -1, SEEK_CUR);

	/* reading the max value */
	specifics->max_ppm_value = 0;
	c = '0';
	skip_white_space(pre_info->fileptr);
	skip_comments(pre_info->fileptr); /* these comments could be added to the metadata section imo */
	do {
		specifics->max_ppm_value = specifics->max_ppm_value*10 + (c - '0');
		c = fgetc(pre_info->fileptr);
	} while (is_digit(c));
	/* not fseeking back, because that last newline was in fact the final newline */
	specifics->start_of_image = ftell(pre_info->fileptr);

	if (specifics->max_ppm_value <= 255) pre_info->bit_depth = 8;
	else if (specifics->max_ppm_value <= 65535) pre_info->bit_depth = 16;
	pre_info->channels = 3;
	if (pre_info->bit_depth > 8) {
		return to_string("The PPM plugin currently does not support conversion of 16 bit to 8 bit.");
	}

	/* adding the max pixel value to the metadata */
	pre_info->metadata_count += 1;
	pre_info->metadata = realloc(pre_info->metadata, pre_info->metadata_count*sizeof(string[2]));
	pre_info->metadata[pre_info->metadata_count-1][0] = to_string("Max pixel value");
	sprintf((char*) &specifics->pixel_value_string_buffer, "%d", specifics->max_ppm_value);
	pre_info->metadata[pre_info->metadata_count-1][1] = to_string((char*) &specifics->pixel_value_string_buffer);

	return (string){0};
}

string ppm_render(Pre_Rendering_Info *pre_info, Rendering_Info *render_info) {
	Specifics *specifics = pre_info->user_ptr;
	if (specifics->is_binary) {
		int64_t distance = pre_info->channels*pre_info->bit_depth/8;
		uint8_t *file_data = malloc(render_info->buffer_count*distance);

		fseek(pre_info->fileptr, specifics->start_of_image, SEEK_SET);
		fread(file_data, 1, render_info->buffer_count*distance, pre_info->fileptr);

		for (int64_t i = 0; i < render_info->buffer_count; i += 1) {
			render_info->buffer[i][0] = file_data[i*distance + 0];
			render_info->buffer[i][1] = file_data[i*distance + 1];
			render_info->buffer[i][2] = file_data[i*distance + 2];
			render_info->buffer[i][3] = 255;
		}

		free(file_data);
		return (string){0};
	} else {
		fseek(pre_info->fileptr, 0, SEEK_END);
		string file;
		file.count = ftell(pre_info->fileptr) - specifics->start_of_image;
		file.data = malloc(file.count);

		fseek(pre_info->fileptr, specifics->start_of_image, SEEK_SET);
		fread(file.data, 1, file.count, pre_info->fileptr);

		int64_t file_i = 0;
		for (int64_t i = 0; i < render_info->buffer_count; i += 1) {
			uint8_t pixel[3] = {0};
			for (int ii = 0; ii < 3; ii += 1) {
				while (is_white_space(file.data[file_i])) file_i += 1;
				for (int iii = 0; iii < 3; iii += 1) {
					char c = file.data[file_i];
					if (is_white_space(c)) break;
					pixel[ii] *= 10;
					pixel[ii] += c - '0';
					file_i += 1;
				}
			}

			render_info->buffer[i][0] = pixel[0];
			render_info->buffer[i][1] = pixel[1];
			render_info->buffer[i][2] = pixel[2];
			render_info->buffer[i][3] = 255;
		}

		free(file.data);
		return (string){0};
	}
}

string ppm_cleanup(Pre_Rendering_Info *pre_info) {
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

string pfm_cleanup(Pre_Rendering_Info *pre_info) {
	return (string){0};
}
