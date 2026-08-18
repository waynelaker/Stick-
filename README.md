# Stick! — GME Giant Port

This build contains the **Normal giant** and **Tap giant**, closely ported from
the successful TypeScript Gymnastics Movement Engine play mode. The reference
implementation remains authoritative for motion and appearance.

## Run

Open this folder in Godot 4.x and press **F6/F5**, or run:

```sh
godot --path .
```

## Controls

- **Space**: pause/play
- **R**: restart the Giant
- **G**: queue the Normal Giant
- **T**: queue the Tap Giant
- **− / +**: playback speed

## Structure

- `scripts/authored_skills.gd` — GME joint poses and kinematic-chain sampler
- `scripts/gymnast.gd` — exact Giant timing and GME-style canvas rendering
- `scripts/game.gd` — minimal play-mode wrapper

Both Giants use the reference's six-joint skeleton, 12 authored poses, shortest-
path angular interpolation and position-dependent playback speed. A requested
variant blends during the bottom approach and takes over at the bottom, keeping
the routine continuous.
