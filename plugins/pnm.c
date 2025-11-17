/*   https://en.wikipedia.org/wiki/Netpbm   */
#include "MIV.h"
#include <stdlib.h>

/*# helper functions */
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

/*# the actual plugin */
static int called_n_times;
const int TOTAL_IMAGE_FORMATS = 3;

int64_t registration_procedure(Plugin_Registration_Entry *registration) {
	switch (called_n_times) {
	case 0:
		registration->name_of_filetype = to_string("Netpbm Portable BitMap");
		registration->extension = to_string("PBM");
		registration->magic_number = to_string("P"); /* P1 P4 */
		registration->procedure_prefix = to_string("pbm_");
		break;
	case 1:
		registration->name_of_filetype = to_string("Netpbm Portable GrayMap");
		registration->extension = to_string("PGM");
		registration->magic_number = to_string("P"); /* P2 P5 */
		registration->procedure_prefix = to_string("pgm_");
		break;
	case 2:
		registration->name_of_filetype = to_string("Netpbm Portable PixMap");
		registration->extension = to_string("PPM");
		registration->magic_number = to_string("P"); /* P3 P6 */
		registration->procedure_prefix = to_string("ppm_");
		break;
	}
	called_n_times += 1;
	return TOTAL_IMAGE_FORMATS - called_n_times;
}

typedef struct {
	int max_pixel_value;
	int64_t start_of_image;
	bool is_binary;
	uint8_t which_type;
	char pixel_value_string_buffer[16];
} Specifics;
enum {TYPE_PBM = 1, TYPE_PGM = 2, TYPE_PPM = 3};

Log generic_pre_render(Pre_Rendering_Info *pre_info) {
	Specifics *specifics = pre_info->user_ptr;
	Log log = (Log){0};

	/*# Checking the header */
	fseek(pre_info->fileptr, 1, SEEK_SET);
	char c = fgetc(pre_info->fileptr);
	if (c - '0' != specifics->which_type && c - '3' != specifics->which_type) {
		string header_warning = to_string("PBM files must start with either 'P0' or 'P3', but the second character was ' '.");;
		header_warning.data[35] += specifics->which_type;
		header_warning.data[43] += specifics->which_type;
		if (specifics->which_type == TYPE_PGM) header_warning.data[1] = 'G';
		else if (specifics->which_type == TYPE_PPM) header_warning.data[1] = 'P';
		header_warning.data[header_warning.count-3] = c;

		log.type = LOG_TYPE_WARNING;
		log.message = header_warning;
	}
	if (c - '3' == specifics->which_type) specifics->is_binary = 1;
	fseek(pre_info->fileptr, 3, SEEK_SET);

	/*# adding if it is ascii_encoded to the metadata */
	pre_info->metadata_count += 1;
	pre_info->metadata = realloc(pre_info->metadata, pre_info->metadata_count*sizeof(string[2]));
	pre_info->metadata[pre_info->metadata_count-1][0] = to_string("encoding");
	if (specifics->is_binary) pre_info->metadata[pre_info->metadata_count-1][1] = to_string("binary");
	else  pre_info->metadata[pre_info->metadata_count-1][1] = to_string("ASCII");

	/*# read the width */
	c = '0';
	skip_white_space(pre_info->fileptr);
	skip_comments(pre_info->fileptr); /* these comments could be added to the metadata section imo */
	do {
		pre_info->width = pre_info->width*10 + (c - '0');
		c = fgetc(pre_info->fileptr);
	} while (is_digit(c));
	fseek(pre_info->fileptr, -1, SEEK_CUR);

	/*# read the height */
	c = '0';
	skip_white_space(pre_info->fileptr);
	skip_comments(pre_info->fileptr); /* these comments could be added to the metadata section imo */
	do {
		pre_info->height = pre_info->height*10 + (c - '0');
		c = fgetc(pre_info->fileptr);
	} while (is_digit(c));

	if (specifics->which_type == TYPE_PPM) pre_info->channels = 3;
	else pre_info->channels = 1;

	if (specifics->which_type == TYPE_PBM) {
		pre_info->bit_depth = 1;
		/* not fseeking back, because that last newline was in fact the final newline */
		specifics->start_of_image = ftell(pre_info->fileptr);
		return log;
	}
	fseek(pre_info->fileptr, -1, SEEK_CUR);

	/*# reading the max value */
	specifics->max_pixel_value = 0;
	c = '0';
	skip_white_space(pre_info->fileptr);
	skip_comments(pre_info->fileptr); /* these comments could be added to the metadata section imo */
	do {
		specifics->max_pixel_value = specifics->max_pixel_value*10 + (c - '0');
		c = fgetc(pre_info->fileptr);
	} while (is_digit(c));
	/* not fseeking back, because that last newline was in fact the final newline */
	specifics->start_of_image = ftell(pre_info->fileptr);

	if (specifics->max_pixel_value <= 255) pre_info->bit_depth = 8;
	else if (specifics->max_pixel_value <= 65535) pre_info->bit_depth = 16;
	if (pre_info->bit_depth > 8) {
		log.type = LOG_TYPE_ERROR;
		log.message = to_string("The PNM plugin currently does not support conversion of 16 bit to 8 bit.");
		return log;
	}

	/*# adding the max pixel value to the metadata */
	pre_info->metadata_count += 1;
	pre_info->metadata = realloc(pre_info->metadata, pre_info->metadata_count*sizeof(string[2]));
	pre_info->metadata[pre_info->metadata_count-1][0] = to_string("max pixel value");
	sprintf((char*) &specifics->pixel_value_string_buffer, "%d", specifics->max_pixel_value);
	pre_info->metadata[pre_info->metadata_count-1][1] = to_string((char*) &specifics->pixel_value_string_buffer);

	return log;
}

Log ppm_pre_render(Pre_Rendering_Info *pre_info) {
	Specifics *specifics;
	if (!pre_info->user_ptr) {
		specifics = malloc(sizeof(Specifics));
		*specifics = (Specifics){0};
		pre_info->user_ptr = specifics;
	} else specifics = pre_info->user_ptr;

	specifics->which_type = TYPE_PPM;
	return generic_pre_render(pre_info);
}

Log ppm_render(Pre_Rendering_Info *pre_info, Rendering_Info *render_info) {
	Specifics *specifics = pre_info->user_ptr;
	Log log = (Log){0};

	fseek(pre_info->fileptr, 0, SEEK_END);
	string file;
	file.count = ftell(pre_info->fileptr) - specifics->start_of_image;
	file.data = malloc(file.count);

	fseek(pre_info->fileptr, specifics->start_of_image, SEEK_SET);
	fread(file.data, 1, file.count, pre_info->fileptr);

	if (specifics->is_binary) {
		int64_t distance = pre_info->channels*pre_info->bit_depth/8;
		for (int64_t i = 0; i < render_info->buffer_count; i += 1) {
			render_info->buffer[i][0] = ((int)file.data[i*distance + 0])*255/specifics->max_pixel_value;
			render_info->buffer[i][1] = ((int)file.data[i*distance + 1])*255/specifics->max_pixel_value;
			render_info->buffer[i][2] = ((int)file.data[i*distance + 2])*255/specifics->max_pixel_value;
			render_info->buffer[i][3] = 255;
		}
	} else {
		int64_t file_i = 0;
		for (int64_t i = 0; i < render_info->buffer_count; i += 1) {
			uint8_t pixel[3] = {0};
			for (int ii = 0; ii < 3; ii += 1) {
				if (file_i >= file.count) break;
				while (is_white_space(file.data[file_i])) file_i += 1;
				char c = file.data[file_i];
				while (!is_white_space(c)) {
					c = file.data[file_i];
					pixel[ii] *= 10;
					pixel[ii] += c - '0';
					file_i += 1;
					if (file_i >= file.count) break;
					c = file.data[file_i];
				}
			}

			render_info->buffer[i][0] = ((int)pixel[0])*255/specifics->max_pixel_value;
			render_info->buffer[i][1] = ((int)pixel[1])*255/specifics->max_pixel_value;
			render_info->buffer[i][2] = ((int)pixel[2])*255/specifics->max_pixel_value;
			render_info->buffer[i][3] = 255;
			if (file_i >= file.count) break;
		}
	}
	free(file.data);
	return log;
}

Log ppm_cleanup(Pre_Rendering_Info *pre_info) {
	return (Log){0};
}

Log pbm_pre_render(Pre_Rendering_Info *pre_info) {
	Specifics *specifics;
	if (!pre_info->user_ptr) {
		specifics = malloc(sizeof(Specifics));
		*specifics = (Specifics){0};
		pre_info->user_ptr = specifics;
	} else specifics = pre_info->user_ptr;

	specifics->which_type = TYPE_PBM;
	return generic_pre_render(pre_info);;
}

Log pbm_render(Pre_Rendering_Info *pre_info, Rendering_Info *render_info) {
	Specifics *specifics = pre_info->user_ptr;
	Log log = (Log){0};

	fseek(pre_info->fileptr, 0, SEEK_END);
	string file;
	file.count = ftell(pre_info->fileptr) - specifics->start_of_image;
	file.data = malloc(file.count);

	fseek(pre_info->fileptr, specifics->start_of_image, SEEK_SET);
	fread(file.data, 1, file.count, pre_info->fileptr);

	if (specifics->is_binary) {
		int64_t i = 0;
		int64_t file_i = 0;
		while (i < render_info->buffer_count && file_i < file.count) {
			uint8_t byte = file.data[file_i];
			uint8_t mask = 1 >> (i % 8);
			uint8_t pixel = 0;
			if (byte & mask) pixel = 255;

			render_info->buffer[i][0] = pixel;
			render_info->buffer[i][1] = pixel;
			render_info->buffer[i][2] = pixel;
			render_info->buffer[i][3] = 255;

			if (i % 8 == 7) file_i += 1;
			i += 1;
		}
	} else {
		int64_t file_i = 0;
		for (int64_t i = 0; i < render_info->buffer_count; i += 1) {
			while (is_white_space(file.data[file_i])) file_i += 1;

			char c = file.data[file_i];
			uint8_t pixel = 0;
			if (c == '1') pixel = 255;
			file_i += 1;

			render_info->buffer[i][0] = pixel;
			render_info->buffer[i][1] = pixel;
			render_info->buffer[i][2] = pixel;
			render_info->buffer[i][3] = 255;
			if (file_i >= file.count) break;
		}
	}
	free(file.data);
	return log;
}

Log pbm_cleanup(Pre_Rendering_Info *pre_info) {
	return (Log){0};
}

Log pgm_pre_render(Pre_Rendering_Info *pre_info) {
	Specifics *specifics;
	if (!pre_info->user_ptr) {
		specifics = malloc(sizeof(Specifics));
		*specifics = (Specifics){0};
		pre_info->user_ptr = specifics;
	} else specifics = pre_info->user_ptr;

	specifics->which_type = TYPE_PGM;
	return generic_pre_render(pre_info);
}

Log pgm_render(Pre_Rendering_Info *pre_info, Rendering_Info *render_info) {
	Specifics *specifics = pre_info->user_ptr;
	Log log = (Log){0};

	fseek(pre_info->fileptr, 0, SEEK_END);
	string file;
	file.count = ftell(pre_info->fileptr) - specifics->start_of_image;
	file.data = malloc(file.count);

	fseek(pre_info->fileptr, specifics->start_of_image, SEEK_SET);
	fread(file.data, 1, file.count, pre_info->fileptr);

	if (specifics->is_binary) {
		int64_t distance;
		for (int64_t i = 0; i < render_info->buffer_count; i += 1) {
			uint8_t pixel = ((int)file.data[i])*255/specifics->max_pixel_value;
			render_info->buffer[i][0] = pixel;
			render_info->buffer[i][1] = pixel;
			render_info->buffer[i][2] = pixel;
			render_info->buffer[i][3] = 255;
		}
	} else {
		int64_t file_i = 0;
		for (int64_t i = 0; i < render_info->buffer_count; i += 1) {
			uint8_t pixel = 0;
			if (file_i >= file.count) break;
			while (is_white_space(file.data[file_i])) file_i += 1;
			char c = file.data[file_i];
			while (!is_white_space(c)) {
				c = file.data[file_i];
				pixel *= 10;
				pixel += c - '0';
				file_i += 1;
				if (file_i >= file.count) break;
				c = file.data[file_i];
			}

			pixel = ((int)pixel)*255/specifics->max_pixel_value;
			render_info->buffer[i][0] = pixel;
			render_info->buffer[i][1] = pixel;
			render_info->buffer[i][2] = pixel;
			render_info->buffer[i][3] = 255;
			if (file_i >= file.count) break;
		}
	}
	free(file.data);
	return log;
}

Log pgm_cleanup(Pre_Rendering_Info *pre_info) {
	return (Log){0};
}
