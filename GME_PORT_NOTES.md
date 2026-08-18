# TypeScript GME → Godot Giant port

The runtime TypeScript source in `Documents/GitProjects/gme/src` is the
authoritative reference. The checked-in `normal-giant.gme.json` appears to be an
older export (its shoulder is 56 px from the grip); current runtime code uses
the 60 px arm declared in `skeleton.ts`, so this port follows the runtime.

## Motion traced from the reference

- **Joints:** hand, shoulder, hip, knee, ankle and head.
- **Chain:** hand→shoulder→hip→knee→ankle; head is a separate shoulder offset.
- **Proportions:** arm 60, torso 80, thigh 65, shin 65, head offset 20.
- **Grip:** fixed at `(500, 275)` on the edge-on high-bar axis.
- **Authored poses:** 12 poses at equal `2π / 12` phase intervals. The poses are
  generated once from the Normal Giant authoring function, then sampled as
  keyframes rather than recalculated as continuous procedural motion.
- **Shape:** shoulder follows the 60 px grip radius; the hip uses an 80 px radial
  torso plus `9 sin(phase − 0.35)` tangent shaping; knee and ankle receive small,
  independently authored sinusoidal angle offsets.
- **Interpolation:** each bone angle follows the shortest signed angular path.
  Bone lengths interpolate independently. Head angle and distance interpolate
  relative to the shoulder. There is no generic easing function.
- **Timing:** skill time advances at `4.2 × speed × bottomSpeedBias`, where
  `bottomSpeedBias = 0.38 + 0.82 × (1 + cos(skillTime)) / 2`. This creates the
  characteristic acceleration at the bottom and pause near handstand.
- **Loop:** duration is `2π`. The reference sampler's final→first interval had a
  timing error that entered the segment at roughly 92% and caused the visible
  bottom-of-swing jerk. Godot uses the corrected ordinary keyframe span: final
  key at 0%, first key at 100%.
- **Rendering:** the original 1000×550 SVG coordinates are retained without a
  camera conversion. Apparatus is behind the gymnast, while the 13 px end-on bar
  cap is drawn last as a foreground overlay.

## Extension seam

`normal_giant()` returns a self-contained authored skill record with ID, name,
duration, loop flag, entry state, exit state and keyframes. `sample_skill()` is
skill-agnostic. Additional authored moves can therefore reuse the sampler after
the Giant's visual match is approved; no gameplay graph has been added yet.
