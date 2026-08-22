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
- **R**: restart the Giant
- **G**: queue the Normal Giant
- **T**: queue the Tap Giant
- **D** or the **Dismount** button: queue a Layout Back dismount
- **1–9, 0**: queue the corresponding move shown in the on-screen legend;
  JSON skills discovered in `skills/` receive these shortcuts automatically
- **− / +**: playback speed

The numbered move legend remains visible while queue/status messages are shown.
In play mode, the routine strip below the stage can compose a sequence from any
discovered JSON moves. Repeated moves are supported. Choose moves with **Add to
routine**, then use **Play routine** to watch the complete authored sequence.
Moves are classified as **Mount**, **Swing**, **Release**, or **Dismount** in the editor and
saved with that class in their JSON file. A routine allows one mount at the
start, any number of swing and one-shot release moves, and one dismount at the
end. Consecutive queued releases play consecutively. When no next release or
other move is queued, the gymnast returns to the most recently performed swing
and continues it. The gymnast
starts—and returns with **R**—in a static long hang until a move is selected.

For larger move libraries, play mode provides a searchable, class-labelled move
picker. Type part of a move name or class, choose the result, then press
**Queue** (or press Enter in the search field). The first ten moves retain their
number-key shortcuts. Edit mode can **Rename** a move without changing its file
ID, or **Copy** the complete move to a new ID for use as an editable variation.

## Move editor

Choose **Edit mode** below the stage. The editor lets you:

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
- undo or redo authored changes with the buttons, **Ctrl+Z**, **Ctrl+Y**, or
  **Ctrl+Shift+Z**.

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

All three shipped moves load their complete joint poses from files. Saved moves
are self-contained JSON and require no procedural move-generation code.
