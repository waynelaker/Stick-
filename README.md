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
- **− / +**: playback speed

## Move editor

Choose **Edit mode** below the stage. The editor lets you:

- select, preview, add, or remove moves from the working session;
- scrub the timeline and select a keyframe from either the dropdown or the
  explicit dots along the timeline;
- use the low-opacity keyframe poses drawn across the stage as an onion skin;
- click a ghosted pose to select that keyframe directly;
- drag the hand, shoulder, hip, knee, ankle, or head in the stage;
- add, update, or delete keyframes;
- edit duration and looping;
- import `.stick.json` move files;
- save the current move directly into the project's `skills` folder.

Dragging an articulated joint preserves its bone length and carries its
descendants. Pose changes remain temporary until **Update keyframe** or **Add
keyframe** is pressed. **Save move** writes the complete current move to
`skills/<move-id>.stick.json`; additional saved moves are discovered on the next
launch. Removing a move only removes it from the current session and does not
delete its source file.

## Structure

- `skills/*.stick.json` — explicit, editable move/keyframe data
- `scripts/authored_skills.gd` — file loading, saving, and chain interpolation
- `scripts/gymnast.gd` — playback, joint editing, and GME-style rendering
- `scripts/game.gd` — play mode and editor interface

All three shipped moves load their complete joint poses from files. Saved moves
are self-contained JSON and can be imported without procedural move-generation
code.
