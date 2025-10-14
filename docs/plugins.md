# MIV Plugin Reference/Documentation
## Table of Contents
1. [Plugins Overview](#plugins-overview)
2. [Lifecycle](#lifecycle)
3. [`string`](#string)
4. [Registration](#registration)
5. [Pre-Render](#pre-render)
6. [Render](#render)
7. [Cleanup](#cleanup)
8. [Settings API](#settings-api)

## Plugins Overview
A valid MIV plugin must be a `.so` dynamic library, and define at least 4 functions:
```c
int64_t registration_procedure(Plugin_Registration_Entry *registration)

string pre_render(Pre_Rendering_Info *pre_info)
string render(Pre_Rendering_Info *pre_info, Rendering_Info *render_info)
string cleanup(Pre_Rendering_Info *pre_info)
```
The `string`, `Plugin_Registration_Entry`, `Pre_Rendering_Info` and `Rendering_Info` types are defined in [plugins/MIV.h](../plugins/MIV.h).
See [plugins/ppm.c](../plugins/pnm.c) for a comprehensive example on how they are used in a plugin.

This API is expected to change to allow for more advanced features. Also it's not done yet.
It will soon have a versioning system to allow MIV to detect out-of-date plugins.

## Lifecycle
On program startup, the plugins folder is read, and `registration_procedure()` is called for every plugin.
Then, when an image is opened, MIV compares the file extension and magic number to all registered file extensions and magic numbers.\
If it finds a match, `pre_render()` is called and provided with the opened file. If `pre_render()` fails, `cleanup()` is called.
Otherwise, `render()` is called, and the image is displayed. `cleanup()` is again called when another image is opened.

When scanning a directory, MIV calls `pre_render()` and `cleanup()` for every file (that it recognises that file extension and magic number of)
to see if it should add them to the file queue. This can happen while it is displaying an image, so the following can (and often does) happen:\
`pre_render()` -> `pre_render()` -> `cleanup()` -> `render()` -> `cleanup()`.

MIV does not call any plugin functions from multiple threads.

## `string`
The `string` type is used for all plugin functions, and for nearly all of its structs. It's used instead of the more customary `char *`
because \*gestures vaguely at C's history*.

It's essentially a byte array:
```c
typedef struct {
	int64_t count;
	uint8_t *data;
} string;
```

The `to_string()` function is provided to convert 0-terminated string literals.
```c
string to_string(char *str) {
	return (string){(int64_t) strlen(str), (uint8_t *) str};
}
```

## Registration
The `registration_procedure()` is the first mandatory function that has to be defined. This is its signature:
```c
int64_t registration_procedure(Plugin_Registration_Entry *registration)
```
It provides information about which image types the plugin can read. It takes a pointer to a `Plugin_Registration_Entry`.
```c
typedef struct {
	string name_of_filetype;
	string extension;
	string magic_number;

	string procedure_prefix;
	uint8_t has_settings;
} Plugin_Registration_Entry;
```
The `name_of_filetype` is the 'full legal name' of the type of file that the plugin reads.\
`extension` is the file extension that the filetype is associated with (not including the dot (`.`)). It is case insensitive.\
`magic_number` is the first set of bytes that files of the filetype in question start with.\
The `procedure_prefix` is an optional prefix for the rest of the functions in the plugin. This is so that you can have more than one registered filetype in one `.so` file.\
`has_settings` is a boolean. If true, MIV will also look for the `settings()` function, related to the [Settings API](#settings-api).

To register more than one filetype for a plugin, `registration_procedure()` returns an integer that tells MIV how many more times to call `registration_procedure()`.
If the plugin provides 3 file formats, it returns `2` after the first time it has been called, then `1` after the second, and `0` after the third.
Every time, the plugin can put new info in the `Plugin_Registration_Entry`.

## Pre-Render
As mentioned in the section about the [lifecycle](#lifecycle), `pre_render()` is called whenever MIV has pinned down what filetype a given file is.
```c
string pre_render(Pre_Rendering_Info *pre_info)
```
Note that if `procedure_prefix` was defined, that would have to be prepended to the function's name. As an example, if the `procedure_prefix` was `my_very_cool_`,
then it would have to be called `my_very_cool_pre_render()` for MIV to find it.\
Regardless, it takes a pointer to `Pre_Rendering_Info`.
```c
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
```
MIV provides the filename (in the `name`) field, and a libc file pointer to the already opened file (which `ftell()` is guaranteed to return 0 on).\
The main task of `pre_render()` to to inform MIV about any metadata that a file might have, as well as its width and height,
so that MIV can allocate an appropriately sized buffer for the actual image data to be stored in.\
`pre_render()` is not expected to start resolving said image data, only the file header (or equivalent).

`width` and `height` should give the size in pixels of each respective dimension.\
`bit_depth` is not used by MIV, but only displayed as metadata to the user. It is the amount of bits of information that a channel has/can have in the image.\
`channels` refers to the amount of colour channels (or equivalent). Again, this is not used by MIV (yet).\
`metadata` is a pointer to a buffer of `string` pairs. Each string pair represents extra metadata that the plugin might want to offer to the user.
The first element of a string pair is the name, and the second is the actual value (stringified by the plugin). `metadata_count` is the amount of
string pairs that the library has provided.

Finally, `user_ptr` is a pointer that MIV never touches or looks at, and can be used by the plugin to store its own internal state for between functions.
Do note the [lifecycle](#lifecycle) and its implications!

Whenever `pre_render()` detects an error in the image, it can return a non-empty `string` that contains information about what went wrong. This message will be
presented to the user along with the string: `File metadata reading error: `.

## Render
In a sense, `render()` is the focal point of a plugin.
```c
string render(Pre_Rendering_Info *pre_info, Rendering_Info *render_info)
```
The `Pre_Rendering_Info` it is passed is the same one that `pre_render()` filled out. MIV will not respond to any more changes to `width` and `height`
at this point, the struct is only there for the information in it.\
However, the filepointer will be reset to the start of the file (same as for `pre_render()`), so take this into account.

The new struct here is `Rendering_Info`:
```c
typedef struct {
	int64_t buffer_count;
	uint8_t (*buffer)[4];
} Rendering_Info;
```
`buffer` is a pointer to the pixel buffer allocated by MIV (and `buffer_count` is the amount of pixels in it).\
`render()`'s task is to decode the image data in the image file, and to load it, as pixels, into the buffer.
Every pixel in the buffer is 8-bit sRGBA.

Just like `pre_render()`, `render()` can also return an error, which is presented to the user with the string `Image data retrieval error: `.

## Cleanup
`cleanup()` can be used to clean up internal resources.
```c
string cleanup(Pre_Rendering_Info *pre_info)
```
This `Pre_Rendering_Info` struct is the same one that `pre_render()` filled out, so the same as the one `render()` got as well.\
Most relevant usage information of `cleanup()` is described in [Lifecycle](#lifecycle).

## Settings API
A plugin can optionally enable the ability to declare its own settings by setting the `has_settings` field in
`Provided_Registration_Entry` to true.\
If this flag is set to true, a function with the following signature has to be defined (with the established `procedure_prefix` as well):
```c
string settings(Pre_Rendering_Info *pre_info, Rendering_Info *render_info, Settings_Info *settings_info);
```
The `settings()` function gets called whenever the settings menu is opened in MIV, as well as when a plugin setting have changed (in that menu).
It takes the known `Pre_Rendering_Info` and `Rendering_Info` parameters, but also takes `Settings_Info`.
```c
typedef struct {
	uint8_t response;
	int32_t changed_index;
	int32_t changed_secondary_index;
	int64_t options_count;
	Option *options_data;
} Settings_Info;
```
The `changed_index` is the primary indicator of the situation under which MIV called the `settings()` function.
If it is `-1`, then the settings menu was just opened, and the plugin is expected to populate the relevant fields of `Settings_Info`.
If it is larger than or equal to `0`, a setting was changed (more detail on this later).

The main fields for the plugin to populate are:
```c
int64_t options_count;
Option *options_data;
```
Together these form an array view of `Option`s, and they are entirely plugin-owned.
```c
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
```
An `Option` always has a name, which is the name that the setting will get in the UI. There are two types of options, denoted by the `type` field.
It can be either a toggle (`type = OPTION_TYPE_TOGGLE`) or a list (`type = OPTION_TYPE_LIST`). Toggles are simply a boolean.

Lists are a little more involved, as they are an array view of `List_Item`s.
```c
typedef struct {
	uint8_t selected;
	string name;
} List_Item;
```
Each item can be selected individually. They can be used either as checkboxes or as radio buttons, it is up to the plugin to enforce either.

But how does the plugin know what changed? It all lies in the `changed_index` and `changed_secondary_index` fields of `Settings_Info`.
When a setting is changed in the UI, `settings()` is called, and `changed_index` is set to the index into `options_data` of the setting that was changed.
If that setting was a list, then `changed_secondary_index` is set to the list item that was changed.

Finally, whenever the plugin is done changing what it needs to internally, it can give a `response` (a field of `Settings_Info` as well) to MIV.
```c
#define RESPONSE_NOTHING 0;
#define RESPONSE_RE_RENDER 1;
```
As you can see, this response is either `NOTHING`, or `RE_RENDER`. If the latter response is indicated, MIV calls the `pre_render()` and `render()`
functions on the currently open image.
