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
- [x] remove registration file (since it is redundant)
- [ ] One more supported image type
- [x] Option to select between zoom on screen center and pointer
	- [ ] zoom on pointer
- [ ] Options for the different persistence settings (between files, restarts, etc)
	- [ ] Make a settings file
- [x] Options for AA
	- [x] Implement AA
	- [ ] There's linear upscaling and downscaling and nearest upscaling and downscaling, should this be two toggles?
- [x] Option for metadata
	- [x] Display metadata
	- [ ] Let plugins provide custom metadata (this is the thing that needs textflows/scrollbars/clipping)
- [ ] Option for plugin settings
	- [ ] Implement some API for plugin settings
- [ ] Filewatching
	- [ ] Handle events where the file was moved (maybe follow the file?)
- [ ] give functions the ability to respond responsibly based on user input option
- [ ] logs onscreen instead of in terminal
	- [ ] intelligent textflows (includes clipping)
		- [ ] scrollbars I'm afraid
	- [x] show count of errors in the errorbar
- [x] Some pleasant and elaborate tooltips
- [ ] Custom icons
	- [ ] Fit buttons
	- [ ] Mode buttons
	- [ ] Next/prev
	- [ ] Zoom buttons
	- [ ] Settings
	- [ ] Metadata or plugin settings??
- [x] Make modes a radio button selector thing
	- [x] show index in file queue

## Bugs to fix
- When the directory can't be read (happens when it tries to read root), it should return to history mode
- When another window is above MIV, MIV still reads the mouse position from that window.
- When an older window is closed above MIV, MIV crashes?? Even subwindows of other programs (see OBS) have this effect.
```
X Error of failed request:  BadWindow (invalid Window parameter)
  Major opcode of failed request:  38 (X_QueryPointer)
  Resource id in failed request:  0x1
  Serial number of failed request:  41677
  Current serial number in output stream:  41677
```

## Amersfoort
- [ ] different types of filesorting
- [ ] More advanced plugin interactions
- [ ] Being more elaborate about what failed during loading (which part of the directory, which type of error)
