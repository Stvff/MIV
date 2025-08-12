## unorganized
Basic idea: images are loaded by dynamic libraries.
MIV selects the correct dynlib via a 'registration file' that registers file extension and magic number.
The user is notified when a file's extension and magic number disagree.
When there's no file extension, magic numbers are referenced.

The dynlib returns pixels that fit in the view (this for both svg-type things, as well as images that are too large to reasonably fit in RAM)

The process for adding dynlibs:
1. Select menu item
2. drag in the dynlib
3. (internal from here)
4. dynlib is asked for file extension and magic number (if there's a problem: inform the user)
5. dynlib is copied to some cozy place (option in regfile ofc)

What happens when an image is opened:
1. MIV notes the extension
2. MIV opens the file and checks the magic number (if applicable)
3. MIV chooses the library to call to
4. MIV gives the library the opened file to get image information
5. MIV allocates the buffer (always RGBA)
6. MIV tells the library to render the image to the provided buffer
7. MIV watches the file to see if it changes, restarts this whole process when it changes

when switching to history mode, the current file's directory is investigated

when an image is dropped in directory mode, the directory is investigated
in case the directory is invalid, don't change anything
in case that that image is invalid, it switches to the first available image in that directory
in case that there is no available image in that directory, MIV renders and draws nothing, gives an "no readable files in dir" error, and switches to historymode on ok
	else the eventually rendered file gets added to history

when an image is dropped in history mode, the list of files is investigated, and all errors relayed.
the last available image in history is rendered, and the errors displayed (ok does nothing but dismiss)
in case that there are no valid images in history, rendering and drawing is turned off

Dropping files puts them all in the history
History is sanitized
Best available image is chosen to view
if directory mode, discover directory

Some features:
- Zoom (percentage is image pixel to screen pixel, zoomlimit is when 1 pixel completely covers the screen)
- Pan (is in imagepixels removed from the center)
- Rotate (probably degrees, though I prefer radians for this (with the PI factored out))
- The Slider/Player
	- Segmented or Contiguous
	- Prev or Next
	- Play or Pause
- Options menu
	- Edit regfile
	- Viewing settings
	- Sorting, etc

- Zooming options are provided by the dynlib (MIV should probably supply some defaults)
- Persistent viewing state (transformation, channel(?), etc?) across hotreloading (and scrolling, when enabled)
- Hotreloading
- Scrolling continuous at hold (settable FPS target)
- Sorting should be smart (eventually ask the file editor about it)
- Maybe preload N amount of items (either to local disk or memory (as framebuffers))

Because it is not always trivial to provide a sub-window, it might make sense for dynlibs to report themselves as only available in some modes.
For example, 'window rendering', but 'animated'/'multichannel' could be orthogonal to that (but notably not to eachother).
