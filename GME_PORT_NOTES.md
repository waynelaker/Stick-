# TypeScript GME → Godot Giant port

The runtime TypeScript source in `Documents/GitProjects/gme/src` is the
authoritative motion reference. The checked-in `normal-giant.gme.json` appears
to be an older export (its shoulder is 56 px from the grip); current runtime
code uses 60 px. The Godot port began with that runtime value, then adopted the
small arm-length and apparatus-height refinements recorded below after review.

## Motion traced from the reference

- **Joints:** hand, shoulder, hip, knee, ankle and head.
- **Chain:** hand→shoulder→hip→knee→ankle; head is a separate shoulder offset.
- **Proportions:** the GME torso 80, thigh 65, shin 65 and head offset 20 are
  retained. Following visual review, the arm is refined from 60 to 65.
- **Grip:** fixed at `(500, 255)` on the edge-on high-bar axis. It is raised 20
  px from the reference so the extended gymnast clears the mat/floor.
- **Authored poses:** 12 poses at equal `2π / 12` phase intervals. The poses are
  generated once from the Normal Giant authoring function, then sampled as
  keyframes rather than recalculated as continuous procedural motion.
- **Shape:** shoulder follows the refined 65 px grip radius; the hip uses an 80 px radial
  torso plus `9 sin(phase − 0.35)` tangent shaping; knee and ankle receive small,
  independently authored sinusoidal angle offsets.
- **Interpolation:** each bone angle follows the shortest signed angular path.
  Bone lengths interpolate independently. Head angle and distance interpolate
  relative to the shoulder. There is no generic easing function.
- **Timing:** the reference advanced at `4.2 × speed × bottomSpeedBias`, where
  `bottomSpeedBias = 0.38 + 0.82 × (1 + cos(skillTime)) / 2`. This creates the
  characteristic acceleration at the bottom and pause near handstand. After
  play review, the preferred former 1.2× rate was calibrated as the new 1.0×
  baseline, so Godot advances at `5.04 × speed × bottomSpeedBias`.
- **Loop:** duration is `2π`. The reference sampler's final→first interval had a
  timing error that entered the segment at roughly 92% and caused the visible
  bottom-of-swing jerk. Godot uses the corrected ordinary keyframe span: final
  key at 0%, first key at 100%.
- **Rendering:** the original 1000×550 SVG coordinates are retained without a
  camera conversion. The complete apparatus and gymnast composition is then
  uniformly displayed at 86% around stage centre, including its stroke widths,
  to keep the handstand and feet inside the window. Apparatus is behind the
  gymnast; the refined 9 px end-on bar cap is drawn last, while the head is
  drawn before the bones so the near arm crosses in front.

## Extension seam

`normal_giant()` returns a self-contained authored skill record with ID, name,
duration, loop flag, entry state, exit state and keyframes. `sample_skill()` is
skill-agnostic. Additional authored moves can therefore reuse the sampler after
the Giant's visual match is approved; no gameplay graph has been added yet.

The shipped Normal Giant, Tap Giant, and Layout Back are now loaded from
`skills/*.stick.json`. Each file contains every authored joint position. The
remaining procedural constructors are compatibility/fallback helpers; normal
project playback uses the explicit file data.

## Tap Giant

The Tap Giant ports the `tap` branch of the reference's
`referenceGiantPose()`: upswing/downswing shoulder and hip flexion, the bottom
arch, tangent shaping, and its Tap-specific playback drive. `T` queues Tap and
`G` queues Normal. The change happens at a bottom boundary, with the outgoing
move blending into the incoming move across its final 22%. A request made too
late to receive that entire blend waits for the following bottom.

## Layout Back dismount

The first non-looping skill is an authored Layout Back. It starts from the
Normal Giant bottom, swings to a fixed release pose, then follows a cubic flight
path with a straight body completing the backward layout rotation. The final
pose places the ankles on the floor line. A Tap Giant first blends toward the
Normal bottom shape so the dismount begins without snapping.
