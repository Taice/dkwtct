# DKWTCT
- stands for Dont Know What To Call This
- used to make xkb layouts easily on linux
- primarily made with focus on mcsr but can be used for other purposes aswell

# SETUP:
- download the ReleaseSmall binary (or compile with zig build if you have anything other than x86-64)
- NOTE:
- if there is any bug you want to report like crashes or unexpected behaviour please try downloading the debug binary instead and see what it outputs

# USAGE:
## Layout
- import an existing xkb layout with the File menu or ctrl+i
- left click on a key  - input/paste a character on the normal layer (paste using ctrl+v)
- cycle between layers with the menu button or ctrl+(1-4)
- esc to clear the key from the corresponding layer
- ctrl(+shift)+s or File->save to save dkwtct layout to specified location(this is not the same as exporting!)
- bleed chars option - whether to bleed characters from the normal layer to the shift layer if nothing is already on it

## Rebinds
- import existing rebinds with the File menu or ctrl+i
- left click on a key and then press a key on your keyboard to set that rebind
- right click on a key to bring up a searchable list of keys
- swap rebinds option - this preserves the layout when changing rebinds but it also swaps rebinds so if you rebind a to d then it rebinds d to a

## I have a layout, what now
- first i would recommend saving the dkwtct layout somewhere (default path is .config/dkwtct/layouts/) via ctrl(+shift)+s or the File menu
- after that you can export the xkb layout and rebinds via the File menu or ctrl+e
- note that you should export your rebinds to your waywall directory cause you're gonna have to import them in your waywall config
- in your waywall config, replace your `whatever_this_is_called = { ["a"] = "b", ... }` or similar with `whatever_this_is_called = require("{the file you exported the rebinds to}")`

## SHORTCUTS
- ctrl+e - export the xkb layout and rebinds
- ctrl+i - import the xkb layout or rebinds
- ctrl+n - blank slate, discards any changes
- ctrl(+shift)+s - save layout
- ctrl+v - pastes a character if a key is selected
- ctrl+c - copies the character on the selected key
- ctrl+(1-4) - switch layer
- ctrl+space - switch between rebinds and layout

# TODO
- char picker
