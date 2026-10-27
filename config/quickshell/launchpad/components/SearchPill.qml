import "../Common" as Corners
import QtQuick
import QtQuick.Shapes
import ".."

// ─────────────────────────────────────────────────────────────────────────────
//  SearchPill — a glass search capsule with a separate round settings button
//  on its right. The magnifier and the gear are drawn with Shape paths
//  (no icon fonts, no web assets).
//
//  Layout:   [ (magnifier)  Search Applications ]  ( gear )
//
//  The capsule is at least Theme.searchWidth wide and is always widened enough
//  to fit the "Search Applications" placeholder without clipping. The total
//  width of this item = capsule + gap + button.
//
//  The old "ellipsis" button inside the capsule is gone; its job (emit
//  optionsRequested) now belongs to the settings button.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root
    property var captureScreen: null
    property Item backdrop: null
    property point screenPosition: Qt.point(x, y)
    property bool materialActive: LaunchpadState.windowVisible
    property bool shaderFailed: false
    readonly property bool glassReady: glassContext.ready && !shaderFailed
    opacity: glassContext.waiting && !shaderFailed ? 0 : 1
    SearchGlassContext {
        id: glassContext
        anchors.fill: parent
        captureScreen: root.captureScreen
        backdrop: root.backdrop
        screenPosition: root.screenPosition
        active: root.materialActive
    }

    // Kept with the same name so existing connections in the parent still work.
    signal optionsRequested()

    // Gap between the capsule and the round button.
    readonly property real buttonGap: Math.round(height * 0.24)
    // Diameter of the round button (same as the capsule height).
    readonly property real buttonSize: height

    height: Theme.searchHeight

    // Fixed relative to the pill height (NOT to Theme.iconSize), so the
    // settings-panel icon-size slider never scales this text.
    readonly property int fontPx: Math.max(11, Math.round(root.height * 0.39))

    // Horizontal paddings inside the capsule (shared by layout and the minimum-width math).
    readonly property real padLeft: Math.round(height * 0.34)
    readonly property real iconSizePx: Math.round(height * 0.46)
    readonly property real iconTextGap: Math.round(height * 0.28)
    readonly property real padRight: Math.round(height * 0.34)

    // Measures the placeholder so it can never be clipped.
    TextMetrics {
        id: placeholderMetrics
        text: "Search Applications"
        font.family: Theme.fontFamily
        font.pixelSize: root.fontPx
    }

    // Capsule width: at least Theme.searchWidth, and always wide enough for the placeholder.
    readonly property real pillWidth: Math.max(
        Theme.searchWidth,
        padLeft + iconSizePx + iconTextGap + Math.ceil(placeholderMetrics.advanceWidth) + padRight + 6)

    // Total width = capsule + gap + round button.
    width: pillWidth + buttonGap + buttonSize

    function focusInput() {
        input.forceActiveFocus();
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  SEARCH CAPSULE
    // ═════════════════════════════════════════════════════════════════════════
    Item {
        id: pill

        x: 0
        y: 0
        width: root.pillWidth
        height: root.height

        // A true capsule: semicircular ends at every search-field height.
        Corners.ContinuousRectangle { cornerSmoothing: 0;
            visible: !root.glassReady
            anchors.fill: parent
            radius: height / 2
            antialiasing: true
            gradient: Gradient {
                GradientStop { position: 0; color: Theme.searchFillTop }
                GradientStop { position: 1; color: Theme.searchFillBottom }
            }
            border.width: 1
            border.color: Theme.searchBorderMid
        }
        SearchGlassSurface {
            anchors.fill: parent
            context: root.glassReady ? glassContext : null
            onFailed: root.shaderFailed = true
        }

        // focus the field when the user clicks anywhere on the capsule
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            onPressed: root.focusInput()
        }

        // ── magnifier ─────────────────────────────────────────────────────────
        Shape {
            id: magnifier
            readonly property real s: root.iconSizePx
            x: root.padLeft
            anchors.verticalCenter: parent.verticalCenter
            width: s
            height: s
            antialiasing: true
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: Theme.searchText
                strokeWidth: Math.max(1.4, root.height * 0.048)
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathAngleArc {
                    centerX: magnifier.s * 0.42
                    centerY: magnifier.s * 0.42
                    radiusX: magnifier.s * 0.29
                    radiusY: magnifier.s * 0.29
                    startAngle: 0
                    sweepAngle: 360
                }
            }

            // Separate handle meets the circle at its lower-right tangent.
            ShapePath {
                strokeColor: Theme.searchText
                strokeWidth: Math.max(1.4, root.height * 0.048)
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                startX: magnifier.s * 0.625
                startY: magnifier.s * 0.625
                PathLine {
                    x: magnifier.s * 0.88
                    y: magnifier.s * 0.88
                }
            }
        }

        // ── text field ────────────────────────────────────────────────────────
        TextInput {
            selectionColor: Corners.ThemeColors.selectionFor("launchpad", Theme.darkMode)
            selectedTextColor: Corners.ThemeColors.selectedTextFor("launchpad", Theme.darkMode)
            id: input

            anchors.left: magnifier.right
            anchors.leftMargin: root.iconTextGap
            anchors.right: parent.right
            anchors.rightMargin: root.padRight
            anchors.verticalCenter: parent.verticalCenter
            height: root.height

            text: LaunchpadState.query
            color: Theme.searchText


            font.family: Theme.fontFamily
            font.pixelSize: root.fontPx
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            selectByMouse: true
            cursorVisible: LaunchpadState.shown
            activeFocusOnPress: true
            inputMethodHints: Qt.ImhNoPredictiveText

            onTextChanged: {
                if (text !== LaunchpadState.query)
                    LaunchpadState.setQuery(text);
            }

            Connections {
                target: LaunchpadState
                function onQueryChanged() {
                    if (input.text !== LaunchpadState.query)
                        input.text = LaunchpadState.query;
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: input.text.length === 0
                text: "Search Applications"
                color: Theme.searchPlaceholder
                font.family: Theme.fontFamily
                font.pixelSize: input.font.pixelSize
                elide: Text.ElideRight
                width: parent.width
            }

            Keys.onPressed: function (event) {
                if (event.key === Qt.Key_Escape) {
                    if (LaunchpadState.query !== "") {
                        LaunchpadState.setQuery("");
                    } else if (LaunchpadState.folderOpen) {
                        LaunchpadState.closeFolder();
                    } else {
                        LaunchpadState.close();
                    }
                    event.accepted = true;
                    return;
                }
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    LaunchpadState.launch(LaunchpadState.currentItem, true);
                    event.accepted = true;
                    return;
                }
                if (event.key === Qt.Key_Up) {
                    LaunchpadState.moveSelection(0, -1);
                    event.accepted = true;
                    return;
                }
                if (event.key === Qt.Key_Down) {
                    LaunchpadState.moveSelection(0, 1);
                    event.accepted = true;
                    return;
                }
                if (event.key === Qt.Key_Left) {
                    if (LaunchpadState.query === "" && !(event.modifiers & Qt.ControlModifier)) {
                        LaunchpadState.moveSelection(-1, 0);
                        event.accepted = true;
                    } else if (event.modifiers & Qt.ControlModifier) {
                        LaunchpadState.setPage(LaunchpadState.page - 1);
                        event.accepted = true;
                    }
                    return;
                }
                if (event.key === Qt.Key_Right) {
                    if (LaunchpadState.query === "" && !(event.modifiers & Qt.ControlModifier)) {
                        LaunchpadState.moveSelection(1, 0);
                        event.accepted = true;
                    } else if (event.modifiers & Qt.ControlModifier) {
                        LaunchpadState.setPage(LaunchpadState.page + 1);
                        event.accepted = true;
                    }
                    return;
                }
                if (event.key === Qt.Key_Tab) {
                    LaunchpadState.moveSelection((event.modifiers & Qt.ShiftModifier) ? -1 : 1, 0);
                    event.accepted = true;
                    return;
                }
                if (event.key === Qt.Key_Backtab) {
                    LaunchpadState.moveSelection(-1, 0);
                    event.accepted = true;
                    return;
                }
                if (event.key === Qt.Key_Home) {
                    LaunchpadState.selected = 0;
                    event.accepted = true;
                    return;
                }
                if (event.key === Qt.Key_End) {
                    LaunchpadState.selected = Math.max(0, LaunchpadState.viewItems.length - 1);
                    event.accepted = true;
                    return;
                }
                if (event.key === Qt.Key_Backspace && LaunchpadState.query === "") {
                    event.accepted = true;
                }
            }
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  SETTINGS BUTTON  (round glass button, right of the capsule)
    // ═════════════════════════════════════════════════════════════════════════
    Item {
        id: settingsButton

        x: pill.width + root.buttonGap
        y: 0
        width: root.buttonSize
        height: root.buttonSize

        // subtle press feedback
        scale: buttonArea.pressed ? 0.92 : 1.0
        Behavior on scale {
            NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
        }

        // glass disc, same fill and border as the capsule
        Corners.ContinuousRectangle { cornerSmoothing: 0;
            visible: !root.glassReady
            anchors.fill: parent
            radius: width / 2
            antialiasing: true
            gradient: Gradient {
                GradientStop { position: 0; color: Theme.searchFillTop }
                GradientStop { position: 1; color: Theme.searchFillBottom }
            }
            border.width: 1
            border.color: Theme.searchBorderMid
        }
        SearchGlassSurface {
            anchors.fill: parent
            context: root.glassReady ? glassContext : null
            offset: Qt.point(settingsButton.x, settingsButton.y)
            onFailed: root.shaderFailed = true
        }

        // hover / pressed highlight
        Corners.ContinuousRectangle { cornerSmoothing: 0;
            anchors.fill: parent
            radius: width / 2
            antialiasing: true
            color: Theme.searchText
            opacity: buttonArea.pressed ? 0.18 : (buttonArea.containsMouse ? 0.10 : 0.0)
            Behavior on opacity {
                NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
            }
        }

        // ── gear glyph (outline style, matches the magnifier) ────────────────
        // Drawn once in a fixed 100x100 box and then scaled about its center, so
        // the path is never rebuilt and the glyph is always exactly centered.
        Shape {
            id: gear

            readonly property real glyphSize: root.buttonSize * 0.46
            readonly property real k: glyphSize / 100
            readonly property real strokePx: Math.max(1.3, root.height * 0.044)

            // Closed polyline of the toothed outline in 0..100 coordinates.
            readonly property var outline: (function () {
                const teeth = 8;
                const period = (Math.PI * 2) / teeth;
                const topHalf = period * 0.20;    // half-width of a tooth's flat top
                const baseHalf = period * 0.30;   // half-width of a tooth at its base
                const outerR = 47;
                const innerR = 35;
                const pts = [];
                for (let i = 0; i < teeth; ++i) {
                    const a = i * period - Math.PI / 2;
                    const angles = [a - baseHalf, a - topHalf, a + topHalf, a + baseHalf];
                    const radii = [innerR, outerR, outerR, innerR];
                    for (let j = 0; j < 4; ++j) {
                        pts.push(Qt.point(50 + Math.cos(angles[j]) * radii[j],
                                          50 + Math.sin(angles[j]) * radii[j]));
                    }
                }
                pts.push(pts[0]);
                return pts;
            })()

            anchors.centerIn: parent
            width: 100
            height: 100
            scale: k
            transformOrigin: Item.Center
            antialiasing: true
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: Theme.searchText
                strokeWidth: gear.strokePx / gear.k   // compensates the scale
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathPolyline {
                    path: gear.outline
                }
            }

            // center hole
            ShapePath {
                strokeColor: Theme.searchText
                strokeWidth: gear.strokePx / gear.k
                fillColor: "transparent"
                PathAngleArc {
                    centerX: 50
                    centerY: 50
                    radiusX: 15
                    radiusY: 15
                    startAngle: 0
                    sweepAngle: 360
                }
            }
        }

        MouseArea {
            id: buttonArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            onClicked: root.optionsRequested()
        }
    }

    Component.onCompleted: {
        if (LaunchpadState.shown)
            Qt.callLater(focusInput);
    }
}
