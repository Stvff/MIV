There are too many texture creations and deletions. Consider making the vast majority of the simple rectangle drawing ops instead.
Textures are only really needed to clip text, and we can easily use 1 texture for only that.

The scrolling and panning still take inputs when they are outside the canvas; this must be limited.

In fact, when another window is above MIV, MIV still reads the mouse position from that window.
