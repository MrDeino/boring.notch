# Quick 261014-rm9 Summary

Closed-notch usage hairline pinned to the visible notch bottom (hardware-aware), and image paste/drop in the composer with PNG upload through the optimistic send queue.

## Commits
- 1a7787f feat: usageHairlineRect, OrchestratorPost.image, uploadOrchestratorImage, decodeImagePath, orchestratorPNG, PendingMessage images/paths/wireText, tests
- d8e6bef fix: hairline pinned to visible bottom, closed snapshots 12-16
- fd462b3 feat: composer chips, Cmd-V, drop, upload in drain(), pending thumbnails, snapshots 31-33

## Hairline
- Cause: hairline was drawn at the bottom of the drawn shape (`closedNotchSize.height` = safeAreaInsets.top = 32), but the user's Mac menu bar / hardware notch band reaches 33pt, so the 2pt line sat 1pt (2 device px) above the visible bottom.
- Fix: `usageHairlineRect` uses bottom = max(shape height, hardware notch height), where hardware height = the notch screen's `max(safeAreaInsets.top, frame.maxY - visibleFrame.maxY)` (0 on notch-less displays). When the hardware is lower than the shape, the line spans only the hardware notch width (centred) so it never hangs below the wings over the wallpaper. ContentView untouched.
- Gap numbers (pixel check in the closed harness, rows between hairline bottom and visible bottom): 32 = 0, 38 = 0, 32 with simulated 33 hardware = 0, wings at 38 = 0, needs-you at 38 = 0.
- Wings centring: checked at 38 (spinner and timer, needs-you dot and pill) - vertically centred, OrchestratorWings.swift left untouched.

## Image paste/drop
- Cmd-V (keyCode 9, command only, only when an image is on the pasteboard) attaches a removable 34pt chip; text-only paste falls through. Drop of image or image file on the composer adds chips (several allowed). Images are downscaled to 2000px longest side as PNG; over 10 MB or unconvertible shows an inline tag.
- Send: drain() uploads each image to POST /api/chat/image (x-orch 1, image/png, raw), appends returned paths to the row, then sends `text [image: path]...`. Upload failure marks only that row "Not sent"; Retry reuses already-uploaded paths; Edit restores text and images. Reconcile matches on the wire text (stale-drop after 30s still covers Claude Code rewriting the path).
- Mock result: harness passes offline, with ORCH_IMAGE_MOCK=1 (upload returns the mock path, dead port returns nil, missing x-orch gets 400, text/plain gets 415) and ORCH_NOTES_MOCK=1. `lsof -i :47999` empty afterwards. Nothing posted to 4777.

## PNGs looked at
closed-1, 10, 12, 13, 14, 15, 16 (hairline on the visible bottom in all; in 14 it sits on the simulated hardware band and spans the notch width only); 15, 25, 26 (no regression); 31 (chips with xmark buttons readable, not clipped, composer fits), 32 (dimmed thumbnails aligned with the text column, image-only failed row, Not sent / Retry / Edit readable), 33 (right-aligned thumbnails in expanded).

## Deviations
- Follow-up commit (coordinator request): pending-row thumbnails moved under the text line (right-aligned under the bubble when expanded); image-only compact rows keep a drawn ❯ marker on the thumbnail line. Snapshots 32 and 33 re-viewed. (Supersedes the earlier "indent instead of marker" note.)
- Snapshot harness: idle closed replica needed a bare-notch width (ZStack with clear notch-size spacer) so the no-wings hairline scenes have a shape. Pending image-only rows show the thumbnails with a 16pt indent rather than a drawn ❯ marker.
- Task 2 pixel check samples the background colour from the image corner rather than assuming 0.35.

## Needs on-screen checking (not launched)
- Cmd-V with a real screenshot on the clipboard in the composer, and plain text paste still working.
- Drag an image and an image file onto the composer (the outer shelf onDrop should yield inside the composer).
- Real upload to serve and the `[image: path]` text reaching Claude Code.
- Hairline on the real closed notch (32 and 33 hardware band).

## Self-Check: PASSED
Commits 1a7787f, d8e6bef, fd462b3 exist; on orch/261014083623-80d8; ContentView.swift untouched; nothing pushed; no processes left.
