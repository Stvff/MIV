# MIV
![Screenshot of the image viewer, showing a frame from the Bad Apple music video.](/docs/apeldoorn_screenshot_1.png "Screenshot of the image viewer, showing a frame from the Bad Apple music video.")
![Screenshot of the image viewer, showing the settings menu and metadata bar, together with a tooltip.](/docs/apeldoorn_screenshot_2.png "Screenshot of the image viewer, showing the settings menu and metadata bar, together with a tooltip.")

## How to use
### Installing
You can download the latest release here:
[Download executable and official plugins](https://github.com/Stvff/MIV/releases/latest)

Put the executable in a folder with write access (somewhere underneath home), then make a symbolic link in a bin folder of choice:
```
/bin/ $> sudo ln -s ~/your/preferred/path/miv miv
```

### Adding plugins
To add plugins, simply drag them onto the window from your file explorer (or by running it in the terminal: `$> miv your-plugin-name.so`). You can add multiple plugins at once.

### Viewing files
To view files, you can drag them onto the window, or add them from the terminal.

## Context
Recently, while making [Sokoworm](https://stvff.github.io/sokoworm.html#top), which uses [PPM image files](https://en.wikipedia.org/wiki/Netpbm#File_formats)
as graphics outputs, I noticed that the feature-set of the average image viewer is quite limited. Many image viewers only support a relatively small set of image types,
and it is rare for one to support automatic file reloading. On top of this, things like zoomlevel or offset (while viewing an image in detail) are not persistent between files, window resizing, or program restart.
As with most things, performance stays a concern. Long loading times (and no feedback during), or no options for pre-loading.\
Generally, actual viewing settings are very limited.

Instead of these things, image viewers seemingly focus development effort on image editing features, which, while nice, are not as important to me as all the other things mentioned.

It is good practice to attempt to solve a problem like this yourself when you encounter it; maybe there's a reason these more popular programs haven't done it.
So far, I have implemented most of my desired features, and have still not found out why all of these are not commonplace.

## Outline/Mission Statement
The current roadmap can be found in [docs/todo.md](./docs/todo.md).\
The naming of releases is based on all the major train stations between Twente and Amsterdam. The hope is that it will be out of pre-release when I get to Amsterdam.

To be more specific about features, I am aiming for feature parity (or more) with the [Linux Mint xviewer](https://github.com/linuxmint/xviewer?tab=readme-ov-file) in terms of the image viewing experience.

## Development
### Building
If you don't want to download the files from the release, you can also clone this repo from github, then run `jai first.jai` in the directory.
Of course, you will need jai beta access for this.

### Making plugins
To make a plugin, jai beta access is not required. It can be done in any compiled language.
A valid MIV plugin must be a `.so` dynamic library, and define at least 4 functions:
```
int64_t registration_procedure(Provided_Registration_Entry *registration)

string pre_render(Pre_Rendering_Info *pre_info)
string render(Pre_Rendering_Info *pre_info, Rendering_Info *render_info)
string cleanup(Pre_Rendering_Info *pre_info)
```
The `string`, `Provided_Registration_Entry`, `Pre_Rendering_Info` and `Rendering_Info` types are defined in [plugins/MIV.h](./plugins/MIV.h).
See [plugins/ppm.c](./plugins/pnm.c) for a comprehensive example on how to use them.

The `registration_procedure()` provides information about what the plugin can read. The integer that the function returns is how many more times it should be called by MIV.
If the plugin provides 3 file formats, it returns 2 after the first time it has been called, then 1 after the second, and 0 after the third.

`pre_render()` informs MIV about any metadata that a file might have, as well as its width and height, so that MIV can allocate an appropriately sized buffer.
Note that MIV opens the file, and that the plugin is presented with a file pointer (which `ftell()` is guarenteed to return 0 on).

`render()` extracts actual image data out of the file, and puts it in the buffer provided in the `Rendering_Info` struct.

Finally, `cleanup()` can be used to clean up internal resources.

This API is expected to expand to allow for more advanced features.
