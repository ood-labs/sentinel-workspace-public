# UI Interactions and Shortcuts

This page covers the keyboard and mouse controls in the current Sentinel DIST application. Shortcuts yield to text fields, the embedded terminal, and an authored viewport that owns the same key.

## Global Commands

| Input | Result |
|---|---|
| `Ctrl+Z` | Undo the latest graph, parameter, or project edit. |
| `Ctrl+Y` or `Ctrl+Shift+Z` | Redo the latest undone edit. |
| `Ctrl+S` | Save the current project to its existing path. |
| `Ctrl+C` | Copy the selected graph nodes. |
| `Ctrl+V` | Paste copied graph nodes with a small position offset. |
| `Ctrl+Shift+R` | Start or stop a Capture Session. When the Terminal owns keyboard focus, this chord restarts the terminal instead. |
| `Ctrl+Shift+M` | Drop a marker into an active Capture Session. |
| `Alt+F4` | Exit Sentinel through the Windows window command. |

Use the File menu for New Project, Open Project, and Save Project As. The menu shows `Ctrl+N`, `Ctrl+O`, and `Ctrl+Shift+S` labels. The current DIST input handler only implements `Ctrl+S` directly, so the File menu is the reliable path for the other three commands.

Click the temporary "Agent workspace ready" toast to dismiss it early.

### Save and reopen a project

1. Choose **File > Save Project As** the first time and select a `.sentinel` path.
2. Press `Ctrl+S` after later edits to update that file.
3. Choose **File > Open Project** and select the saved file.
4. Confirm the replacement when Sentinel reports unsaved work.
5. Wait for engine-backed and Module nodes to settle, then check that the expected nodes, links, and previews are present.

## Node Graph

### Select, move, and navigate

- Left-click a node to select it. Hold `Ctrl` while clicking to add or remove nodes from the selection.
- Drag a node title to move it. Drag empty canvas to box-select nodes.
- Left-click empty canvas to clear the graph and Properties selection.
- Drag with the middle mouse button to pan. `Alt` plus left-drag provides the same pan gesture.
- Use the mouse wheel over the graph to zoom.
- Press `F` while the Graph panel is focused to fit all nodes.
- Press `G` to focus the current selection.
- Press `Ctrl+D` to duplicate the selected nodes.
- Press `Shift+Delete` to delete the selected nodes. The graph asks for confirmation.
- Double-click a pipeline node to open and focus its pipeline panel.

### Wire and detach

Create a texture or data link by dragging from an output pin to a compatible input pin. Dragging in the reverse direction is accepted and normalized to output-to-input flow. Dropping a live link on empty canvas opens a creation menu containing compatible sources, nodes, and outputs, then connects the new object automatically.

Dragging a control-output pin to a numeric pipeline input opens the control mapping menu. Choosing a target parameter installs a `ref("node/control_outputs/name")` expression for that parameter.

To detach a link:

1. Hold `Ctrl`.
2. Left-click the link and begin a drag.
3. Release on empty canvas, or reconnect the loose end to a compatible pin.
4. Confirm that the old link is gone before saving.

Right-click a link or a connected input pin and choose **Disconnect** when a menu-driven detach is easier.

### Node controls and context menus

- Every pipeline node header carries three buttons: `F` freezes the node on its last completed output, `B` bypasses it with type-aware passthrough of video, data, and Mesh ports, and `P` shows or hides the node-local preview. Neither `F` nor `B` engaged is Normal. See `node-modes.md`.
- `F`, `B`, and `P` keys apply the same toggles to the selected nodes. A shut-down node must be launched from its context menu before it can run.
- Right-click a node for launch or shutdown, capture, duplication, deletion, viewport-target, Scene Group, and panel-presentation actions that apply to that node.
- Right-click empty canvas to create a source, node, output, feedback object, or annotation. Node-only actions stay on the node menu.
- Right-click a link or input pin to disconnect it.
- Hover a cable to see the schema it carries and, for Module data outputs with an authored `description`, what one record means. Data links can animate their flow, and reference lines anchor at node body centers with direction arrows.
- DMX In and DMX Out headers hold a `<` `>` universe stepper and a jump field for the universe grid drawn in the node body; OSC Out's header `+` adds a message. See `lighting-and-show-control.md`.

### Annotations and Scene Groups

- Double-click an annotation title or body to edit it. `Enter` finishes title editing. `Escape`, a middle-mouse gesture, or a click outside finishes the active edit.
- Drag an annotation title to move the annotation. Hold `Shift` during the drag to move fully contained nodes with it. Scene Group annotations always move their contained nodes.
- Drag the lower-right corner handle to resize an annotation.
- Click the color swatch to edit its color.
- Click the annotation `A` button to toggle all contained pipelines. On a Scene Group, it toggles the group.
- A Scene Group collected by a Groups-mode Mux shows a switch control on its header; click it to select that group on the switcher. The header also reads back which group the switcher holds.
- Right-click a Scene Group annotation for `Export Scene Group`, which writes a portable `.sentinel` file. Converting an annotation to a Scene Group and reverting it both undo. See `portable-scene-groups.md`.

## Pipeline Panels and Previews

Clicking a pipeline panel outside its preview selects that pipeline in Properties. Preview interaction keeps the existing Properties selection, which supports editing one node while navigating another node's viewport.

The preview panel has a real view transform. A `Fit`, `Fill`, `1:1` combo in the panel header picks the framing, and free zoom with pan sits on top of it: zoom anchors at the cursor, pan clamps to the content, and each node's framing persists with the project. Once the view is zoomed or panned, a zoom percentage button appears beside the combo; click it to reset the view. Two-output nodes can show a split preview. Per-node panel presentation (Standard or Canvas) and resolution mode (Pipeline, Follow Panel, or the 1/4x, 1/2x, and 2x Follow Panel scales) live in Properties and read back through `sentinel_pipeline info`.

- The wheel zooms the preview view around the pointer, and holding `Space` while left-dragging pans it (the `preview.zoom` and `preview.pan` bindings).
- Over a node that exposes `pan_x`, `pan_y`, and `zoom`, or a camera-driven viewport, the bare wheel and left-drag belong to the node: wheel drives the node's `zoom` or camera dolly, left-drag drives its pan, and double-click resets them. Hold `Ctrl` with the wheel there to zoom the preview view instead.
- Hold `Alt` for 10x finer movement. Hold `Alt+Shift` for 100x finer movement.

Right-click a connected input tile to route preview mouse input to that upstream pipeline. Right-click the selected tile again to clear passthrough.

## Camera Viewport Navigation

Click the camera-capable preview before using its keys.

Orbit mode:

- Right-drag to orbit.
- `Shift` plus right-drag, or middle-drag, to pan the target.
- Use the wheel to dolly.
- `W`, `A`, `S`, `D`, `Q`, and `E` move the camera and target together.

Fly mode:

- Right-drag to look.
- Use `W`, `A`, `S`, and `D` to move horizontally relative to the view.
- Use `Q` and `E` to move down and up.
- Hold `Shift` for 3x movement speed.
- Use the wheel to change movement speed.

Press `Tab` while the preview is focused to toggle Orbit and Fly. The Camera node's current viewport hint still names `C`; the active preview input route consumes `Tab`.

## Properties

- Drag a numeric slider to edit it. Hold `Alt` for 10x finer relative dragging, or `Alt+Shift` for 100x finer dragging.
- Double-click an integer or float slider to restore its default.
- Right-click a parameter for Reset to Default, expression, editable-range, binding, preset, exposure, and OSC actions that apply to that parameter.
- Shift-click a pipeline parameter label or numeric slider to lock or unlock it for parameter randomization.
- Touching an expression-driven integer or float slider clears its driving expression at the start of the gesture. One undo restores the expression.
- Drag an XY pad normally for absolute placement. Start the drag with `Alt` for relative fine motion, with `Alt+Shift` for the finest motion.
- Double-click a Scene Group compound color or XY control to restore that compound unit's defaults.
- In a multiline prompt field, press `Enter` to submit and `Ctrl+Enter` to add a line.
- Drag the video-source scrubber to seek. The play, pause, restart, and single-frame buttons sit beside it.
- `Enter` accepts preset and rename dialogs. `Escape` cancels them.

## Sources, Outputs, and Presets

- Click a source chip to select it. Drag the chip to a compatible graph target.
- Press `F2` on the selected source to rename it. Press `Enter` to commit or `Escape` to cancel. Clicking elsewhere also cancels the edit.
- Right-click a source or output chip for its type-specific actions, rename, and deletion controls.
- Right-click a preset for recall-management actions. Preset-name dialogs accept `Enter` and cancel with `Escape`.

## Embedded Terminal

- Click the terminal grid to give it keyboard focus. Clicking another panel releases terminal capture.
- Drag across cells to select text. Releasing the drag copies a nonempty selection to the clipboard.
- Use `Ctrl+Shift+C` to copy the current selection.
- Use `Ctrl+V`, `Ctrl+Shift+V`, or `Shift+Insert` to paste.
- Use the wheel for scrollback. Click the scrollback position chip to return to the live bottom.
- Right-click the grid for the terminal context menu.
- Press `Ctrl+Shift+R` while the terminal owns focus to restart its shell session.
- Control letters, arrows, navigation keys, function keys, Enter, Tab, Backspace, Escape, Insert, and Delete are forwarded to the terminal process.
- The terminal's Launch command and Workspace folder are set in Settings, in matching Embedded Terminal sections on the System and Project tabs. The Project value is saved in the project file and overrides the System value.
- Clearing the Launch command opens a plain interactive PowerShell session instead of an agent CLI.
- Settings changes apply to the next terminal session. Use Restart Terminal in either Settings tab, or `Ctrl+Shift+R` in the grid, to apply them now.

## Panels, Docking, and Turbo Mode

Open or close panels from the View menu. Drag a panel tab to dock it beside, above, or below another docked panel. Drag it away from a dock target to float it. Use **View > Reset Layout**, then restart Sentinel, to restore the default layout.

Use **View > Panel Presentation** on a selected Module to follow the Module declaration or force Standard or Canvas presentation.

Use **View > Turbo Mode** to toggle reduced UI work for performance-sensitive operation.

## Authored Module Controls

Authored Module panels and previews can declare their own buttons, sliders, XY pads, keyboard interests, selection tools, and transform gizmos. Sentinel routes focus, pointer capture, undo, and committed parameter edits according to the Module manifest. See [Authored Module UI](ui-authoring.md) for authoring and interaction contracts, including hit regions, pointer capture, selection, and authored gizmos.

Press `Escape` to cancel active authored pointer capture. Windows and application-reserved chords such as the Windows key, `Alt+Tab`, `Alt+Space`, and `Ctrl+Escape` stay with the host. Other letters, digits, arrows, navigation keys, and declared modifiers reach an authored viewport only when its manifest requests them and the viewport owns focus.

## Input Bindings

Keyboard and mouse actions are named and editable in `Settings > Bindings`. Click a row, press one key, mouse button, wheel direction, or key-plus-mouse chord; `Escape` cancels capture. Same-scope conflicts ask for an explicit Replace or Cancel. `Reset` restores one row and `Reset All` restores the Sentinel Default layout. Bindings persist per user, never in project files.

Two complete layouts ship. Sentinel Default pans with middle-drag or `Alt`+left-drag, selects with left-click, box-selects with left-drag on empty canvas, and detaches a link with `Ctrl`+left-click. The TouchDesigner layout pans with left-drag on empty canvas, moves nodes with left-drag on the node, selects with right-click, and box-selects with right-drag; the context menu stays on right-click and opens on release. Both keep `F`, `B`, `P`, and `G` (focus the selection, or fit the whole graph when nothing is selected). Pointer bindings are target-aware, so a binding on a node, pin, or canvas only fires where it belongs.

## Scope and Exclusions

This page includes every user-reachable DIST binding found in the graph, pipeline preview, Properties, Sources, Outputs, Presets, Terminal, main-window, viewport-router, and Camera input paths.

The following code paths are excluded from the user binding list:

- Automation ItemTracker click targets and synthetic viewport ingress: internal/not-user-reachable. They expose existing UI behavior to tests and agents.
- Viewport performance-storm and cancellation-test actions: internal/not-user-reachable.
- Controls compiled only under non-DIST pipeline or debug feature gates: dev-build-only or disabled-in-DIST.
