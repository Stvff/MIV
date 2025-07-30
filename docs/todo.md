## Deventer
- [x] read files from the command line
- [x] zooming on pixel currently in the center of the screen
	- [x] refactor/reorder of input, drawing, rendering, filehandling
- [x] Implement UI
	- [x] user prompt popups
		- [ ] give programs the ability to respond responsibly based on user input option
	- [ ] logs onscreen instead of in terminal
		- [ ] intelligent textflows (includes clipping)
	- [x] option buttons
		- [ ] option sliders
- [x] registration file for plugins (always lives next to the exe, not cwd)
	- [x] parse regfile
	- [x] write regfile on MIV close
	- [x] move plugin files to the plugins folder on import
	- [x] create plugin directory if it doesn't exist (on program startup)
- [ ] next/prev in the current directory
	- [ ] some starts on preloading (mostly through the user importing more than 1 file at once)

## Apeldoorn
- [ ] Option to select between zoom on screen center and pointer
	- [ ] zoom on pointer
- [ ] Filewatching
- [ ] Options for the different persistence settings (between files, restarts, etc)
