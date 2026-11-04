-- Les coordonnées sont exprimées en points, indépendamment de la résolution.
on run arguments
    set mountPath to item 1 of arguments
    set appName to item 2 of arguments
    tell application "Finder"
        set volumeFolder to folder (POSIX file mountPath as alias)
        open volumeFolder
        delay 1
        set targetWindow to container window of volumeFolder
        tell targetWindow
            set current view to icon view
            set toolbar visible to false
            set statusbar visible to false
            set pathbar visible to false
            set sidebar width to 0
            set bounds to {160, 120, 880, 592}
            set viewOptions to icon view options of targetWindow
            set arrangement of viewOptions to not arranged
            set icon size of viewOptions to 96
            set text size of viewOptions to 13
            set label position of viewOptions to bottom
            set shows item info of viewOptions to false
            set shows icon preview of viewOptions to false
            set background color of viewOptions to {0, 0, 0}
            set background picture of viewOptions to POSIX file (mountPath & "/.background/background.tiff")
        end tell
        set position of item appName of volumeFolder to {180, 229}
        set position of item "Applications" of volumeFolder to {540, 229}
        close container window of volumeFolder
        open volumeFolder
        update volumeFolder without registering applications
        delay 2
        close container window of volumeFolder
    end tell
end run
