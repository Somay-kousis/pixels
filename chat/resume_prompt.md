Resuming: Pixels (~/Pixels, public repo github.com/Somay-kousis/pixels), macOS desktop pets from Somay's own GIFs. Cat = water reminder (45 min, goal 8), Gengar = walk reminder (60 min); friends Vaporeon, Lapras (stay put, spots saved) and Mew (new mew_.gif, flies) from ~/Pixels/friends. All wander; a due reminder brings that pet to the pointer with bubble + hop + sound; click to log. Timers pause while screen off/locked. Starts at login.

Last completed: per-pet right-click 'Move around' and 'Hide (peek from the bottom)' (remembered per pet; reminders override). Before that: personalities + signature moves for all pets, 40 pt spacing (no collisions), mouse-shake/⌃⌥J group jump; uncommitted. Before that: 3-stage escalation (5 min → 3× + shake, 10 min → full-screen takeover unless camera/mic/fullscreen busy), Done reward, idle actions for every pet; installed + running; uncommitted. Before that: Pokémon matched to each other at ~100 pt (cat unchanged; '-big' tag = 120 pt); lineup at ~/Pixels/size-lineup.png. Before that: Vaporeon/Lapras made stationary (sliding looked unnatural); Mew swapped for mew_.gif; installed, running.

Next action: none pending; wait for Somay's feedback (sizes, speed, roles for friends).

Do not build on:
- any commit with a Claude/co-author/generated-by line (Somay: "no claude name in commits").
- assuming the sprites are licensed: repo is public by Somay's choice, takedown possible.
- anything on-screen being verified by Claude: no screen access; only logs and offscreen renders.

Verify first:
- `cd ~/Pixels && ./build.sh` builds; `pgrep -x Pixels` running; login items list Pixels.
- `WB_DEBUG=1 ~/Pixels/Pixels.app/Contents/MacOS/Pixels --demo` logs moving frames and chase.
