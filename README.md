# Stick! — GME Giant Port

This build contains file-backed **Normal giant**, **Tap giant**, and **Layout
Back dismount** skills, plus a pose/keyframe editor inspired by the TypeScript
Gymnastics Movement Engine.

## Run

Open this folder in Godot 4.x and press **F6/F5**, or run:

```sh
godot --path .
```

## Controls

- **Space**: pause/play
- **R**: return to the static hang
- **G**: queue the Normal Giant
- **T**: queue the Tap Giant
- **D**: queue a Layout Back dismount
- **1–9, 0**: optional quick shortcuts for the first ten discovered moves
- **− / +**: playback speed

Use the **☰ Menu** in the right sidebar to switch between Play, Edit, and Routine
modes. Each mode only shows the controls relevant to it. Play mode uses a
large searchable, class-filtered move list; one click performs a move. Routine
mode provides its own filtered list, where one click adds a move to the routine.
Repeated moves are supported.
Moves are classified as **Mount**, **Swing**, **Release**, or **Dismount** in the editor and
saved with that class in their JSON file. A routine allows one mount at the
start, any number of swing and one-shot release moves, and one dismount at the
end. Consecutive queued releases play consecutively. When no next release or
other move is queued, the gymnast returns to the most recently performed swing
and continues it. The gymnast
starts—and returns with **R**—in a static long hang until a move is selected.

Each move also stores structured **START** and **END** transition signatures:
position/phase and grip. Edit mode exposes these fields in
the right sidebar and labels the first and final gymnast poses directly on the
stage. Green and red timeline markers identify those endpoint keyframes. Play
mode only lists moves whose START signature matches the current END signature;
Routine mode applies the same filtering after the last move in the routine.

For larger move libraries, every move has a visible two-digit code. Enter that
code in the sidebar and press Enter to perform it (or add it in Routine mode).
Search accepts a move name, class, or code. The first ten moves also retain
optional number-key shortcuts. Edit mode can **Rename** a move without changing
its file ID, or **Copy** the complete move to a new ID for use as an editable
variation.

## Move editor

Choose **Edit mode** from the hamburger menu. The editor lets you:

- select, preview, add, or remove moves from the working session;
- scrub the timeline and select a keyframe from either the dropdown or the
  explicit dots along the timeline;
- drag a timeline dot horizontally to adjust that keyframe's time (the first
  keyframe remains anchored at `0.0s`);
- use the low-opacity keyframe poses drawn across the stage as an onion skin;
- click a ghosted pose to select that keyframe directly;
- drag the hand, shoulder, hip, knee, ankle, or head in the stage; the selected
  keyframe updates immediately in memory;
- add or delete keyframes;
- copy the previous keyframe's pose into the selected keyframe as a starting
  point for the next authored pose;
- edit duration and looping;
- save the current move directly into the project's `skills` folder.
- undo or redo authored changes with **Ctrl+Z**, **Ctrl+Y**, or
  **Ctrl+Shift+Z**.

All timeline values are real seconds. The Giant speed shaping is represented by
non-uniform keyframe times—closer dots through the fast bottom and wider gaps
near handstand—rather than by a hidden phase clock. Changing **Move … s** scales
the complete move and every keyframe proportionally, providing a whole-move
speed control without individually dragging its frames.

Dragging an articulated joint preserves its bone length, carries its
descendants, and immediately updates the selected keyframe in memory. The
arm, torso, thigh, shin, and head offset always use the gymnast's canonical
proportions; loaded poses are normalised to those proportions as well. Feet
only snap to the floor while the gymnast is detached from the bar. The
torso/spine can be dragged to translate the entire gymnast when the selected
pose's hands are detached from the bar. Clicking the detached gymnast's spine
opens a transform gizmo: drag its central cross to move the entire figure or its
offset circular handle to rotate it in place. Clicking elsewhere closes the
gizmo. Drag an attached hand away from the bar
to release it; move a detached hand close to the bar to snap it back on. An
attached grip is shown in green. The apparatus itself remains fixed. The
ankle similarly snaps to the floor when dragged close and turns light green.
Pulling it away releases the ground contact. Grounded pose interpolation and
editing are rooted at the planted ankle rather than at the hands. The
**Ghosts** checkbox controls both onion-skin visibility and click selection of
ghost poses. **Save move** writes the complete current move to
`skills/<move-id>.stick.json`; additional saved moves are discovered on the next
launch. Removing a move only removes it from the current session and does not
delete its source file.

## Structure

- `skills/*.stick.json` — explicit, editable move/keyframe data
- `scripts/authored_skills.gd` — file loading, saving, and chain interpolation
- `scripts/gymnast.gd` — playback, joint editing, and GME-style rendering
- `scripts/game.gd` — play mode and editor interface

Authored moves load their complete joint poses from files. Saved moves are
self-contained JSON. The compact generated Blind change and Forward giant
files expand to ordinary editable keyframes when loaded and become fully
authored JSON after **Save move** is used.

### Side-on turns and depth

Pose files remain backward compatible with the original six-joint 2D format.
Individual keyframes may additionally store `body_yaw`, `arm_depth`, and
`leg_depth` as normalised values. The renderer uses these only for side-on
projection: the gymnast's true arm and leg lengths remain fixed while limbs
pointing into the screen appear foreshortened. At zero depth and at either end
of a turn, the original single-silhouette renderer is used unchanged.

Edit mode exposes these values as **Turn**, **Arms out**, and **Legs out** in
degrees. It also stores left and right hand grips separately. Green grip marks
mean regular grip and orange marks mean reverse grip; each hand may also carry
its own attachment state in the skill file.

When turn or depth projection is active, Edit mode places its draggable joint
handles on the gymnast's projected left/right joints rather than on the hidden
centre-line pose. Dragging a projected handle maps back to the fixed-length
authored skeleton, so foreshortened arms and legs remain directly editable.

The included **Blind change** authors a half turn over the established normal
giant motion. It finishes in reverse grip and automatically continues into the
included **Forward giant** unless another compatible move has been queued. The
**Pirouette** provides the inverse transition: Forward giant in reverse grip to
Normal giant in regular grip.

## Prototype D score

Play and Routine modes show a live D-score panel beneath the gymnast stage. An
element only enters the score when its animation completes; selecting or
queueing it does not count. Up to ten distinct completed elements are retained,
with a later harder element replacing the lowest-valued entry when necessary.
Each row shows both its difficulty letter (`A`, `B`, `C`…) and numeric value.
Each represented element group currently adds a provisional `0.5` requirement
bonus. This deliberately small policy is preparation for the full Code of
Points rather than an attempt to reproduce it yet.

Skills may store top-level `difficulty` and `element_group` fields. Older files
remain compatible and receive inferred prototype values: releases are Group
II, dismounts Group IV, and foundational swing elements Group I. Saving a move
writes the inferred or authored values explicitly into its JSON file.

For current men's High Bar, the Code's groups are: **I** long hang swings with
or without turns; **II** flight elements; **III** in-bar and Adler elements;
and **IV** dismounts. These are separate from Stick's broad editor/playback
`move_class` values, although releases and dismounts naturally align with
Groups II and IV respectively.

Non-looping skills may specify `default_follow` in their JSON. This continuation
is used only when the player has not queued another move. Start Swing currently
defaults to Normal giant, so choosing no follow-up produces continuous giants.
