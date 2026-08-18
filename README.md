# Stick! — GME Giant Port

This build deliberately contains one move: the **Normal giant**. It is a close
Godot port of the successful TypeScript Gymnastics Movement Engine play mode.
The reference implementation remains authoritative for motion and appearance.

## Run

Open this folder in Godot 4.x and press **F6/F5**, or run:

```sh
godot --path .
```

## Controls

- **Space**: pause/play
- **R**: restart the Giant
- **− / +**: playback speed

## Structure

- `scripts/authored_skills.gd` — GME joint poses and kinematic-chain sampler
- `scripts/gymnast.gd` — exact Giant timing and GME-style canvas rendering
- `scripts/game.gd` — minimal play-mode wrapper

The Giant uses the reference's six-joint skeleton, 12 authored poses, shortest-
path angular interpolation and position-dependent playback speed. The skill
record already carries compatible entry/exit state fields, but gameplay graph
work is intentionally deferred until the single Giant has been visually signed
off.
