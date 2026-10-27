# Large folder drag-out — implementation and verification

Implemented in the existing Quickshell QML configuration on 2026-10-22.

## Follow-up: real grid folder removal fixed

The initial tests opened folders directly with JavaScript objects. In the actual UI, FolderTile receives its item through the PagedGrid Repeater/Loader; nested items are exposed as a QML V4Sequence. Array.isArray(foldered.items) returns false for that valid list, causing both drag-out and the menu commit to be rejected before any layout update.

The state now copies QML lists with listCopy (Array.prototype.slice.call) before validating membership or changing arrays. Source folder children and page arrays are copied consistently. New regressions open a folder by clicking its actual FolderTile in PagedGrid, then exercise drag-out and the manual menu commit separately. An explicit list<var> fixture also tests V4Sequence input.

A temporary baseline with the old array guard reproduces the failure; the fixed suite reports 21 passed and 0 failed, plus the state conservation suite and independent restart round trip. The user subsequently confirmed that BOTH drag-out and Remove from Folder work in their actual Hyprland session. Temporary diagnostic logs were removed; detailed logs remain behind debugDrag.

## Implementation

Approach A: folder cells own an overlay MouseArea. AppTile's interaction is explicitly disabled for these cells; its top-level drag pipeline remains unchanged. A folder drag has one ghost, one insertion indicator, and one call to removeFromFolder. The ghost stays outside the clipped Flickable, preserves the grab offset, and dims/reveals the panel/grid without changing the grid's 0.96 scale.

The existing code differed from the prompt: FolderPanel already contained most drag visuals; PagedGrid already mapped both corners and supplied slotAt/slotRect; LaunchpadWindow already passed backdrop/gridItem and brightened the grid. The incompatible state method was removeFromFolder(folderId, appId), which appended to the last page. It now accepts (item, targetPage, index) and returns a boolean. The parameter is named targetPage to avoid shadowing the state's page property.

Removal identifies apps by id, reads the current source folder, copies the folder and page arrays, cleans up empty/single-child folders, adjusts insertion indices after cleanup, and cascades overflow forward. It leaves hidden/usage untouched, switches to manual sorting, updates the open folder, sets justDroppedId, and uses the existing 500 ms save debounce and atomic FileView writes. A busy guard and validation reject invalid, hidden, stale, and duplicate sources. Debug mode checks uniqueness, hidden apps, page capacity, and empty folders/trailing pages.

While searching, destination page/index are ignored and the app is inserted immediately after its former folder. The query remains intact. The visible page tracks the moved app's search-result page, since search pages and layout pages have different indices.

Startup now waits for the initial DesktopEntries changes to settle before resolving saved ids. Valid partial pages are preserved rather than repacked unconditionally at startup. Both issues were caught by the actual save/load and second-process restart tests.

## Controls

Settings → Features → Large Folder:

- Close Folder After Removing an App: default true.
- Dissolve Single-App Folders: default false.
- The existing folder blur and Liquid Glass controls are preserved.

Esc during a drag cancels only the drag and suppresses the remainder of that mouse press. Right-click offers Remove from Folder. Shift+Enter removes the selected folder app; arrows/Tab select an app. Long press enters edit mode without launching. Rename Enter/Escape are consumed locally. Normal close uses the panel's reverse zoom; removal of an empty or dissolved folder closes immediately through state cleanup.

Run with LAUNCHPAD_DEBUG_DRAG=1 to show grid/slot outlines and drag/invariant logs. Debugging is disabled by default. Timers stop after their startup, animation, debounce, or capture work; there is no new periodic idle polling.

## Files delivered in full

- LaunchpadState.qml
- Theme.qml
- components/FolderPanel.qml
- components/PagedGrid.qml
- components/LaunchpadWindow.qml
- components/AppTile.qml
- components/FolderTile.qml
- components/SettingsPanel.qml
- tests/FolderDragTests.qml
- tests/PersistenceRestartTest.qml
- tests/state-test.cjs
- tests/run-tests.sh

FolderTile.qml only gains an objectName for the real grid-click regression. Its preview logic stays unchanged; the state replaces the folder object so preview bindings refresh. The existing blur shader/assets were not modified by this task.

## Verification

Environment: Quickshell 0.3.2, Qt 6.12.0. All changed QML files pass qmllint. The bash runner passes bash -n. Qt 6 qmllint exits with code 0 and no syntax errors; it still reports scoped-id and dynamic Item-method diagnostics in this configuration, so this is not a claim of warning-free static lint.

The runner copies the configuration and redirects XDG_STATE_HOME/XDG_RUNTIME_DIR to a temporary directory. It exercises the production components using QtTest mouse/key events in an offscreen Qt Window. It does not launch desktop applications or write the user's layout. Click-to-launch uses a test entry with an execute counter. Persistence tests use real installed desktop ids and the production FileView serializer/loader, then launch a second Quickshell process to verify the saved page structure survives startup.

The state suite passes 11 explicit scenarios, 5 failure guards, and 500 deterministic randomized conservation/pagination cases. The native suite reports 21 passed and 0 failed (including initialization), including extra checks for closeAfterRemove=false, Shift+Enter, long press, rename, panel destruction during drag, and pop-in timing.

## T1–T14 checklist

The agent cannot control the real Wayland/GPU session from this environment. The table below records automated coverage. After the V4Sequence fix, the user manually confirmed both drag-out and Remove from Folder work in the actual Hyprland session; that confirmation does not certify every separate item in T1–T14.

| Test | Automated result | Evidence and manual remainder |
| --- | --- | --- |
| T1 | PASS | Mouse drag to append slot; folder retains the other two apps and a new folder object. Preview pixels still require a desktop visual check. |
| T2 | PASS | Mouse drag inserts before the indicated existing app. |
| T3 | PASS | Both keep-single and dissolve-single settings tested. |
| T4 | PASS | Last child becomes top-level and folder closes. |
| T5 | PASS | Full page cascades overflow to the front of the next page. |
| T6 | PASS | Release inside leaves layout unchanged and does not launch. |
| T7 | PASS | Real Escape key cancels drag, retains folder/query, and further motion during that press cannot restart it. |
| T8 | PASS (logic) | Click executes the test entry once; right-click records a folder-source menu; rename and outside close pass. Actual desktop launch/menu rendering remain manual. |
| T9 | PASS | Search retains query, hides the insertion indicator, and inserts after the former folder in layout. |
| T10 | PASS | Production save/load plus independent-process restart preserve serialized folder/page structure, including a partial first page. |
| T11 | PASS | Qt wheel events scroll a 30-app folder; dragging disables Flickable interaction and commits correctly. |
| T12 | PASS (events/geometry) | Fast release-only destination, slow motion, and grab offset pass. Perceived ghost smoothness requires GPU visual inspection. |
| T13 | PASS (coordinates) | Three show/hide cycles and animated 0.96 folder scale; actual slot and indicator coordinates agree. Debug overlay appearance remains manual. |
| T14 | PASS (lint and test QML); MANUAL UNVERIFIED | No application QML warnings/errors in the final automated suite. Offscreen startup reports unavailable Wayland/GL/IPC facilities. The actual config reloads successfully, but absence of warnings during a real desktop drag has not been certified. |

## Reproduce

From the existing configuration directory:

```sh
./tests/run-tests.sh
```

Requires qs, node, rg, timeout, bash, and QtTest. The runner prints the temporary directory containing both test logs and the isolated layout. It fails if assertions fail, application QML warnings occur, or the restart structure differs.

## Remaining limits

Real Hyprland screencopy, Liquid Glass GPU appearance, cross-monitor pointer behavior, perceived animation smoothness, and desktop idle CPU measurements remain unverified in this sandbox. The QtTest reporting uses Qt's qtest_results property because tests are hosted inside Quickshell; a future QtTest API change may require adapting the harness. Optional edge page flipping and merge-on-hover were not added; folder drag-out always inserts at the chosen slot.
