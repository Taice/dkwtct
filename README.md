# DKWTCT
- stands for Dont Know What To Call This

# SETUP:
- download the binary (or compile with zig build if you have anything other than x86-64)

# USAGE:
- left click on a key  - input/paste a character on the normal layer (paste using ctrl+v)
- right click on a key - input/paste a character on the shift layer 
- left/right click and esc to clear the key from the corresponding layer
- ctrl+shift+s to save layout to specified location <BR>
note: <BR>
in the save/load menu the top thing is the layout and the bottom is the variant
so if your command to load the layout would be: setxkbmap {layout} -variant {variant} you would put those 2 things in the input menu
- ctrl+s to save layout to the current loaded
- esc while not clicking anything to import a layout
## SHORTCUTS
- ctrl+n - new layout, discards any changes
- ctrl(+shift)+s - save layout
- ctrl+v - pastes either a character if a key is selected or a layout if nothing is selected <BR>
note: <BR>
the layout is sanity checked so you don't need to be particularly cautious when pasting characters
- esc - brings up the load menu
- ctrl+c copies the current layout to clipboard with either the name its saved as or "layout" if you haven't given it a name yet

# NOTES
- the layouts are saved to `~/.xkb/symbols/`, because thats where xkb can find them
