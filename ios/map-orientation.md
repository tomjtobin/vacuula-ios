# Map orientation

Implemented 2026-10-19. Open **Settings → Maps → Rotation** and choose **0° (Default)**, **90° clockwise**, **180° clockwise** or **270° clockwise**.

The choice is saved locally and applies to all map canvases, across robots and servers. It is restored on app restart. Demo rotation changes do not save preferences. The `--demo-map` fixture starts at zero without changing the saved real-app choice.

The common map renderer rotates the cropped raster, cleaning-room outlines, selection fills, no-go areas and base position in the same coordinate transform. The base's house symbol remains upright for readability. At 90°/270°, available axes are swapped when fitting the image, so a rectangular map fits inside its viewport. Existing zoom/pan happens outside the rotation; changing the orientation resets zoom/pan. Reset view retains the chosen global orientation.

This is display-only. Saved map pixels, boundary vertices, robot/base coordinates, room IDs and cleaning-command payloads are unchanged. No server call or firmware change is needed for the preference.

Core tests verify the default, every supported persisted value, invalid-value fallback and rectangular-map fitting. The simulator fixture contains an asymmetric rectangular raster, a room, a no-go line and a base marker so all four orientations can be visually compared. See [validation](validation/README.md) and [evidence](validation/map-rotation/).

Current validation: app/UI-test builds succeed, all 32 core tests pass, and the simulator's four-orientation picker/map check passes. Screenshots were reviewed for consistent base and overlay alignment. No live robot operation was performed.
