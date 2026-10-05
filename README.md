# Pixels

Desktop pets for macOS that remind you to drink water and take walks.

- **Cat**: water reminder (default every 45 min, goal 8 glasses a day). Walks along the bottom of the screen.
- **Gengar**: walk reminder (default every 60 min). Floats around.
- When a reminder is due, that pet comes to your mouse pointer, hops and shows a bubble. Click it to log the glass or walk.
- **Friends**: every GIF/PNG in `friends/` becomes a companion. `-fly` in the filename makes it float, `-walk` makes it walk (for real walk-cycle GIFs), `-big` makes it a size up. Others stay where you put them.
- Ignored reminders escalate: after 5 min the pet grows and shakes; after 10 min the screen dims with a big pet and Done / 5 more min buttons (skipped while your camera or mic is in use or an app is fullscreen).
- Each pet has its own personality and signature moves (Gengar vanishes and sneaks up on your cursor, Vaporeon melts, Lapras sings, Mew transforms into the others). Pets keep a gap from each other.
- Shake the mouse: everyone jumps and scatters. ⌃⌥J: everyone jumps.
- Right-click a pet: "Move around" on/off, "Hide (peek from the bottom)", intervals, snooze, sound, and "Show both reminders now".
- Timers pause while the screen is off or locked.

The app reads friends from `~/Pixels/friends`.

## Build and run

```sh
./build.sh
open Pixels.app                 # or: open Pixels.app --args --demo  (reminders in a few seconds)
```

Install: `cp -R Pixels.app ~/Applications/`, then add it to Login Items to start at login.

## Assets

The sprites in `assets/` and `friends/` are not mine: Pokémon sprites are © Nintendo / Game Freak, the cat GIF belongs to its creator. They're included as examples for a non-commercial fan project. Swap in any GIFs you like.
