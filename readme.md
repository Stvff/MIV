# MIV
This project is somewhat of an experiment. As with most projects, I am not confident it will yield something generally useful, but it is definitely made to eventually be useful.
![Screenshot of the image viewer, showing the first level of sokoworm.](/docs/screenshot.png "Screenshot of the image viewer, showing the first level of sokoworm.")\

## Context
Recently, while making [Sokoworm](https://stvff.github.io/sokoworm.html#top), which uses [PPM image files](https://en.wikipedia.org/wiki/Netpbm#File_formats)
as graphics outputs, I noticed that the feature-set of the average image viewer is quite limited. Many image viewers only support a relatively small set of image types,
and it is rare for one to support automatic file reloading. On top of this, things like zoomlevel or offset (while viewing an image in detail) are not persistent between files, window resizing, or program restart.
As with most things, performance stays a concern. Long loading times (and no feedback during), or no options for pre-loading.\
Generally, actual viewing settings are very limited.

Instead of these things, image viewers seemingly focus development effort on image editing features, which, while nice, are not as important to me as all the other things mentioned.

It is good practice to attempt to solve a problem like this yourself when you encounter it; maybe there's a reason these more popular programs haven't done it.

## Outline/Mission Statement
So, my idea is as follows:\
MIV is a modular image viewer, where file formats are supported through plugins (as `.so` files). These plugins must have a simple API, so that supporting a new image format is a simple task based on the reference implementation for that format.
MIV arranges the windowing, the UI, file collection and preloading, and the plugins decode the images.

A loose set of specific ideas and architecture is collected in [docs/idea.md](./docs/idea.md).\
As for now, I'm trying to get a passable image viewer with automatic file reloading for PPM files. This way, I'm creating a 'reference plugin' in C (see `MIV.h` and `meow.c`) that other people can then reference, should they choose to participate.

To be more specific about features, I am aiming for feature parity with the [Linux Mint xviewer](https://github.com/linuxmint/xviewer?tab=readme-ov-file) in terms of the image viewing experience.
