# Stick! — GME Giant Port

This build contains file-backed **Normal giant**, **Tap giant**, and **Layout
Back dismount** skills, plus a pose/keyframe editor inspired by the TypeScript
Gymnastics Movement Engine.

## Run

Open this folder in Godot 4.x and press **F6/F5**, or run:

```sh
godot --path .
```

## Web export

The checked-in **Web** export preset uses the Compatibility renderer, disables
thread support for ordinary static hosting, and explicitly includes the JSON
skill library in the exported game. Install the Godot export templates matching
your editor version once, then build with:

```sh
./tools/export_web.sh
```

Test the result through a local web server (browsers cannot run the build
correctly by opening `index.html` directly):

```sh
./tools/serve_web.sh
```

Open <http://127.0.0.1:8000>. To publish on itch.io, zip the contents of
`build/web` so `index.html` is at the ZIP root, then upload it as an HTML game.
Player-created routines continue to use `user://`; in a Web build Godot stores
that data in the browser's persistent site storage.

## Game mode

Use the **☰ Menu** to switch between **Game** and **Editor**. Game
opens on a library of ready-made and player-saved routines so play can begin
immediately. **Add a routine** opens Compose: search or filter the large
text-first move-card grid and drag cards into any transition-valid routine
slot. Click a card to play its move once inside the card; it then returns to its
name and description. Preview moves never loop or follow their normal automatic
continuation. Drag routine cards to reorder them, or use × to delete them. The
potential D score updates live, with its breakdown behind **D details**.

**Save routine** writes player routines to `user://stick_routines.json`, using
Godot's platform-appropriate per-user storage rather than a project path.
Player-created routines are labelled **Custom** in the library and have direct
**Edit** and **Delete** controls; bundled routines remain read-only.

During Perform, press **Space** or **START** to begin. No click is needed to
initiate a skill. An explicit Giant supplies one complete warning revolution,
and the Routine HUD shows the following skill approaching; input is inactive
during that warning. The separate alert text over the gymnast has been removed.
Consecutive complex skills flow directly. Releases use one judged **CATCH** hold—the
authored release itself needs no input; turns and In-bar skills use one click; dismounts
use one judged **STICK** landing click. Optional pose hints are
off by default. Harder moves have tighter timing. A badly missed release
branches into a fall and offers choices to remount and retry, continue, or
restart. The routine must be landed within 60 seconds. D counts completed
skills; E begins at 10.0 and loses execution deductions.

**Remount + retry** never launches directly from the mount into a failed
release. It reuses the nearest compatible authored Giant, completes one full
revolution to rebuild momentum, and then retries the release/catch.
On the fall screen, **Space** always chooses **Remount + retry** as the default.
Recovery is armed only after the fall animation finishes. A late catch press
that arrives during the fall is consumed, preventing it from immediately
replacing the fall with the remount hang; release it, then press Space to retry.

The compact, opaque **Routine HUD** sits beneath the apparatus so it never
obscures or competes directly with the gymnast. A fixed centre line
is always **NOW**; move frames scroll continuously from right to left beneath it.
Before starting, move 1 begins immediately to the right of that line. Halfway
through an authored move, the line is halfway through its frame, so the strip
communicates timing as well as sequence. Frame widths are proportional to
authored duration, giving the strip one constant pixels-per-second scale across
move boundaries. Each move box contains only its name; current/upcoming/done
highlights and metadata have been removed. Labelled
dots above the strip show every required input at its exact authored
judgement time: amber is upcoming, pulsing red is the input currently being
judged, and muted grey has passed. Roles read **RELEASE**, **CATCH**, **TURN**,
**EXECUTE**, or the player-facing **STICK** rather than the internal LAND name.
During a landing reaction the strip continues smoothly from the authored
contact point to the end of the dismount rather than stopping at contact.

Click-based execution timing is deliberately strict and scales with move difficulty. The
absolute early/late windows for A / D / G / J elements are respectively:

- no deduction: `50 / 39 / 29 / 18 ms`;
- `0.1`: up to `115 / 98 / 82 / 65 ms`;
- `0.3`: up to `230 / 200 / 170 / 140 ms`;
- beyond that: `0.5`.

Release catches use a separate hold test. Space must be down at the exact frame
the authored CATCH keyframe is crossed; if it is not, the gymnast falls. Once
the catch is secured, deduction is based on total hold duration (including any
time held before the release animation): through `80 ms` is clean, through
`160 ms` is `0.1`, through `300 ms` is `0.3`, and longer is `0.5`. A long hold
still catches the bar. Release Space after the catch to complete the judgement.
A missed catch deducts `1.0`. A popup beside the gymnast combines the result
and deduction as **Too early! −1.0** or **Too late! −1.0**.

Landing uses fixed windows: no deduction through `35 ms`, `0.1` through
`85 ms`, `0.3` through `170 ms`, `0.5` through `300 ms`, then a `1.0` fall.

Press **P** during a performance to pause or resume. Pause freezes the gymnast,
routine timer, film position, timing judgement and automatic misses together.

Releases and dismounts infer release at the first detached-hand frame; releases
infer catch at the first subsequent regrasp; dismount land defaults to first
floor contact. Editor's **Judgement points** window can add, update, remove and
retime `RELEASE`, `CATCH`, `TURN`, `EXECUTE`, and `LAND` clicks per skill.

Landing input is judged when pressed, but an early press does not interrupt the
airborne dismount—the authored animation continues to ground contact before
the reaction plays. Landing outcomes: `0.1` briefly separates the feet, `0.3`
steps forward and returns, `0.5` takes a large step, and no click within `0.5s`
scores `1.0` and falls. After every non-fall reaction, the gymnast blends into
the dismount's authored final pose and holds the arms-up salute to the judges.
The main action button holds on **LANDED** for 1 second, then becomes
**REPEAT ROUTINE**; there is no separate replay button.

A Giant written into a routine is an explicit one-revolution move. Consecutive
Swing-class skills each play once in authored order; they are never collapsed,
so sequences such as `Normal Giant → Tap Giant → Normal Giant` remain visible.
The final Giant before a complex skill also acts as its warning move.
Game mode does not invent hidden connecting giants. Adjacent complex skills
therefore flow directly into one another; for example
`Giant → Kovacs → Kovacs` gives notice only before the first Kovacs, while
omitting the Giant after a mount continues directly into the next skill. Every
direct transition must still satisfy the authored signatures.

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
stage. Green and red timeline markers identify those endpoint keyframes. Game
mode accepts a card in a routine slot only when its START signature matches the
preceding move's END signature.

The library search accepts move names and classes. Editor can
**Rename** a move without changing
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
- mark the selected keyframe as the move's fixed **Execution** target;
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
- `scripts/game.gd` — compose/perform flow, timing judgement, and editor UI
- `scripts/skill_card.gd` — draggable move thumbnails
- `scripts/routine_drop_zone.gd` — transition-valid routine insertion slots

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

## Prototype scoring

Compose shows a potential D score; Perform builds the actual D and E scores.
An element only enters the performed D score when its animation completes;
placing it in the routine does not count. Up to ten distinct completed elements are retained,
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
