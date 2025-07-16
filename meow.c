#include "MIV.h"

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

int max_ppm_value = 0;
string ppm_pre_render(Pre_Rendering_Info *pre_info) {
	/* ignore the header */
	fseek(pre_info->fileptr, 3, SEEK_SET);

	/* read the width */
	char c = '0';
	skip_white_space(pre_info->fileptr);
	skip_comments(pre_info->fileptr); /* these comments could be added to the metadata section imo */
	do {
		pre_info->width = pre_info->width*10 + (c - '0');
		c = fgetc(pre_info->fileptr);
	} while (is_digit(c));
	fseek(pre_info->fileptr, -1, SEEK_SET);

	/* read the height */
	c = '0';
	skip_white_space(pre_info->fileptr);
	skip_comments(pre_info->fileptr); /* these comments could be added to the metadata section imo */
	do {
		pre_info->height = pre_info->height*10 + (c - '0');
		c = fgetc(pre_info->fileptr);
	} while (is_digit(c));
	fseek(pre_info->fileptr, -1, SEEK_SET);

	/* reading the max value */
	max_ppm_value = 0;
	c = '0';
	skip_white_space(pre_info->fileptr);
	skip_comments(pre_info->fileptr); /* these comments could be added to the metadata section imo */
	do {
		max_ppm_value = max_ppm_value*10 + (c - '0');
		c = fgetc(pre_info->fileptr);
	} while (is_digit(c));
	/* not fseeking back, because that last newline was in fact the final newline */

	if (max_ppm_value <= 255) pre_info->bit_depth = 8;
	else if (max_ppm_value <= 65535) pre_info->bit_depth = 16;
	pre_info->channels = 3;

	return (string){0};
}

string ppm_render(Pre_Rendering_Info *pre_info, Rendering_Info *render_info) {
	return (string){0};
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
