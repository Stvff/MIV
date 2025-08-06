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
- [ ] One more supported image type
- [ ] Option to select between zoom on screen center and pointer
	- [ ] zoom on pointer
- [ ] Options for the different persistence settings (between files, restarts, etc)
- [ ] Options for AA (think about if this could be elaborate)
- [ ] Filewatching
- [ ] give functions the ability to respond responsibly based on user input option
- [ ] logs onscreen instead of in terminal
	- [ ] intelligent textflows (includes clipping)
		- [ ] scrollbars I'm afraid
- [ ] Some pleasant and elaborate tooltips maybe
- [ ] Custom icons?

## Amersfoort
- [ ] different types of filesorting
- [ ] More advanced plugin interactions
- [ ] Being more elaborate about what failed during loading (which part of the directory, which type of error)
