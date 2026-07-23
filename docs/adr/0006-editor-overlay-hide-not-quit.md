# Editor Overlay: hide, don't quit

The Editor is a terminal editor (e.g. vim, nano) in an Overlay PTY on the Agent. Leaving the Overlay **hides** it and returns focus to the Main CLI; the editor process stays alive so the Operator can show it again with buffer/state intact.

Quitting the editor (e.g. `:q`) is an explicit Operator action, not the default of the hide shortcut.
