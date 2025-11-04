#include <stdint.h>
#include <string.h>
#include <stdio.h>

typedef struct {
	int64_t count;
	uint8_t *data;
} string;

string to_string(char *str) {
	return (string){(int64_t) strlen(str), (uint8_t *) str};
}

/*** The next three structs are used in the mandatory functions. ***/

/* Entirely filled in by the Plugin. */
typedef struct {
	string name_of_filetype;
	string extension;
	string magic_number;

	string procedure_prefix;
	uint8_t has_settings;
} Plugin_Registration_Entry;

typedef struct {
	/* <Provided by MIV> */
	string name;
	FILE *fileptr;
	/* <Provided by MIV/> */
	/* <Provided by Plugin> */
	int64_t width, height;
	uint8_t bit_depth;
	uint8_t channels;
	int64_t metadata_count;
	string (*metadata)[2];

	void *user_ptr;
	/* <Provided by Plugin/> */
} Pre_Rendering_Info;

/* Entirely filled in by MIV, except for the values in the buffer. */
typedef struct {
	int64_t buffer_count;
	uint8_t (*buffer)[4];
} Rendering_Info;

/*** From here it is about the optional features (like plugin settings). ***/
#define RESPONSE_NOTHING 0;
#define RESPONSE_RE_RENDER 1;

#define OPTION_TYPE_TOGGLE 0;
#define OPTION_TYPE_LIST 1;
#define OPTION_TYPE_SLIDER 2;

typedef struct {
	int32_t provided_ID;

	string name;
	uint8_t type;
} Setting_Info;

typedef struct {
	Setting_Info info;
	uint8_t active;
} Setting_Toggle;

typedef struct {
	uint8_t active;
	string name;
} List_Item;

typedef struct {
	Setting_Info info;
	int64_t changed_item;
	int64_t count;
	List_Item *data;
} Setting_List;

typedef struct {
	Setting_Info info;
	string value_text;
	float value;
} Setting_Slider;
