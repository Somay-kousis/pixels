# Decisions log — scratch-2026-10-05-5a158f

Append-only. Status: **settled**, **provisional**, **reversed** (kept, with what replaced it).

| Date | Decision | Why | Status |
|---|---|---|---|
| 2026-10-05 | `chat/` handoff scaffolded. | Every project keeps state this way. | settled |

- 2026-10-05 · Native Swift (AppKit panel + SwiftUI) instead of Python: transparent always-on-top, all-Spaces windows are reliable natively and flaky in tkinter; single file, no deps, `swiftc` already installed.
- 2026-10-05 · Default interval 45 min, daily goal 8 glasses (~8 over a 6–8 h waking/working day); user-adjustable 20/30/45/60/90 via right-click.
- 2026-10-05 · Unanswered reminders re-nudge every 5 min (sound + bubble) rather than once, so a missed one isn't lost.
- 2026-10-05 · Pets are Somay's own GIFs played as-is ("take excatly what I gave"): cat = water (assets/water-cat.gif), Gengar = walk (assets/walk-ghost.gif). Mapping is Claude's assumption (ghost was Boo = walk). Personal use only; Gengar is Pokémon IP, so never publish/distribute these assets.
- 2026-10-05 · Cat drawn at 4/7 scale with nearest-neighbour (4 pt per art pixel); Gengar GIF is a fractional resize (runs of 6 and 7 px), so smooth scaling at 0.3.
- 2026-10-05 · Cat sits still (frame 0) and does its trick every 40–90 s; loops the trick while water is due. Ghost only appears when a walk is due, floats in from the right next to the cat, leaves after click. Timers restart on wake from sleep.
- 2026-10-05 · Supersedes the earlier behaviour row: both pets stay on screen and loop their GIFs continuously; a due reminder makes that pet hop and show a bubble. (Somay found the hidden ghost / still cat wrong.)
- 2026-10-05 · Timers only count while Somay is at the screen: pause on display sleep / system sleep / screen lock, restart both on wake/unlock (his expectation: "timer works only when my laptop screen is on right").
- 2026-10-05 · Named Pixels; source ~/Pixels, app ~/Applications/Pixels.app, bundle id local.somay.pixels; starts at login via a System Events login item (Somay: "set it to start by itself").
- 2026-10-05 · Pets wander: cat walks the bottom edge (45 pt/s, faces direction of travel), ghost floats anywhere (30 pt/s); a due reminder makes that pet come to the pointer at 3×; hover stops it; drag holds it 6 s; window ignores mouse except over the sprite (click-through). Menu toggle "Let them wander". Saved window positions dropped (they move anyway).
- 2026-10-05 · Extra pets = companions loaded at launch from ~/Pixels/friends (GIF/PNG/WebP/JPG), no reminder role (Claude's call; Somay said only "letsadd these too"). Solid backgrounds keyed out by edge flood fill; pixel grid auto-detected → crisp whole-point scale; "-fly" in filename = floats.
- 2026-10-05 · Friends without "-fly" stay put (play their GIF in place, fall to the floor if dropped, position saved per friend) — Somay: Vaporeon/Lapras motion "looks unnatural so maybe you can either fix it or keep them still". "-walk" opts a real walk-cycle GIF into walking.
- 2026-10-05 · Mew replaced by ~/Downloads/mew_.gif (Somay: "keep this mew instead") → friends/mew-fly.gif.
- 2026-10-05 · Sizes measured on the first frame's body, cat (80×56 pt) is the reference and unchanged (Somay: "car is perfect though just do pokemoins"). Small class 60 pt (Vaporeon, Mew), big class 82 pt (Gengar, Lapras via "-big" filename tag). Pixel-art scale snaps to quarter art-pixel steps.
- 2026-10-05 · Supersedes the 60/82 pt sizing: Pokémon matched to each other at ~100 pt body height (Gengar 100, Lapras 99, Vaporeon 96, Mew 100); cat untouched. "-big" tag = 120 pt. Lapras renamed back to lapras.gif.
- 2026-10-05 · GitHub repo is PRIVATE because it contains Pokémon sprites; README says personal use only. Leftover WaterBuddy.swift/.app in ~/Pixels kept but gitignored.
