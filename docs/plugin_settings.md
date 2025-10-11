## Plugins Overview
A valid MIV plugin must be a `.so` dynamic library, and define at least 4 functions:
```
int64_t registration_procedure(Plugin_Registration_Entry *registration)

string pre_render(Pre_Rendering_Info *pre_info)
string render(Pre_Rendering_Info *pre_info, Rendering_Info *render_info)
string cleanup(Pre_Rendering_Info *pre_info)
```
The `string`, `Plugin_Registration_Entry`, `Pre_Rendering_Info` and `Rendering_Info` types are defined in [plugins/MIV.h](../plugins/MIV.h).
See [plugins/ppm.c](../plugins/pnm.c) for a comprehensive example on how to use them.

This API is expected to change to allow for more advanced features. Also it's not done yet.
It will soon have a versioning system to allow MIV to detect out-of-date plugins.

## Registration
The `registration_procedure()` provides information about what the plugin can read. The integer that the function returns is how many more times it should be called by MIV.
If the plugin provides 3 file formats, it returns 2 after the first time it has been called, then 1 after the second, and 0 after the third.

## Lifecycle
On program startup, the plugins folder is read, and `registration_procedure()` is called for every plugin.
Then, when an image is opened, MIV compares the file extension and magic number to all registered file extensions and magic numbers.\
If it finds a match, `pre_render()` is called and provided with the opened file. If `pre_render()` fails, `cleanup()` is called.
Otherwise, `render()` is called, and the image is displayed. `cleanup()` is again called when another image is opened.

When scanning a directory, MIV calls `pre_render()` and `cleanup()` for every file (that it recognises that file extension and magic number of)
to see if it should add them to the file queue. This can happen while it is displaying an image, so the following can (and often does) happen:\
`pre_render()` -> `pre_render()` -> `cleanup()` -> `render()` -> `cleanup()`.

MIV does not call any plugin functions from multiple threads.

## Registration
`pre_render()` informs MIV about any metadata that a file might have, as well as its width and height, so that MIV can allocate an appropriately sized buffer.
Note that MIV opens the file, and that the plugin is presented with a file pointer (which `ftell()` is guaranteed to return 0 on).

## Pre-Render
`render()` extracts actual image data out of the file, and puts it in the buffer provided in the `Rendering_Info` struct.

## Render
Finally, `cleanup()` can be used to clean up internal resources.

## Settings API
A plugin can optionally enable the ability to declare its own settings by setting the `has_settings` field in
`Provided_Registration_Entry` to true.\
If this flag is set to true, a function with the following signature has to be defined (with the established naming scheme):
```c
string settings(Pre_Rendering_Info *pre_info, Rendering_Info *render_info, Settings_Info *settings_info);
```
The `settings()` function gets called whenever the settings menu is opened in MIV, as well as when a plugin setting has changed (in that menu).
This function takes the known `Pre_Rendering_Info` and `Rendering_Info` parameters, but also takes `Settings_Info`.
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
