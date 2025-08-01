#include <stdint.h>
#include <string.h>
#include <stdio.h>

typedef struct {
	int64_t count;
	uint8_t *data;
} string;

string to_string(char* str) {
	return (string){strlen(str), str};
}

typedef struct {
	string name_filetype;
	string procedure_prefix;
	string extension;
	string magic_number;
	uint8_t has_magic_number;
	uint8_t extension_is_case_sensitive;
} Provided_Registration_Entry;

typedef struct {
	string name;
	FILE *fileptr;
	int64_t width, height;

	uint8_t bit_depth;
	uint8_t channels;
	string metadata;

	void *user_ptr;
} Pre_Rendering_Info;

typedef struct {
	int64_t column_range[2];
	int64_t row_range[2];

	int64_t buffer_width;
	int64_t buffer_height;

	int64_t buffer_count;
	uint8_t (*buffer)[4];
} Rendering_Info;
