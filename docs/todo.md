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
	- [ ] qoi
	- [ ] Finish the pnm plugin to really support all types
- [x] Option to select between zoom on screen center and pointer
	- [x] zoom on pointer
- [x] Options for the different persistence settings (between files, restarts, etc)
	- [x] Implement that actual persistence
	- [x] Make a settings file
- [x] Options for AA
	- [x] Implement AA
- [x] Option for metadata
	- [x] Display metadata
	- [x] Let plugins provide custom metadata
- [ ] Option for plugin settings
	- [ ] Implement some API for plugin settings
		- [ ] Catagorize what sort of settings there should be
		- [ ] Some sort of settings persistence?
	- [ ] Draw it on the UI
- [x] Filewatching
	- [x] Reload various file lists when something was detected
	- [x] show count of errors in the errorbar
- [x] Some pleasant and elaborate tooltips
- [x] Make modes a radio button selector thing
	- [x] show index in file queue
- [ ] Enter directory mode if `files_to_open` is only one file.
- [x] Begin custom icons

## Bugs to fix
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
- [ ] intelligent textflows (includes clipping)
	- [ ] scrollbars I'm afraid
	- [ ] logs onscreen instead of in terminal
- [ ] Modernize Custom icons
	- [ ] Fit buttons
	- [ ] Queueue mode buttons
	- [ ] Next/prev
	- [ ] Zoom buttons
	- [ ] Settings
	- [ ] AA button
	- [ ] Metadata or plugin settings??
- [ ] different types of filesorting
- [ ] give functions the ability to respond responsibly based on user input option
	- [ ] More advanced plugin interactions
- [ ] Being more elaborate about what failed during loading (which part of the directory, which type of error)
- [ ] Select which plugin to use for which filetype in case there's multiple plugins covering multiple file types.
- [ ] Exif data
- [ ] Follow files when they are moved, also in the history
- [ ] Nicer looking upscaling
