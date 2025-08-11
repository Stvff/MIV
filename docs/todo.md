## Deventer
- [x] read files from the command line
- [x] zooming on pixel currently in the center of the screen
	- [x] refactor/reorder of input, drawing, rendering, filehandling
- [x] Implement UI
	- [x] user prompt popups
	- [x] option buttons
		- [x] option sliders
- [x] registration file for plugins (always lives next to the exe, not cwd)
	- [x] parse regfile
	- [x] write regfile on MIV close
	- [x] move plugin files to the plugins folder on import
	- [x] create plugin directory if it doesn't exist (on program startup)
- [x] next/prev in the current directory
	- [x] some starts on preloading (mostly through the user importing more than 1 file at once)
- [x] Documentation

## Apeldoorn
- [ ] remove registration file (since it is redundant)
- [ ] One more supported image type
- [ ] Option to select between zoom on screen center and pointer
	- [ ] zoom on pointer
- [ ] Options for the different persistence settings (between files, restarts, etc)
- [ ] Options for AA (think about if this could be elaborate)
- [ ] Filewatching
	- [ ] Handle events where the file was moved (maybe follow the file?)
- [ ] give functions the ability to respond responsibly based on user input option
- [ ] logs onscreen instead of in terminal
	- [ ] intelligent textflows (includes clipping)
		- [ ] scrollbars I'm afraid
	- [x] show count of errors in the errorbar
- [ ] Some pleasant and elaborate tooltips maybe
- [ ] Custom icons?
	- [x] Make modes a radio button selector thing
		- [x] show index in file queue

## Bugs to fix
- While scrolling through a directory, MIV attempts to open files it doesn't/shouldn't know instead of skipping them like it should.
	- When such a file is opened, the index in the directory is still kept while the previous file renders, and it's very confusing.
- When another window is above MIV, MIV still reads the mouse position from that window.
- When an older window is closed above MIV, MIV crashes?? Even subwindows of other programs (see OBS) have this effect.

## Amersfoort
- [ ] different types of filesorting
- [ ] More advanced plugin interactions
- [ ] Being more elaborate about what failed during loading (which part of the directory, which type of error)
