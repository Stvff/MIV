#include "MIV.h"
#include <stdlib.h>

int64_t registration_procedure(Plugin_Registration_Entry *registration) {
	registration->name_of_filetype = to_string("Vanadis Image");
	registration->extension = to_string("VAIM");
	registration->magic_number = to_string("vaim");
	registration->procedure_prefix = to_string("vaim_");
	registration->has_settings = true;
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

int32_t vaim_setting(Pre_Rendering_Info *pre_info, Rendering_Info *render_info, Setting_Info *setting) {
	if (setting == NULL) return 3;

	int32_t response = RESPONSE_NOTHING;
	switch (setting->provided_ID) {
	/* intialize settings */
	case -1: {
		setting->name = to_string("invert");
		setting->type = OPTION_TYPE_TOGGLE;
		break;
	} case -2: {
		setting->name = to_string("possible sounds");
		setting->type = OPTION_TYPE_LIST;
		Setting_List *list = (Setting_List*) setting;
		list->count = 4;
		list->data = malloc(list->count*sizeof(List_Item));
		memset(list->data, 0, list->count*sizeof(List_Item));
		list->data[0].name = to_string("meow");
		list->data[1] = (List_Item){true, to_string("yip")};
		list->data[2].name = to_string("wruff");
		list->data[3].name = to_string("nyaaaaa");
		break;
	} case -3: {
		setting->name = to_string("rotation");
		setting->type = OPTION_TYPE_SLIDER;
		Setting_Slider *slider = (Setting_Slider*) setting;
		slider->value_text = to_string("might be halfway");
		slider->value = 0.5;
		break;
	}

	/* use the results when a setting has changed */
	case 1: {
		Setting_Toggle *toggle = (Setting_Toggle*) setting;
		if (toggle->active) printf("wow\n");
		response = RESPONSE_NOTHING;
		break;
	} case 2: {
		Setting_List *list = (Setting_List*) setting;
		for (int i = 0; i < list->count; i += 1) list->data[i].active = false;
		list->data[list->changed_item].active = true;
		response = RESPONSE_RE_RENDER;
		break;
	} case 3: {
		Setting_Slider *slider = (Setting_Slider*) setting;
		slider->value -= 0.1;
		if (slider->value < 0.0) slider->value = 0.0;
		break;
	}}

	return RESPONSE_NOTHING;
}

string vaim_setting_cleanup(Pre_Rendering_Info *pre_info, Rendering_Info *render_info) {
	return (string){0};
}
