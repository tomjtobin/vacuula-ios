# Vacuum icons

The app icon is original geometric artwork inspired by the D-shaped robot: a flat cleaning edge, curved rear, lidar ring and power control, in Vacuula’s teal palette. The opaque 1024-pixel square lets iOS apply its own Home Screen mask.

`RobotVacuum` is a monochrome vector PDF with transparent cutouts, so the tab bar can apply the selected and unselected colours in either appearance. Discovery and the empty robot screen use the same symbol. The existing status-card illustration already has a D-shaped body.

Regenerate both assets from the workspace root with the Xcode toolchain’s `swift ios/Design/generate-icons.swift`. The generated files are checked into the app’s asset catalog; the script is not part of the app build.
