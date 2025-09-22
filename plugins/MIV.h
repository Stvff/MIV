#include <stdint.h>
#include <string.h>
#include <stdio.h>

typedef struct {
	int64_t count;
	uint8_t *data;
} string;

string to_string(char *str) {
	return (string){strlen(str), str};
}

/*** The next three structs are used in the mandatory functions. ***/

typedef struct {
	string name_filetype;
	string procedure_prefix;
	string extension;
	string magic_number;
	uint8_t has_magic_number;
	uint8_t extension_is_case_sensitive;
	uint8_t has_settings;
} Provided_Registration_Entry;

typedef struct {
	string name;
	FILE *fileptr;
	int64_t width, height;

	uint8_t bit_depth;
	uint8_t channels;
	int64_t metadata_count;
	string (*metadata)[2];

	void *user_ptr;
} Pre_Rendering_Info;

typedef struct {
	int64_t buffer_width;
	int64_t buffer_height;

	int64_t buffer_count;
	uint8_t (*buffer)[4];
} Rendering_Info;

/*** From here it is about the optional features (like plugin settings). ***/

typedef struct {
	uint8_t selected;
	string name;
} List_Item;

#define OPTION_TYPE_TOGGLE 0;
#define OPTION_TYPE_LIST 1;

typedef struct {
	string name;
	uint8_t type;
	union {
		uint8_t toggle;
		struct {
			int64_t count;
			List_Item *data;
		} list;
	};
} Option;

typedef struct {
	uint8_t response;
	int32_t changed_index;
	int32_t changed_secondary_index;
	int64_t options_count;
	Option *options_data;
} Settings_Info;

#define RESPONSE_NOTHING 0;
#define RESPONSE_RE_RENDER 1;
