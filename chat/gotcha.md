# Gotchas — this looks normal but will ruin your afternoon (scratch-2026-10-05-5a158f)

Each: what you would naturally do, what actually happens, what to do instead. Add to it the
moment something costs an hour.

- 

- 2026-10-05 · `screencapture -l <windowid>` to check the app → "could not create image from window" (no Screen Recording permission for the shell), and computer-use `request_access` can't find an LSUIElement/accessory app → verify SwiftUI drawing by compiling the view with an `ImageRenderer` harness to PNG instead.
- 2026-10-05 · Compiling a multi-file harness where the extra file has top-level code → "expressions are not allowed at the top level" → the file with top-level code must be named `main.swift`.

- 2026-10-05 · Animating with `dt = min(0.05, elapsed)` in the pets widget → when frames drop (background browser pane ran ~4 fps) the scene clock crawled (T=5.5 after ~15 s wall) and reminders never fired → cap dt at 0.25 s; to test timed states, set the state clock via javascript_tool instead of waiting.
- 2026-10-05 · Boo's bubble placed at sprite top with Boo at y=12 (low-res) → "Walk break!" bubble clipped above the scene → keep floating sprites ≥ 26 low-res px from the top.

- 2026-10-05 · Editing WaterBuddy.swift via python/sed in Bash, then calling Write on it → "File has been modified since read" → Read the file (even a few lines) before a full Write after shell edits.
- 2026-10-05 · Assumed the user's GIFs needed background keying → both already have alpha; but the cat GIF moves inside its 504×280 canvas (a flip trick, not a walk cycle) → crop all frames to the union alpha bbox, not per-frame, so the motion survives; it's exact 7× pixel art (grid at 0), so draw at n/7 with nearest-neighbour.

- 2026-10-05 · Showed the ghost only when a walk was due and froze the cat on frame 0 between occasional tricks → Somay: "i cant see gengar and kitten is so stiff" → desktop pets must be visible and animating the whole time; play GIFs on an always-running Timer in RunLoop .common mode, and signal reminders with a bubble + hop instead.

- 2026-10-05 · Images Somay pastes mid-turn (Vaporeon, Lapras, Mew) are not saved to the session images/ dir (only 1.gif, 2.gif exist; find under /private/tmp/claude-501 found nothing new) → ask him to save the files into ~/Pixels/friends instead of searching.

- 2026-10-05 · "comapre sizes and adjust car is perfect though just do pokemoins" read as "size Pokémon against the cat" → shrank them to 60/82 pt → Somay: "bigger like you shrank them a lot, I didnt ask you to comapre cat with them" → he meant match the Pokémon to each other; when a size request is ambiguous, keep the current scale and only equalise, or ask.
