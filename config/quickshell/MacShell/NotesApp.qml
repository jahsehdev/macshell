// Notes — the macOS Notes app for MacShell: folder sidebar, dated notes list,
// text editor with formatting, and a drawing canvas with a floating glass palette.
//
//   qs -c MacShell ipc call notes open          (also: notes new)
//
// Lives inside MacShell like the Clock app. Notes and drawings are stored in SQLite
// at ~/.local/share/macshell/notes/notes.db through bin/notes.py (one-shot process,
// JSON on stdout, no network). Strokes are stored vector-style, so a drawing can be
// re-edited after reopening and exported to PNG or SVG at any size.
//
// Layout follows macOS Notes: a folder sidebar on the left (with counts and
// Recently Deleted), a middle column with the notes list grouped by date
// (Pinned / Today / Yesterday / Previous 7 & 30 Days / month year), and the
// editor on the right. The toolbar buttons and the floating drawing palette use
// a Liquid-Glass style pill: translucent vertical gradient + 1px rim + inner top
// highlight (the same look as ControlSurface.qml).
import "Common" as Corners
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root
    property var hub: null
    readonly property var dock: hub ? hub.dock : null
    readonly property var bar: hub ? hub.bar : null
    readonly property bool darkMode: dock ? dock.darkMode : true
    readonly property string fam: dock ? dock.fontFamily : "SF Pro Text"
    readonly property color accent: Corners.ThemeColors.accentFor("notes")
    readonly property string home: Quickshell.env("HOME")
    readonly property string notesPy: Quickshell.shellPath("bin/notes.py")
    readonly property string dbPath: home + "/.local/share/macshell/notes/notes.db"
    readonly property string exportDir: home + "/Documents/MacShell Notes"
    readonly property bool reduceMotion: Corners.DesktopPreferences.reduceMotion

    // ═════════════ STATE ═════════════
    property var notes: []                 // summaries from `notes.py list`, sorted + date-grouped
    property var folders: []               // [{name, count}] from `notes.py folders`
    property int allCount: 0
    property int trashCount: 0
    property string folderFilter: "All"    // "All" | "Trash" | a folder name
    property var current: null             // the loaded note { id, title, body, strokes, ... }
    property string query: ""
    property string view: "text"           // text | drawing
    property var strokes: []               // committed strokes of the current note
    property var redoStrokes: []           // legacy compatibility
    property var drawingHistory: []        // undoable add / erase / clear operations
    property var drawingRedo: []           // redoable drawing operations
    property string tool: "pen"
    property string brushName: "Pen"
    property bool brushMenuOpen: false            // pen | line | rect | ellipse
    property int penIndex: 0               // index into palette
    property real penWidth: 3              // px on the live canvas
    property bool drawing: false           // a stroke is being drawn
    property var pendingStroke: null
    property bool dirty: false             // unsaved edits
    property bool loading: false           // a note is being loaded into the fields
    property bool listReady: false
    property string confirmDelete: ""      // note id awaiting a second Delete click
    property bool afterDelete: false       // list changed under us; re-select once it arrives
    property bool addingFolder: false      // inline "new folder" row is visible
    property bool sidebarCollapsed: false  // macOS sidebar toggle
    property string sortBy: "updated"      // "updated" | "created" | "title"
    property string sortOrder: "desc"      // "desc" | "asc"
    property var smartCounts: ({ pinned: 0, locked: 0, checklists: 0, drawings: 0, math: 0 })
    property bool currentUnlocked: true
    readonly property bool trashView: folderFilter === "Trash"
    readonly property var palette: ["#1D1D1F", "#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#007AFF", "#AF52DE", "#A2845E"]
    readonly property var toolNames: ["pen", "line", "rect", "ellipse"]

    // Liquid Glass control surface based on MacShell ControlSurface.qml:
    // Translucent vertical gradient + crisp 1px non-glowing rim + inner top highlight.
    component GlassSurface: Item {
        id: gs
        property bool dark: false
        property bool hovered: false
        property bool pressed: false
        property bool selected: false
        property bool circle: false
        property var backdropSource: null
        property Item sceneRoot: null
        property real cornerRadius: height / 2

        // Soft ambient drop shadow underneath (matching MacTahoe box-shadow: 0 6px 20px rgba(0,0,0,0.15))
        Corners.ContinuousRectangle {
            anchors.fill: parent
            y: gs.pressed ? 0.5 : 1
            radius: gs.cornerRadius
            normalizeRadius: false
            cornerSmoothing: gs.circle ? 0 : Corners.CornerTheme.smoothing
            color: gs.dark ? "#26000000" : "#0D000000"
        }

        // Base gradient surface (matching Nautilus MacTahoe GTK theme translucent gradient)
        Corners.ContinuousRectangle {
            anchors.fill: parent
            radius: gs.cornerRadius
            normalizeRadius: false
            cornerSmoothing: gs.circle ? 0 : Corners.CornerTheme.smoothing
            gradient: Gradient {
                GradientStop {
                    position: 0.0
                    color: gs.dark
                        ? (gs.selected ? "#22FFFFFF" : gs.pressed ? "#35FFFFFF" : gs.hovered ? "#16FFFFFF" : "#0DFFFFFF")
                        : (gs.selected ? "#18000000" : gs.pressed ? "#22000000" : gs.hovered ? "#0F000000" : "#07000000")
                    Behavior on color { ColorAnimation { duration: 100 } }
                }
                GradientStop {
                    position: 1.0
                    color: gs.dark
                        ? (gs.selected ? "#18FFFFFF" : gs.pressed ? "#26FFFFFF" : gs.hovered ? "#0EFFFFFF" : "#07FFFFFF")
                        : (gs.selected ? "#1E000000" : gs.pressed ? "#28000000" : gs.hovered ? "#14000000" : "#0A000000")
                    Behavior on color { ColorAnimation { duration: 100 } }
                }
            }
            // Subtle 1px boundary stroke (matching MacTahoe inset 0 0 0 1px rgba(255,255,255,0.08))
            border.width: 1
            border.color: gs.dark
                ? (gs.hovered ? "#1FFFFFFF" : gs.selected ? "#28FFFFFF" : "#14FFFFFF")
                : (gs.hovered ? "#1C000000" : gs.selected ? "#24000000" : "#12000000")

            // Top specular hairline (matching MacTahoe inset 1px 2px 1px -1px rgba(255,255,255,0.08))
            Corners.ContinuousRectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: Math.max(0, gs.cornerRadius - 1)
                normalizeRadius: false
                cornerSmoothing: gs.circle ? 0 : Corners.CornerTheme.smoothing
                color: "transparent"
                border.width: 1
                border.color: gs.dark ? (gs.hovered ? "#18FFFFFF" : "#10FFFFFF") : "#50FFFFFF"
            }
        }
    }

// Dedicated solid popover surface matching MacTahoe GTK popovers
    component MenuSurface: Item {
        id: ms
        property bool dark: false
        property real cornerRadius: 13

        // Ambient drop shadow (deep and soft, popover floating effect)
        Corners.ContinuousRectangle {
            anchors.fill: parent
            anchors.margins: -3
            y: 3
            radius: ms.cornerRadius + 3
            normalizeRadius: false
            color: ms.dark ? "#55000000" : "#20000000"
        }
        Corners.ContinuousRectangle {
            anchors.fill: parent
            y: 7
            radius: ms.cornerRadius
            normalizeRadius: false
            color: ms.dark ? "#80000000" : "#25000000"
        }

        // Solid background matching MacTahoe popovers (#262629 in dark, #F6F6F8 in light)
        Corners.ContinuousRectangle {
            anchors.fill: parent
            radius: ms.cornerRadius
            normalizeRadius: false
            color: ms.dark ? "#262629" : "#F6F6F8"
            border.width: 1
            border.color: ms.dark ? "#38FFFFFF" : "#22000000"

            // Inner subtle specular highlight
            Corners.ContinuousRectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: Math.max(0, ms.cornerRadius - 1)
                normalizeRadius: false
                color: "transparent"
                border.width: 1
                border.color: ms.dark ? "#14FFFFFF" : "#60FFFFFF"
            }
        }
    }

    component GlassButton: Item {
        id: gb
        property string icon: ""
        property string sym: ""
        property string tip: ""
        property bool bigger: false
        property bool slim: false
        property bool active: false
        property bool dimmed: false
        property bool dark: false
        property var backdropSource: null
        property Item sceneRoot: null
        property color activeColor: "#007AFF"
        property int fontPx: 14
        property int fontWeight: Font.Normal
        property real cornerRadius: height / 2
        signal clicked()
        // Matching Nautilus MacTahoe circular button size
        width: 30
        height: 30
        opacity: dimmed ? 0.38 : 1

        GlassSurface {
            anchors.fill: parent
            dark: gb.dark
            hovered: gbMa.containsMouse && !gb.dimmed
            pressed: gbMa.pressed
            selected: gb.active
            cornerRadius: height / 2
            circle: true
        }

        // Active indicator ring if active (perfect circle, MacTahoe style)
        Corners.ContinuousRectangle {
            anchors.centerIn: parent
            width: parent.height - 4
            height: width
            radius: width / 2
            normalizeRadius: false
            cornerSmoothing: 0
            visible: gb.active
            color: "transparent"
            border.width: 1.2
            border.color: gb.dark ? "#35FFFFFF" : "#25000000"
        }

        NoteIcon {
            visible: gb.icon !== ""
            anchors.centerIn: parent
            kind: gb.icon
            size: gb.bigger ? 18.5 : gb.slim ? 16.5 : 17.5
            strokeWidth: 1.55
            color: gb.active ? (gb.dark ? "#FDFDFD" : "#1D1D1F") : (gb.dark ? "#FDFDFD" : "#242428")
        }

        Text {
            visible: gb.icon === "" && gb.sym !== ""
            anchors.centerIn: parent
            text: gb.sym
            color: gb.active ? (gb.dark ? "#FDFDFD" : "#1D1D1F") : (gb.dark ? "#FDFDFD" : "#242428")
            font.family: "SF Pro Text"
            font.pixelSize: gb.bigger ? 16 : (gb.fontPx > 0 ? gb.fontPx : 14)
            font.weight: Font.DemiBold
        }
        MouseArea {
            id: gbMa
            anchors.fill: parent
            hoverEnabled: true
            enabled: !gb.dimmed
            cursorShape: Qt.PointingHandCursor
            onClicked: gb.clicked()
        }
        Accessible.role: Accessible.Button
        Accessible.name: gb.tip
        Accessible.onPressAction: if (!gb.dimmed) gb.clicked()
    }

    // Segmented / capsule tool button for the unified toolbar in Foto 2
    component ToolPillButton: Item {
        id: tpb
        property string icon: ""
        property string sym: ""
        property string tip: ""
        property bool active: false
        property bool dimmed: false
        property bool dark: false
        property int fontPx: 14
        signal clicked()
        width: sym !== "" ? 34 : 31; height: 30
        opacity: dimmed ? 0.35 : 1

        // MacTahoe hover pill
        Corners.ContinuousRectangle {
            anchors.fill: parent; anchors.margins: 1.5
            radius: height / 2
            normalizeRadius: false
            cornerSmoothing: 0
            color: tpbMa.containsMouse && !tpb.dimmed ? (tpb.dark ? "#1CFFFFFF" : "#12000000") : "transparent"
        }

        // Active circle indicator (matches MacTahoe active/checked button)
        Corners.ContinuousRectangle {
            anchors.centerIn: parent
            width: 24; height: 24; radius: 12
            normalizeRadius: false
            cornerSmoothing: 0
            visible: tpb.active
            color: tpb.dark ? "#26FFFFFF" : "#18000000"
            border.width: 1
            border.color: tpb.dark ? "#35FFFFFF" : "#22000000"
        }

        NoteIcon {
            visible: tpb.icon !== ""
            anchors.centerIn: parent
            kind: tpb.icon
            size: 17
            strokeWidth: 1.55
            color: tpb.dark ? "#FDFDFD" : "#242428"
        }

        Text {
            visible: tpb.icon === "" && tpb.sym !== ""
            anchors.centerIn: parent
            text: tpb.sym
            color: tpb.dark ? "#FDFDFD" : "#242428"
            font.family: root.fam
            font.pixelSize: tpb.fontPx
            font.weight: Font.DemiBold
        }

        MouseArea {
            id: tpbMa
            anchors.fill: parent
            hoverEnabled: true
            enabled: !tpb.dimmed
            cursorShape: Qt.PointingHandCursor
            onClicked: tpb.clicked()
        }
    }

    component MenuItemRow: Item {
        id: mir
        property string label: ""
        property bool checked: false
        property bool hasCheck: false
        property bool danger: false
        property bool dim: false
        property bool dark: true
        property string fam: "SF Pro Text"
        signal clicked()
        width: parent ? parent.width : 100; height: 30
        Corners.ContinuousRectangle {
            anchors.fill: parent; radius: 6; normalizeRadius: false
            color: mirMa.containsMouse
                ? (mir.danger ? "#D63A32" : (mir.dark ? "#007AFF" : "#007AFF"))
                : "transparent"
        }
        NoteIcon {
            visible: mir.hasCheck && mir.checked
            x: 8; anchors.verticalCenter: parent.verticalCenter
            kind: "check"; size: 12; strokeWidth: 1.8
            color: mirMa.containsMouse ? "#FFFFFF" : (mir.dark ? "#F5F5F7" : "#1D1D1F")
        }
        Text {
            x: mir.hasCheck ? 26 : 12; anchors.verticalCenter: parent.verticalCenter
            width: parent.width - (mir.hasCheck ? 36 : 24)
            text: mir.label
            color: mirMa.containsMouse
                ? "#FFFFFF"
                : (mir.dim ? (mir.dark ? "#50FFFFFF" : "#50000000") : (mir.danger ? "#FF453A" : (mir.dark ? "#F5F5F7" : "#1D1D1F")))
            font.family: mir.fam; font.pixelSize: 13
            font.weight: mirMa.containsMouse ? Font.Medium : Font.Normal
            elide: Text.ElideRight
        }
        MouseArea { id: mirMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: mir.clicked() }
    }

    component FolderGlyph: Item {
        id: fg
        property real size: 16
        property bool hasPlus: false
        width: size; height: size * 0.82
        Corners.ContinuousRectangle {
            x: 1; y: 0; width: fg.width * 0.42; height: fg.height * 0.35
            radius: 1.5; normalizeRadius: false; color: "#D9991C"
        }
        Corners.ContinuousRectangle {
            y: fg.height * 0.2; width: fg.width; height: fg.height * 0.8
            radius: 3; normalizeRadius: false; color: "#F5B838"
            border.width: 0.8; border.color: "#DC9F20"
            Corners.ContinuousRectangle {
                anchors.fill: parent; anchors.margins: 0.8
                radius: 2.2; normalizeRadius: false; color: "transparent"
                border.width: 0.6; border.color: "#35FFFFFF"
            }
        }
    }

    component NoteIcon: Canvas {
        id: ico
        property string kind: ""
        property color color: "#FFFFFF"
        property real size: 17
        property real strokeWidth: 1.5

        width: size; height: size
        antialiasing: true

        onKindChanged: requestPaint()
        onColorChanged: requestPaint()
        onSizeChanged: requestPaint()

        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            ctx.clearRect(0, 0, width, height);
            ctx.strokeStyle = color;
            ctx.fillStyle = color;
            ctx.lineWidth = strokeWidth;
            ctx.lineCap = "round";
            ctx.lineJoin = "round";

            var w = width, h = height;
            var k = kind;

            if (k === "more") {
                var r = Math.max(1.6, w * 0.10);
                var cy = h / 2;
                ctx.beginPath();
                ctx.arc(w * 0.22, cy, r, 0, Math.PI * 2);
                ctx.arc(w * 0.50, cy, r, 0, Math.PI * 2);
                ctx.arc(w * 0.78, cy, r, 0, Math.PI * 2);
                ctx.fill();
            } else if (k === "sidebar") {
                var bw = w - 4, bh = h - 4;
                ctx.strokeRect(2, 2, bw, bh);
                ctx.beginPath();
                ctx.moveTo(2 + bw * 0.38, 2);
                ctx.lineTo(2 + bw * 0.38, 2 + bh);
                ctx.stroke();
            } else if (k === "folder-new") {
                ctx.beginPath();
                ctx.moveTo(1.5, 3.5);
                ctx.lineTo(5.5, 3.5);
                ctx.lineTo(7.5, 5.5);
                ctx.lineTo(15.5, 5.5);
                ctx.lineTo(15.5, 14.5);
                ctx.lineTo(1.5, 14.5);
                ctx.closePath();
                ctx.stroke();
                // Plus sign
                ctx.beginPath();
                ctx.moveTo(11, 8.5); ctx.lineTo(11, 12.5);
                ctx.moveTo(9, 10.5); ctx.lineTo(13, 10.5);
                ctx.stroke();
            } else if (k === "compose") {
                ctx.beginPath();
                ctx.moveTo(w * 0.58, h * 0.22);
                ctx.lineTo(w * 0.18, h * 0.22);
                ctx.lineTo(w * 0.18, h * 0.82);
                ctx.lineTo(w * 0.82, h * 0.82);
                ctx.lineTo(w * 0.82, h * 0.44);
                ctx.stroke();
                ctx.beginPath();
                ctx.moveTo(w * 0.46, h * 0.58);
                ctx.lineTo(w * 0.82, h * 0.18);
                ctx.lineTo(w * 0.88, h * 0.24);
                ctx.lineTo(w * 0.52, h * 0.64);
                ctx.closePath();
                ctx.stroke();
            } else if (k === "checklist") {
                var cr = w * 0.24;
                var cx = w * 0.26, cy = h * 0.42;
                ctx.beginPath();
                ctx.arc(cx, cy, cr, 0, Math.PI * 2);
                ctx.stroke();
                ctx.beginPath();
                ctx.moveTo(cx - cr * 0.45, cy);
                ctx.lineTo(cx - cr * 0.1, cy + cr * 0.45);
                ctx.lineTo(cx + cr * 0.55, cy - cr * 0.4);
                ctx.stroke();
                ctx.beginPath();
                ctx.moveTo(w * 0.56, h * 0.32); ctx.lineTo(w * 0.92, h * 0.32);
                ctx.moveTo(w * 0.56, h * 0.54); ctx.lineTo(w * 0.92, h * 0.54);
                ctx.moveTo(w * 0.24, h * 0.78); ctx.lineTo(w * 0.36, h * 0.78);
                ctx.moveTo(w * 0.56, h * 0.78); ctx.lineTo(w * 0.92, h * 0.78);
                ctx.stroke();
            } else if (k === "table") {
                ctx.strokeRect(2, 2.5, w - 4, h - 5);
                ctx.beginPath();
                ctx.moveTo(w * 0.5, 2.5); ctx.lineTo(w * 0.5, h - 2.5);
                ctx.moveTo(2, h * 0.5); ctx.lineTo(w - 2, h * 0.5);
                ctx.stroke();
            } else if (k === "attachment") {
                ctx.beginPath();
                ctx.moveTo(w * 0.72, h * 0.26);
                ctx.lineTo(w * 0.38, h * 0.62);
                ctx.arc(w * 0.32, h * 0.68, w * 0.14, -Math.PI * 0.25, Math.PI * 0.75, false);
                ctx.lineTo(w * 0.68, h * 0.32);
                ctx.arc(w * 0.74, h * 0.26, w * 0.11, -Math.PI * 0.25, Math.PI * 0.75, false);
                ctx.stroke();
            } else if (k === "markup") {
                ctx.beginPath();
                ctx.arc(w * 0.5, h * 0.5, w * 0.44, 0, Math.PI * 2);
                ctx.stroke();
                ctx.beginPath();
                ctx.moveTo(w * 0.5, h * 0.24);
                ctx.lineTo(w * 0.36, h * 0.56);
                ctx.lineTo(w * 0.44, h * 0.66);
                ctx.lineTo(w * 0.5, h * 0.76);
                ctx.lineTo(w * 0.56, h * 0.66);
                ctx.lineTo(w * 0.64, h * 0.56);
                ctx.closePath();
                ctx.stroke();
                ctx.beginPath();
                ctx.moveTo(w * 0.5, h * 0.24); ctx.lineTo(w * 0.5, h * 0.52);
                ctx.stroke();
            } else if (k === "lock" || k === "lock-small") {
                var lw = w * 0.68, lh = h * 0.48;
                var lx = (w - lw) / 2, ly = h * 0.44;
                ctx.strokeRect(lx, ly, lw, lh);
                ctx.beginPath();
                ctx.arc(w * 0.5, ly, lw * 0.32, Math.PI, 0, false);
                ctx.stroke();
                ctx.beginPath();
                ctx.arc(w * 0.5, ly + lh * 0.46, Math.max(1.2, w * 0.08), 0, Math.PI * 2);
                ctx.fill();
            } else if (k === "share") {
                ctx.beginPath();
                ctx.moveTo(w * 0.20, h * 0.44);
                ctx.lineTo(w * 0.20, h * 0.82);
                ctx.lineTo(w * 0.80, h * 0.82);
                ctx.lineTo(w * 0.80, h * 0.44);
                ctx.stroke();
                ctx.beginPath();
                ctx.moveTo(w * 0.5, h * 0.70);
                ctx.lineTo(w * 0.5, h * 0.18);
                ctx.moveTo(w * 0.30, h * 0.36);
                ctx.lineTo(w * 0.5, h * 0.16);
                ctx.lineTo(w * 0.70, h * 0.36);
                ctx.stroke();
            } else if (k === "search") {
                var sr = w * 0.28;
                var scx = w * 0.42, scy = h * 0.42;
                ctx.beginPath();
                ctx.arc(scx, scy, sr, 0, Math.PI * 2);
                ctx.stroke();
                ctx.beginPath();
                ctx.moveTo(scx + sr * 0.7, scy + sr * 0.7);
                ctx.lineTo(w * 0.85, h * 0.85);
                ctx.stroke();
            } else if (k === "trash") {
                var tx = w * 0.22, tw = w * 0.56;
                ctx.beginPath();
                ctx.moveTo(w * 0.16, h * 0.28);
                ctx.lineTo(w * 0.84, h * 0.28);
                ctx.moveTo(w * 0.38, h * 0.28);
                ctx.arc(w * 0.5, h * 0.28, w * 0.12, Math.PI, 0, false);
                ctx.stroke();
                ctx.beginPath();
                ctx.moveTo(tx + 1, h * 0.32);
                ctx.lineTo(tx + 2.5, h * 0.84);
                ctx.lineTo(tx + tw - 2.5, h * 0.84);
                ctx.lineTo(tx + tw - 1, h * 0.32);
                ctx.closePath();
                ctx.stroke();
                ctx.beginPath();
                ctx.moveTo(w * 0.42, h * 0.42); ctx.lineTo(w * 0.43, h * 0.74);
                ctx.moveTo(w * 0.58, h * 0.42); ctx.lineTo(w * 0.57, h * 0.74);
                ctx.stroke();
            } else if (k === "undo") {
                ctx.beginPath();
                ctx.arc(w * 0.55, h * 0.56, w * 0.30, Math.PI * 1.1, 0, false);
                ctx.stroke();
                ctx.beginPath();
                ctx.moveTo(w * 0.22, h * 0.30);
                ctx.lineTo(w * 0.22, h * 0.56);
                ctx.lineTo(w * 0.50, h * 0.56);
                ctx.stroke();
            } else if (k === "redo") {
                ctx.beginPath();
                ctx.arc(w * 0.45, h * 0.56, w * 0.30, Math.PI, -Math.PI * 0.1, false);
                ctx.stroke();
                ctx.beginPath();
                ctx.moveTo(w * 0.78, h * 0.30);
                ctx.lineTo(w * 0.78, h * 0.56);
                ctx.lineTo(w * 0.50, h * 0.56);
                ctx.stroke();
            } else if (k === "lasso") {
                ctx.setLineDash([2.5, 2]);
                ctx.strokeRect(w * 0.16, h * 0.16, w * 0.68, h * 0.68);
                ctx.setLineDash([]);
            } else if (k === "shapes") {
                ctx.strokeRect(w * 0.14, h * 0.14, w * 0.48, h * 0.48);
                ctx.beginPath();
                ctx.arc(w * 0.64, h * 0.64, w * 0.26, 0, Math.PI * 2);
                ctx.stroke();
            } else if (k === "stylus") {
                ctx.beginPath();
                ctx.moveTo(w * 0.20, h * 0.80);
                ctx.lineTo(w * 0.74, h * 0.22);
                ctx.lineTo(w * 0.80, h * 0.28);
                ctx.lineTo(w * 0.28, h * 0.84);
                ctx.lineTo(w * 0.18, h * 0.84);
                ctx.closePath();
                ctx.stroke();
            } else if (k === "check") {
                ctx.beginPath();
                ctx.moveTo(w * 0.18, h * 0.52);
                ctx.lineTo(w * 0.42, h * 0.78);
                ctx.lineTo(w * 0.84, h * 0.24);
                ctx.stroke();
            } else if (k === "chevron-down") {
                ctx.beginPath();
                ctx.moveTo(w * 0.22, h * 0.38);
                ctx.lineTo(w * 0.50, h * 0.64);
                ctx.lineTo(w * 0.78, h * 0.38);
                ctx.stroke();
            } else if (k === "close") {
                ctx.beginPath();
                ctx.moveTo(w * 0.22, h * 0.22); ctx.lineTo(w * 0.78, h * 0.78);
                ctx.moveTo(w * 0.78, h * 0.22); ctx.lineTo(w * 0.22, h * 0.78);
                ctx.stroke();
            } else if (k === "eraser") {
                ctx.beginPath();
                ctx.moveTo(w * 0.18, h * 0.62);
                ctx.lineTo(w * 0.50, h * 0.18);
                ctx.lineTo(w * 0.82, h * 0.50);
                ctx.lineTo(w * 0.50, h * 0.86);
                ctx.closePath();
                ctx.stroke();
                ctx.beginPath();
                ctx.moveTo(w * 0.34, h * 0.40); ctx.lineTo(w * 0.66, h * 0.66);
                ctx.stroke();
            } else if (k === "pen") {
                ctx.beginPath();
                ctx.moveTo(w * 0.50, h * 0.14);
                ctx.lineTo(w * 0.26, h * 0.62);
                ctx.lineTo(w * 0.38, h * 0.74);
                ctx.lineTo(w * 0.50, h * 0.86);
                ctx.lineTo(w * 0.62, h * 0.74);
                ctx.lineTo(w * 0.74, h * 0.62);
                ctx.closePath();
                ctx.stroke();
                ctx.beginPath();
                ctx.moveTo(w * 0.50, h * 0.14); ctx.lineTo(w * 0.50, h * 0.52);
                ctx.stroke();
            } else if (k === "restore") {
                ctx.beginPath();
                ctx.arc(w * 0.52, h * 0.54, w * 0.32, Math.PI * 1.2, 0, false);
                ctx.stroke();
                ctx.beginPath();
                ctx.moveTo(w * 0.20, h * 0.28); ctx.lineTo(w * 0.20, h * 0.58); ctx.lineTo(w * 0.48, h * 0.58);
                ctx.stroke();
            } else if (k === "sparkles" || k === "writing-tools") {
                var cx = w * 0.44, cy = h * 0.46, r = w * 0.34;
                ctx.beginPath();
                ctx.moveTo(cx, cy - r);
                ctx.quadraticCurveTo(cx, cy, cx + r, cy);
                ctx.quadraticCurveTo(cx, cy, cx, cy + r);
                ctx.quadraticCurveTo(cx, cy, cx - r, cy);
                ctx.quadraticCurveTo(cx, cy, cx, cy - r);
                ctx.fill();
                var sx = w * 0.78, sy = h * 0.22, sr = w * 0.16;
                ctx.beginPath();
                ctx.moveTo(sx, sy - sr);
                ctx.quadraticCurveTo(sx, sy, sx + sr, sy);
                ctx.quadraticCurveTo(sx, sy, sx, sy + sr);
                ctx.quadraticCurveTo(sx, sy, sx - sr, sy);
                ctx.quadraticCurveTo(sx, sy, sx, sy - sr);
                ctx.fill();
            } else if (k === "pin") {
                ctx.beginPath();
                ctx.moveTo(w * 0.35, h * 0.20);
                ctx.lineTo(w * 0.65, h * 0.20);
                ctx.moveTo(w * 0.40, h * 0.20);
                ctx.lineTo(w * 0.40, h * 0.50);
                ctx.lineTo(w * 0.25, h * 0.65);
                ctx.lineTo(w * 0.75, h * 0.65);
                ctx.lineTo(w * 0.60, h * 0.50);
                ctx.lineTo(w * 0.60, h * 0.20);
                ctx.moveTo(w * 0.50, h * 0.65);
                ctx.lineTo(w * 0.50, h * 0.88);
                ctx.stroke();
            } else if (k === "math") {
                ctx.beginPath();
                ctx.moveTo(w * 0.20, h * 0.35); ctx.lineTo(w * 0.48, h * 0.35);
                ctx.moveTo(w * 0.34, h * 0.20); ctx.lineTo(w * 0.34, h * 0.50);
                ctx.moveTo(w * 0.20, h * 0.70); ctx.lineTo(w * 0.48, h * 0.70);
                ctx.moveTo(w * 0.60, h * 0.40); ctx.lineTo(w * 0.84, h * 0.40);
                ctx.moveTo(w * 0.60, h * 0.60); ctx.lineTo(w * 0.84, h * 0.60);
                ctx.stroke();
            }
        }
    }
    function pad(n) { return (n < 10 ? "0" : "") + n; }
    function fmtStamp(d) {
        return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate())
            + "-" + pad(d.getHours()) + pad(d.getMinutes());
    }
    function startOfToday() {
        var now = new Date();
        return new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
    }
    function fmtWhen(ts) {
        if (!ts) return "";
        var d = new Date(ts * 1000), now = new Date();
        var h = d.getHours();
        var m = pad(d.getMinutes());
        var ampm = h >= 12 ? "PM" : "AM";
        h = h % 12;
        if (h === 0) h = 12;
        var hm = h + ":" + m + " " + ampm;
        var sameDay = d.getFullYear() === now.getFullYear() && d.getMonth() === now.getMonth() && d.getDate() === now.getDate();
        if (sameDay) return hm;
        var yy = String(d.getFullYear()).slice(-2);
        return pad(d.getDate()) + "/" + pad(d.getMonth() + 1) + "/" + yy;
    }
    function fmtLong(ts) {
        if (!ts) return "";
        var d = new Date(ts * 1000);
        var months = ["January", "February", "March", "April", "May", "June",
                      "July", "August", "September", "October", "November", "December"];
        var h = d.getHours();
        var m = pad(d.getMinutes());
        var ampm = h >= 12 ? "PM" : "AM";
        h = h % 12;
        if (h === 0) h = 12;
        return d.getDate() + " " + months[d.getMonth()] + " " + d.getFullYear()
            + " at " + h + ":" + m + " " + ampm;
    }
    // macOS Golden Gate Notes groups: Pinned, Today, Yesterday, Previous 7/30 Days, Month, Year.
    function groupOf(n) {
        if (n.pinned) return "Pinned";
        if (sortBy === "title") return (n.title || "Untitled").charAt(0).toUpperCase();
        var ts = (sortBy === "created" ? n.created : n.updated);
        var t = ts * 1000, day = 86400000, start = startOfToday();
        if (t >= start) return "Today";
        if (t >= start - day) return "Yesterday";
        if (t >= start - 7 * day) return "Previous 7 Days";
        if (t >= start - 30 * day) return "Previous 30 Days";
        var months = ["January", "February", "March", "April", "May", "June",
                      "July", "August", "September", "October", "November", "December"];
        var d = new Date(t);
        var now = new Date();
        if (d.getFullYear() === now.getFullYear()) {
            return months[d.getMonth()];
        }
        return "" + d.getFullYear();
    }
    function safeName(title) {
        var name = String(title || "").replace(/[^\w .-]/g, "").trim().replace(/ +/g, "-");
        return (name || "note").slice(0, 60);
    }

    function open() { if (win.visible) { win.raise(); win.requestActivate(); return; } win.visible = true; win.raise(); win.requestActivate(); refreshFolders(); refreshList(); }
    function close() { flushSave(); win.visible = false; }

    // ═════════════ BRIDGE (bin/notes.py, one-shot JSON) ═════════════
    function runNotes(proc, args) {
        proc.command = ["python3", "-B", root.notesPy, "--db", root.dbPath].concat(args);
        proc.running = true;
    }
    function parseJson(text, fallback) {
        try { return JSON.parse(text || ""); } catch (e) { return fallback; }
    }
    function refreshList() { runNotes(listProc, ["list", "--folder", folderFilter, "--query", query, "--sort", sortBy, "--order", sortOrder]); }
    function refreshFolders() { runNotes(foldersProc, ["folders"]); }

    Process {
        id: listProc
        stdout: StdioCollector {
            onStreamFinished: {
                var r = root.parseJson(text, null);
                if (r && r.notes) {
                    root.notes = r.notes.slice().sort(function (a, b) {
                        if (a.pinned !== b.pinned) return b.pinned ? 1 : -1;
                        if (root.sortBy === "title") {
                            var cmp = (a.title || "").localeCompare(b.title || "");
                            return root.sortOrder === "asc" ? cmp : -cmp;
                        }
                        var prop = root.sortBy === "created" ? "created" : "updated";
                        return root.sortOrder === "asc" ? (a[prop] - b[prop]) : (b[prop] - a[prop]);
                    });
                    for (var i = 0; i < root.notes.length; i++) root.notes[i].group = root.groupOf(root.notes[i]);
                    root.listReady = true;
                    if (root.afterDelete) { root.afterDelete = false; root.selectAfterDelete(); }
                }
            }
        }
    }
    Process {
        id: foldersProc
        stdout: StdioCollector {
            onStreamFinished: {
                var r = root.parseJson(text, null);
                if (r && r.folders) {
                    root.folders = r.folders;
                    root.allCount = r.all || 0;
                    root.trashCount = r.trash || 0;
                    if (r.smart) root.smartCounts = r.smart;
                }
            }
        }
    }
    Process {
        id: getProc
        stdout: StdioCollector {
            onStreamFinished: {
                var r = root.parseJson(text, null);
                if (!r || !r.note) return;
                root.loading = true;
                root.current = r.note;
                root.currentUnlocked = !r.note.locked;
                root.strokes = r.note.strokes || [];
                root.redoStrokes = [];
                root.drawingHistory = []; root.drawingRedo = [];
                titleEdit.text = r.note.title || "";
                bodyEdit.text = r.note.body || "";
                root.dirty = false;
                root.loading = false;
                drawingCanvas.requestPaint();
                if (root.view === "text") bodyEdit.forceActiveFocus();
            }
        }
    }
    Process {
        id: lockProc
        stdout: StdioCollector {
            onStreamFinished: {
                var r = root.parseJson(text, null);
                if (r && r.ok && root.current && root.current.id === r.id) {
                    root.current.locked = !!r.locked;
                    root.currentUnlocked = true;
                }
                root.refreshList();
                root.refreshFolders();
            }
        }
    }
    Process {
        id: writingProc
        stdout: StdioCollector {
            onStreamFinished: {
                var r = root.parseJson(text, null);
                if (r && r.ok && r.result !== undefined) {
                    bodyEdit.text = r.result;
                    root.markDirty();
                    Quickshell.execDetached(["notify-send", "-a", "macshell", "Writing Tools", "Applied: " + (r.action || "transform")]);
                } else if (r && r.error) {
                    Quickshell.execDetached(["notify-send", "-a", "macshell", "Writing Tools", "Error: " + r.error]);
                }
            }
        }
    }
    Process {
        id: newProc
        stdout: StdioCollector {
            onStreamFinished: {
                var r = root.parseJson(text, null);
                root.refreshList();
                root.refreshFolders();
                if (r && r.note) {
                    root.loading = true;
                    root.current = r.note; root.strokes = []; root.redoStrokes = [];
                root.drawingHistory = []; root.drawingRedo = [];
                    titleEdit.text = ""; bodyEdit.text = "";
                    root.dirty = false; root.loading = false;
                    root.view = "text"; titleEdit.forceActiveFocus();
                }
            }
        }
    }
    Process {
        id: saveProc
        stdout: StdioCollector {
            onStreamFinished: {
                var r = root.parseJson(text, null);
                if (r && r.ok) { root.dirty = false; root.refreshList(); }
            }
        }
    }
    Process {
        id: deleteProc
        stdout: StdioCollector {
            onStreamFinished: {
                // re-select only after the refreshed list arrives, so the selection
                // never points at the deleted note (stale-list race).
                root.afterDelete = true;
                root.refreshList();
                root.refreshFolders();
            }
        }
    }
    // generic op runner: pin / move / duplicate / restore / purge / empty-trash /
    // new-folder / delete-folder — the result just triggers a refresh.
    Process {
        id: opProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.refreshList();
                root.refreshFolders();
            }
        }
    }
    Process {
        id: exportProc
        stdout: StdioCollector {
            onStreamFinished: {
                var r = root.parseJson(text, null);
                if (r && r.ok) Quickshell.execDetached(["notify-send", "-a", "macshell", "Notes",
                                                        "Exported to " + r.path]);
                else Quickshell.execDetached(["notify-send", "-a", "macshell", "Notes",
                                              "Export failed: " + ((r && r.error) || "unknown error")]);
            }
        }
    }

    // ── selection & editing ──
    function select(id) {
        if (current && current.id === id) return;
        flushSave();
        runNotes(getProc, ["get", "--id", id]);
        confirmDelete = "";
    }
    function selectAfterDelete() {
        // the removed note is gone from the list; fall back to the newest remaining note
        var id = current ? current.id : "";
        var keep = null;
        for (var i = 0; i < notes.length; i++) if (notes[i].id === id) keep = notes[i];
        if (keep) { runNotes(getProc, ["get", "--id", keep.id]); }
        else if (notes.length > 0) { select(notes[0].id); }
        else { current = null; strokes = []; redoStrokes = []; drawingHistory = []; drawingRedo = []; dirty = false; }
        confirmDelete = "";
    }
    function snapshot() {
        if (!current) return null;
        return { id: current.id, title: titleEdit.text, body: bodyEdit.text, strokes: strokes };
    }
    function saveNow() {
        var s = snapshot();
        if (!s) return;
        runNotes(saveProc, ["save", "--json", JSON.stringify(s)]);
        dirty = false;
    }
    function flushSave() { if (dirty) saveNow(); }
    Timer { id: saveTimer; interval: 800; onTriggered: root.saveNow() }
    function markDirty() { dirty = true; saveTimer.restart(); }
    property bool evaluatingMath: false
    function newNote() {
        flushSave();
        var folder = (!trashView && folderFilter !== "All" && folderFilter.indexOf("@smart:") !== 0) ? folderFilter : "Notes";
        runNotes(newProc, ["new", "--folder", folder]);
    }
    function requestDelete() {
        if (!current || current.deleted) return;
        if (confirmDelete === current.id) {
            dirty = false;                       // a pending autosave must not resurrect the deleted note
            runNotes(deleteProc, ["delete", "--id", current.id]);
        } else {
            confirmDelete = current.id;
            deleteConfirmTimer.restart();
        }
    }
    Timer { id: deleteConfirmTimer; interval: 3000; onTriggered: root.confirmDelete = "" }
    function restoreCurrent() {
        if (!current || !current.deleted) return;
        runNotes(opProc, ["restore", "--id", current.id]);
    }
    function purgeCurrent() {
        if (!current || !current.deleted) return;
        if (confirmDelete === current.id) {
            dirty = false;
            runNotes(opProc, ["purge", "--id", current.id]);
        } else {
            confirmDelete = current.id;
            deleteConfirmTimer.restart();
        }
    }
    function emptyTrash() {
        if (trashCount === 0) return;
        runNotes(opProc, ["empty-trash"]);
        current = null; strokes = []; dirty = false;
    }
    function pinToggle() {
        if (!current || current.deleted) return;
        runNotes(opProc, ["pin", "--id", current.id, "--on", current.pinned ? "0" : "1"]);
    }
    function toggleLockCurrent() {
        if (!current || current.deleted) return;
        var nextLock = current.locked ? 0 : 1;
        runNotes(lockProc, ["lock", "--id", current.id, "--on", String(nextLock)]);
    }
    function applyWritingTool(action) {
        if (!current || current.deleted || !bodyEdit.text) return;
        writingToolsMenu.open = false;
        runNotes(writingProc, ["writing-tools", "--action", action, "--text", bodyEdit.text]);
    }
    function insertTable() {
        if (!current || current.deleted) return;
        var text = bodyEdit.text;
        var pos = bodyEdit.cursorPosition;
        var tableStr = "\n| Column 1 | Column 2 | Column 3 |\n| :--- | :--- | :--- |\n| Item 1 | Detail | Status |\n| Item 2 | Detail | Status |\n";
        bodyEdit.text = text.slice(0, pos) + tableStr + text.slice(pos);
        bodyEdit.cursorPosition = pos + tableStr.length;
        markDirty();
    }
    function insertAttachment(kind) {
        if (!current || current.deleted) return;
        attachmentMenu.open = false;
        var text = bodyEdit.text;
        var pos = bodyEdit.cursorPosition;
        var snippet = "";
        if (kind === "link") snippet = " [Link Title](https://apple.com) ";
        else if (kind === "photo") snippet = "\n![Photo Description](file:///home/icentry/Pictures/photo.jpg)\n";
        else if (kind === "file") snippet = "\n[Document.pdf](file:///home/icentry/Documents/Document.pdf)\n";
        bodyEdit.text = text.slice(0, pos) + snippet + text.slice(pos);
        bodyEdit.cursorPosition = pos + snippet.length;
        markDirty();
    }
    function evaluateMathExpr(expr) {
        var clean = String(expr || "").trim();
        if (!clean) return null;
        clean = clean.replace(/×/g, "*").replace(/÷/g, "/").replace(/\^/g, "**");
        if (!/^[0-9\.\s\+\-\*\/\%\(\)]+$/.test(clean)) return null;
        if (!/[\+\-\*\/\%]/.test(clean)) return null;
        try {
            var fn = new Function("return (" + clean + ");");
            var val = fn();
            if (typeof val === "number" && isFinite(val) && !isNaN(val)) {
                if (Math.floor(val) === val) return String(val);
                return String(parseFloat(val.toFixed(4)));
            }
        } catch (e) {
            return null;
        }
        return null;
    }
    function checkMathNote() {
        if (root.loading || evaluatingMath || !root.current || root.current.deleted) return;
        var text = bodyEdit.text;
        var pos = bodyEdit.cursorPosition;
        if (pos <= 0) return;
        var beforeCursor = text.slice(0, pos);
        var lineStart = beforeCursor.lastIndexOf("\n") + 1;
        var line = beforeCursor.slice(lineStart);
        var m = line.match(/([0-9\.\+\-\*\/\%\(\)\^][0-9\.\s\+\-\*\/\%\(\)\^]*)=\s*$/);
        if (m) {
            var expr = m[1].trim();
            var ans = evaluateMathExpr(expr);
            if (ans !== null) {
                evaluatingMath = true;
                var matchIndex = line.lastIndexOf(m[0]);
                var prefix = line.slice(0, matchIndex);
                var fullPrefix = text.slice(0, lineStart) + prefix;
                var afterCursor = text.slice(pos);
                var insertStr = expr + " = " + ans + " ";
                bodyEdit.text = fullPrefix + insertStr + afterCursor;
                bodyEdit.cursorPosition = fullPrefix.length + insertStr.length;
                evaluatingMath = false;
                root.markDirty();
            }
        }
    }
    function duplicateCurrent() {
        if (!current || current.deleted) return;
        flushSave();
        runNotes(opProc, ["duplicate", "--id", current.id]);
    }
    function moveTo(folder) {
        if (!current || current.deleted) return;
        runNotes(opProc, ["move", "--id", current.id, "--folder", folder]);
    }
    function createFolder(name) {
        name = String(name || "").trim();
        if (name === "") return;
        runNotes(opProc, ["new-folder", "--name", name]);
        addingFolder = false;
    }
    function deleteFolder(name) {
        if (!name || name === "Notes") return;
        runNotes(opProc, ["delete-folder", "--name", name]);
        if (folderFilter === name) folderFilter = "All";
    }
    function selectFolder(name) {
        if (folderFilter === name) return;
        flushSave();
        folderFilter = name;
        refreshList();
    }
    function smartFolderName(filter) {
        if (filter === "@smart:pinned") return "Pinned Notes";
        if (filter === "@smart:locked") return "Locked Notes";
        if (filter === "@smart:checklists") return "Checklists";
        if (filter === "@smart:drawings") return "Drawings";
        if (filter === "@smart:math") return "Math Notes";
        return filter;
    }
    function folderCount(name) {
        if (name === "All") return allCount;
        if (name === "Trash") return trashCount;
        if (name === "@smart:pinned") return smartCounts ? (smartCounts.pinned || 0) : 0;
        if (name === "@smart:locked") return smartCounts ? (smartCounts.locked || 0) : 0;
        if (name === "@smart:checklists") return smartCounts ? (smartCounts.checklists || 0) : 0;
        if (name === "@smart:drawings") return smartCounts ? (smartCounts.drawings || 0) : 0;
        if (name === "@smart:math") return smartCounts ? (smartCounts.math || 0) : 0;
        for (var i = 0; i < folders.length; i++) if (folders[i].name === name) return folders[i].count;
        return 0;
    }

    // ── formatting (prefix-based: #, ##, ###, -, –, 1., >, ☐/☑) ──
    function stripPrefix(line) {
        var m = /^(\s*)(#{1,3} |- |– |> |☐ |☑ |\d+\. )/.exec(line);
        return m ? line.slice(m[0].length) : line;
    }
    function lineBounds() {
        var text = bodyEdit.text, pos = bodyEdit.cursorPosition;
        var start = text.lastIndexOf("\n", pos - 1) + 1;
        var end = text.indexOf("\n", pos);
        if (end === -1) end = text.length;
        return { start: start, end: end };
    }
    function replaceLine(bounds, newLine) {
        var text = bodyEdit.text;
        bodyEdit.text = text.slice(0, bounds.start) + newLine + text.slice(bounds.end);
        bodyEdit.cursorPosition = bounds.start + Math.min(newLine.length, bounds.end - bounds.start);
        markDirty();
    }
    function applyFormat(styleId) {
        if (!current || current.deleted) return;
        var b = lineBounds();
        var line = bodyEdit.text.slice(b.start, b.end);
        var indent = (/^\s*/.exec(line) || [""])[0];
        var rest = stripPrefix(line).slice(indent.length);
        var prefix = { "title": "# ", "heading": "## ", "subheading": "### ", "body": "",
                       "bulleted": "- ", "dashed": "– ", "numbered": "1. ", "quote": "> " }[styleId];
        if (prefix === undefined) return;
        replaceLine(b, indent + prefix + rest);
        styleMenu.open = false;
    }
    function insertDivider() {
        if (!current || current.deleted) return;
        var b = lineBounds();
        var text = bodyEdit.text;
        bodyEdit.text = text.slice(0, b.end) + "\n———\n" + text.slice(b.end);
        bodyEdit.cursorPosition = b.end + 5;
        markDirty();
        styleMenu.open = false;
    }
    function toggleChecklist() {
        if (!current || current.deleted) return;
        var b = lineBounds();
        var line = bodyEdit.text.slice(b.start, b.end);
        var indent = (/^\s*/.exec(line) || [""])[0];
        var rest = stripPrefix(line).slice(indent.length);
        var marked;
        if (/^\s*☐ /.test(line)) marked = indent + "☑ " + rest;       // unchecked → checked
        else if (/^\s*☑ /.test(line)) marked = indent + rest;          // checked → plain
        else marked = indent + "☐ " + rest;                            // plain → unchecked
        replaceLine(b, marked);
    }

    // ── drawing ──
    function startStroke(nx, ny) {
        drawing = true;
        pendingStroke = { tool: tool, brush: brushName, color: palette[penIndex],
                          width: penWidth / Math.max(1, drawingCanvas.width),
                          points: [nx, ny, nx, ny] };
        if (tool === "pen" || tool === "eraser") pendingStroke.points = [nx, ny];
        drawingCanvas.requestPaint();
    }
    function moveStroke(nx, ny) {
        if (!drawing || !pendingStroke) return;
        if (tool === "pen" || tool === "eraser") { pendingStroke.points.push(nx, ny); }
        else { pendingStroke.points[2] = nx; pendingStroke.points[3] = ny; }
        drawingCanvas.requestPaint();
    }
    function endStroke() {
        if (!drawing || !pendingStroke) { drawing = false; return; }
        drawing = false;
        var s = pendingStroke;
        pendingStroke = null;
        if (s.tool === "eraser") {
            var before = strokes.slice();
            var kept = strokes.filter(function (old) { return !root.eraserTouches(old, s.points); });
            if (kept.length !== strokes.length) {
                drawingHistory.push({ kind: "erase", before: before, after: kept.slice() });
                drawingRedo = []; redoStrokes = []; strokes = kept; markDirty();
            }
            drawingCanvas.requestPaint(); return;
        }
        var enough = s.tool === "pen" ? s.points.length >= 4 : Math.abs(s.points[0] - s.points[2]) + Math.abs(s.points[1] - s.points[3]) > 0.004;
        if (!enough) { drawingCanvas.requestPaint(); return; }
        if (s.tool === "pen") s.points = s.points.concat([s.points[s.points.length - 2], s.points[s.points.length - 1]]);
        strokes.push(s);
        drawingHistory.push({kind: "add", stroke: s});
        drawingRedo = []; redoStrokes = [];
        markDirty();
        drawingCanvas.requestPaint();
    }
    // Whole-stroke eraser: does not add unsupported shape types to notes.py.
    function eraserTouches(stroke, path) {
        var pts = stroke.points || [];
        if (pts.length < 2) return false;
        var threshold = Math.max(0.012, (penWidth * 2 + 8) / Math.max(1, drawingCanvas.width));
        var aspect = drawingCanvas.width / Math.max(1, drawingCanvas.height);
        function distanceToSegment(px,py,x1,y1,x2,y2) {
            var dx=x2-x1, dy=(y2-y1)/aspect, px0=px-x1, py0=(py-y1)/aspect;
            var t=Math.max(0,Math.min(1,(px0*dx+py0*dy)/Math.max(dx*dx+dy*dy,1e-8)));
            return Math.hypot(px0-dx*t, py0-dy*t);
        }
        for (var i=0; i<path.length; i+=2) {
            for (var j=0; j<pts.length-2; j+=2) {
                if (distanceToSegment(path[i],path[i+1],pts[j],pts[j+1],pts[j+2],pts[j+3]) < threshold)
                    return true;
            }
            if (stroke.tool !== "pen" && stroke.tool !== "eraser" && pts.length >= 4) {
                if (distanceToSegment(path[i],path[i+1],pts[0],pts[1],pts[2],pts[3]) < threshold) return true;
            }
        }
        return false;
    }
    function selectBrush(name) {
        brushName = name;
        tool = name === "Eraser" ? "eraser" : "pen";
        brushMenuOpen = false;
    }
    function undoDrawing() {
        var op;
        if (drawingHistory.length > 0) {
            op = drawingHistory.pop();
            if (op.kind === "add" || op.kind === "legacyAdd") {
                var idx = strokes.lastIndexOf(op.stroke);
                if (idx >= 0) strokes.splice(idx, 1);
            } else strokes = op.before.slice();
        } else if (strokes.length > 0) {
            // Notes loaded from SQLite still support original undo semantics.
            op = { kind: "legacyAdd", stroke: strokes.pop() };
        } else return;
        drawingRedo.push(op);
        markDirty(); drawingCanvas.requestPaint();
    }
    function redoDrawing() {
        if (drawingRedo.length === 0) return;
        var op = drawingRedo.pop();
        if (op.kind === "add" || op.kind === "legacyAdd") strokes.push(op.stroke);
        else strokes = op.after.slice();
        drawingHistory.push(op);
        markDirty(); drawingCanvas.requestPaint();
    }
    function clearDrawing() {
        if (strokes.length === 0) return;
        var previous = strokes.slice();
        drawingHistory.push({ kind: "clear", before: previous, after: [] });
        drawingRedo = []; redoStrokes = [];
        strokes = [];
        markDirty(); drawingCanvas.requestPaint();
    }
    function undo() { if (view === "drawing") undoDrawing(); else if (bodyEdit.canUndo) { bodyEdit.undo(); markDirty(); } }
    function redo() { if (view === "drawing") redoDrawing(); else if (bodyEdit.canRedo) { bodyEdit.redo(); markDirty(); } }

    function exportNote(format) {
        if (!current) return;
        flushSave();
        var stem = safeName(titleEdit.text || "note") + "-" + fmtStamp(new Date());
        runNotes(exportProc, ["export", "--id", current.id, "--out", exportDir + "/" + stem, "--format", format]);
        exportMenu.open = false;
    }


    // ═══════════ WINDOW / TAHOE NOTES REDESIGN ═══════════
    Window {
        id: win
        title: "Notes"
        width: 1050; height: 668
        minimumWidth: 860; minimumHeight: 480
        visible: false
        color: "transparent"
        flags: Qt.Window | Qt.FramelessWindowHint
        readonly property bool squareCorners: !!(root.hub && root.hub.desktopController.hasSquareCorners(title))
        readonly property int toolbarHeight: 52
        readonly property int sidebarWidth: 184
        readonly property int currentSidebarWidth: root.sidebarCollapsed ? 0 : sidebarWidth
        readonly property int listWidth: 198

        QtObject {
            id: pal
            readonly property bool dark: root.darkMode
            readonly property color bg: dark ? "#1E1E20" : "#FFFFFF"
            readonly property color bar: dark ? "#262628" : "#F6F6F8"
            readonly property color side: dark ? "#212123" : "#EFEFF1"
            readonly property color list: dark ? "#262628" : "#FFFFFF"
            readonly property color paper: dark ? "#1E1E20" : "#FFFFFF"
            readonly property color text: dark ? "#F5F5F7" : "#1D1D1F"
            readonly property color text2: dark ? "#A1A1A6" : "#787880"
            readonly property color text3: dark ? "#8E8E93" : "#8E8E93"
            readonly property color sep: dark ? "#38383C" : "#E5E5EA"
            readonly property color ctrl: dark ? "#1FFFFFFF" : "#0A000000"
            readonly property color ctrlHover: dark ? "#2FFFFFFF" : "#14000000"
            readonly property color border: dark ? "#40FFFFFF" : "#24000000"
            readonly property color selection: dark ? "#363639" : "#DCDCDC"
            readonly property color noteHighlight: dark ? "#3A3A3D" : "#DFDFDC"
            readonly property color field: dark ? "#303034" : "#E8E8EC"
        }

        Corners.ContinuousRectangle {
            id: frame
            anchors.fill: parent
            radius: win.squareCorners ? 0 : 13
            normalizeRadius: false
            color: pal.bg
            border.width: 1
            border.color: pal.border
            clip: true

            // Base scene is the ONLY source sampled by every Liquid Glass effect.
            // No shader item is a descendant of this item, so there is no
            // circular ShaderEffectSource dependency or continuous feedback loop.
            Item {
                id: baseScene
                anchors.fill: parent

                Corners.ContinuousRectangle {
                    anchors.fill: parent
                    radius: win.squareCorners ? 0 : 13
                    color: pal.bg
                }
                Rectangle {
                    id: toolbarBackground
                    width: parent.width; height: win.toolbarHeight
                    color: pal.bar
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: pal.sep }
                    TapHandler { acceptedButtons: Qt.LeftButton; onDoubleTapped: if (root.hub) root.hub.desktopController.titlebar() }
                    DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
                    Text {
                        x: win.currentSidebarWidth + 14; y: 8
                        text: root.trashView ? "Recently Deleted" : (root.folderFilter === "All" ? "All iCloud" : (root.folderFilter.indexOf("@smart:") === 0 ? root.smartFolderName(root.folderFilter) : root.folderFilter))
                        color: pal.text; font.family: root.fam; font.pixelSize: 13; font.weight: Font.Bold
                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    }
                    Text {
                        x: win.currentSidebarWidth + 14; y: 27
                        text: root.notes.length === 1 ? "1 note" : root.notes.length + " notes"
                        color: pal.text3; font.family: root.fam; font.pixelSize: 10
                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    }
                    WindowControls {
                        x: 15; anchors.verticalCenter: parent.verticalCenter
                        dark: pal.dark
                        windowActive: win.active
                        minimizeEnabled: true
                        onMinimizeClicked: if (root.dock && root.dock.minimize) root.dock.minimize.minimizeFocused()
                        restored: win.visibility === Window.FullScreen || win.visibility === Window.Maximized
                        onCloseClicked: root.close()
                        onZoomClicked: {
                            if (win.visibility === Window.FullScreen || win.visibility === Window.Maximized) win.showNormal();
                            else if (root.dock && root.dock.reservesSpaceOn(win.screen ? win.screen.name : "")) win.showMaximized();
                            else win.showFullScreen();
                        }
                    }
                }

                // Sidebar — native macOS Notes spacing, rows, and yellow folder icons.
                Rectangle {
                    id: folderSidebar
                    x: 0; y: win.toolbarHeight
                    width: win.currentSidebarWidth; height: parent.height - y
                    color: pal.side
                    visible: width > 0
                    clip: true
                    Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: pal.sep }
                    Text {
                        x: 14; y: 10
                        text: "iCloud"
                        color: pal.text3
                        font.family: root.fam; font.pixelSize: 11; font.weight: Font.DemiBold
                    }
                    Column {
                        id: folderRows
                        x: 8; y: 29; width: Math.max(1, parent.width - 16)
                        spacing: 2
                        Item {
                            width: folderRows.width; height: 29
                            readonly property bool selected: root.folderFilter === "All"
                            Corners.ContinuousRectangle {
                                anchors.fill: parent; radius: 7; normalizeRadius: false
                                color: parent.selected ? pal.selection : (allMa.containsMouse ? pal.ctrl : "transparent")
                            }
                            FolderGlyph {
                                x: 9; size: 16
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                x: 34; anchors.verticalCenter: parent.verticalCenter
                                text: "All iCloud"; color: pal.text
                                font.family: root.fam; font.pixelSize: 12
                                font.weight: parent.selected ? Font.DemiBold : Font.Normal
                            }
                            Text {
                                anchors.right: parent.right; anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.allCount; color: pal.text3
                                font.family: root.fam; font.pixelSize: 12
                            }
                            MouseArea { id: allMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.selectFolder("All") }
                        }
                        Repeater {
                            model: root.folders
                            delegate: Item {
                                id: folderRow
                                required property var modelData
                                width: folderRows.width; height: 29
                                readonly property bool selected: root.folderFilter === modelData.name
                                Corners.ContinuousRectangle {
                                    anchors.fill: parent; radius: 7; normalizeRadius: false
                                    color: folderRow.selected ? pal.selection : (foldMa.containsMouse ? pal.ctrl : "transparent")
                                }
                                FolderGlyph {
                                    x: 9; size: 16
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    x: 34; width: parent.width - 72
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: folderRow.modelData.name; elide: Text.ElideRight
                                    color: pal.text; font.family: root.fam; font.pixelSize: 12
                                    font.weight: folderRow.selected ? Font.DemiBold : Font.Normal
                                }
                                Text {
                                    anchors.right: parent.right; anchors.rightMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: folderRow.modelData.count; color: pal.text3
                                    font.family: root.fam; font.pixelSize: 12
                                }
                                MouseArea {
                                    id: foldMa
                                    anchors.fill: parent; hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: function (mouse) {
                                        if (mouse.button === Qt.RightButton && folderRow.modelData.name !== "Notes")
                                            root.deleteFolder(folderRow.modelData.name);
                                        else root.selectFolder(folderRow.modelData.name);
                                    }
                                }
                            }
                        }
                        Item {
                            width: folderRows.width
                            height: root.addingFolder ? 33 : 0
                            visible: root.addingFolder
                            TextField {
                                id: newFolderEdit
                                x: 7; y: 3; width: parent.width - 14; height: 26
                                placeholderText: "Folder name"
                                color: pal.text; placeholderTextColor: pal.text3
                                font.family: root.fam; font.pixelSize: 12
                                background: Corners.ContinuousRectangle { radius: 7; normalizeRadius: false; color: pal.field }
                                onAccepted: root.createFolder(text)
                                Keys.onEscapePressed: root.addingFolder = false
                            }
                        }
                        Item { width: folderRows.width; height: 10 }
                        Text {
                            x: 6; text: "Smart Folders"
                            color: pal.text3
                            font.family: root.fam; font.pixelSize: 11; font.weight: Font.DemiBold
                        }
                        Repeater {
                            model: [
                                { id: "@smart:pinned", name: "Pinned Notes", icon: "pin", color: "#D9991C" },
                                { id: "@smart:locked", name: "Locked Notes", icon: "lock", color: "#FF9F0A" },
                                { id: "@smart:checklists", name: "Checklists", icon: "checklist", color: "#30D158" },
                                { id: "@smart:drawings", name: "Drawings", icon: "markup", color: "#0A84FF" },
                                { id: "@smart:math", name: "Math Notes", icon: "math", color: "#BF5AF2" }
                            ]
                            delegate: Item {
                                id: smartRow
                                required property var modelData
                                width: folderRows.width; height: 29
                                readonly property bool selected: root.folderFilter === modelData.id
                                Corners.ContinuousRectangle {
                                    anchors.fill: parent; radius: 7; normalizeRadius: false
                                    color: smartRow.selected ? pal.selection : (smartMa.containsMouse ? pal.ctrl : "transparent")
                                }
                                NoteIcon {
                                    x: 10; anchors.verticalCenter: parent.verticalCenter
                                    kind: smartRow.modelData.icon; color: smartRow.modelData.color; size: 15
                                }
                                Text {
                                    x: 34; width: parent.width - 72; anchors.verticalCenter: parent.verticalCenter
                                    text: smartRow.modelData.name; elide: Text.ElideRight
                                    color: pal.text; font.family: root.fam; font.pixelSize: 12
                                    font.weight: smartRow.selected ? Font.DemiBold : Font.Normal
                                }
                                Text {
                                    anchors.right: parent.right; anchors.rightMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.folderCount(smartRow.modelData.id)
                                    color: pal.text3; font.family: root.fam; font.pixelSize: 12
                                }
                                MouseArea {
                                    id: smartMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: root.selectFolder(smartRow.modelData.id)
                                }
                            }
                        }
                        Item { width: folderRows.width; height: 8 }
                        Item {
                            width: folderRows.width; height: 29
                            readonly property bool selected: root.trashView
                            Corners.ContinuousRectangle {
                                anchors.fill: parent; radius: 7; normalizeRadius: false
                                color: parent.selected ? pal.selection : (trashMa.containsMouse ? pal.ctrl : "transparent")
                            }
                            NoteIcon {
                                x: 10
                                anchors.verticalCenter: parent.verticalCenter
                                kind: "trash"
                                color: "#D0A133"
                                size: 15
                            }
                            Text {
                                x: 34; anchors.verticalCenter: parent.verticalCenter
                                text: "Recently Deleted"; color: pal.text
                                font.family: root.fam; font.pixelSize: 12
                                font.weight: parent.selected ? Font.DemiBold : Font.Normal
                            }
                            Text {
                                anchors.right: parent.right; anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.trashCount; color: pal.text3
                                font.family: root.fam; font.pixelSize: 12
                            }
                            MouseArea { id: trashMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.selectFolder("Trash") }
                        }
                        Item { width: folderRows.width; height: 14 }
                        Text {
                            x: 6; text: "Google"
                            color: pal.text3
                            font.family: root.fam; font.pixelSize: 11; font.weight: Font.DemiBold
                        }
                        Item {
                            width: folderRows.width; height: 26
                            Text {
                                x: 6; anchors.verticalCenter: parent.verticalCenter
                                text: "ujjwalkumarcgt@gmail.com"
                                color: pal.text2
                                font.family: root.fam; font.pixelSize: 11
                                elide: Text.ElideRight
                                width: parent.width - 12
                            }
                        }
                    }
                }

                // Notes column with grouped date headers; matches the screenshot.
                Rectangle {
                    id: listColumn
                    x: win.currentSidebarWidth; y: win.toolbarHeight
                    width: win.listWidth; height: parent.height - y
                    color: pal.list
                    Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: pal.sep }
                    Text {
                        visible: root.trashView && root.trashCount > 0
                        anchors.right: parent.right; anchors.rightMargin: 12; y: 6
                        text: "Empty"; color: "#F25048"; font.pixelSize: 11
                        MouseArea { anchors.fill: parent; anchors.margins: -5; onClicked: root.emptyTrash() }
                    }
                    ListView {
                        id: notesList
                        x: 6; y: 4; width: parent.width - 12
                        height: parent.height - y - 8
                        model: root.notes
                        spacing: 1
                        clip: true
                        ScrollBar.vertical: ScrollBar { width: 5; policy: ScrollBar.AsNeeded }
                        section.property: "group"
                        section.criteria: ViewSection.FullString
                        section.delegate: Item {
                            id: sectionHead
                            required property string section
                            width: notesList.width; height: 32
                            Text {
                                x: 10; anchors.bottom: parent.bottom; anchors.bottomMargin: 4
                                text: sectionHead.section
                                color: pal.text; font.family: root.fam
                                font.pixelSize: 13; font.weight: Font.Bold
                            }
                        }
                        delegate: Item {
                            id: noteRow
                            required property var modelData
                            required property int index
                            width: notesList.width; height: 66
                            readonly property bool selected: root.current && root.current.id === modelData.id
                            readonly property bool isLockedNote: !!modelData.locked || (modelData.title && modelData.title.toLowerCase().indexOf("password") >= 0)
                            Corners.ContinuousRectangle {
                                anchors.fill: parent; anchors.margins: 1
                                radius: 8; normalizeRadius: false
                                color: noteRow.selected ? pal.noteHighlight : (rowMa.containsMouse ? pal.ctrl : "transparent")
                            }
                            Column {
                                x: 12; anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 24; spacing: 2
                                Row {
                                    width: parent.width; spacing: 5
                                    NoteIcon {
                                        visible: noteRow.isLockedNote
                                        anchors.verticalCenter: parent.verticalCenter
                                        kind: "lock"
                                        size: 11
                                        color: pal.text2
                                    }
                                    NoteIcon {
                                        visible: !!noteRow.modelData.pinned
                                        anchors.verticalCenter: parent.verticalCenter
                                        kind: "pin"
                                        size: 11
                                        color: "#D9991C"
                                    }
                                    Text {
                                        width: parent.width - (noteRow.isLockedNote ? 16 : 0) - (noteRow.modelData.pinned ? 16 : 0)
                                        elide: Text.ElideRight
                                        text: noteRow.modelData.title || "New Note"
                                        color: pal.text; font.family: root.fam
                                        font.pixelSize: 13; font.weight: Font.DemiBold
                                    }
                                }
                                Text {
                                    width: parent.width; elide: Text.ElideRight
                                    text: root.fmtWhen(noteRow.modelData.updated) + "  " + (noteRow.modelData.has_drawing ? "Handwritten note" : (noteRow.modelData.snippet || "No additional text"))
                                    color: pal.text2; font.family: root.fam; font.pixelSize: 11
                                }
                                Row {
                                    spacing: 5
                                    FolderGlyph {
                                        anchors.verticalCenter: parent.verticalCenter
                                        size: 12
                                    }
                                    Text {
                                        text: noteRow.modelData.folder
                                        color: pal.text3; font.family: root.fam; font.pixelSize: 10
                                    }
                                }
                            }
                            MouseArea { id: rowMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.select(noteRow.modelData.id) }
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: root.listReady && root.notes.length === 0
                            text: root.query === "" ? "No Notes" : "No results"
                            color: pal.text3; font.family: root.fam; font.pixelSize: 13
                        }
                    }
                }

                // Right-hand paper/editor. Content stays in the base texture so
                // floating controls genuinely refract whatever is behind them.
                Item {
                    id: editorPanel
                    x: win.currentSidebarWidth + win.listWidth
                    y: win.toolbarHeight
                    width: parent.width - x; height: parent.height - y
                    Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    Rectangle { anchors.fill: parent; color: pal.paper }
                    Rectangle {
                        id: trashBanner
                        visible: !!root.current && !!root.current.deleted
                        width: parent.width; height: 38
                        color: pal.dark ? "#382A29" : "#FFF0EA"
                        Text {
                            x: 22; anchors.verticalCenter: parent.verticalCenter
                            text: "This note is in Recently Deleted"
                            color: pal.text2; font.family: root.fam; font.pixelSize: 12
                        }
                    }
                    Column {
                        id: editorColumn
                        anchors.fill: parent
                        anchors.topMargin: trashBanner.visible ? trashBanner.height : 0
                        visible: root.view === "text" && !!root.current && (!root.current.locked || root.currentUnlocked)
                        spacing: 0
                        Item { width: parent.width; height: 13 }
                        Text {
                            width: parent.width; height: 16
                            text: root.current ? root.fmtLong(root.current.updated) : ""
                            color: pal.text3; font.family: root.fam; font.pixelSize: 10
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Item { width: parent.width; height: 9 }
                        TextField {
                            id: titleEdit
                            x: 24; width: parent.width - 48; height: 36
                            placeholderText: "Title"
                            color: pal.text; placeholderTextColor: pal.text3
                            font.family: root.fam; font.pixelSize: 20; font.weight: Font.DemiBold
                            background: null
                            readOnly: !!root.current && !!root.current.deleted
                            onTextChanged: if (!root.loading && root.current && text !== root.current.title) root.markDirty()
                        }
                        Flickable {
                            id: bodyScroll
                            width: parent.width; height: parent.height - 77
                            contentWidth: width
                            contentHeight: bodyEdit.contentHeight + 45
                            clip: true
                            TextEdit {
                                id: bodyEdit
                                x: 24; width: parent.width - 48
                                wrapMode: TextEdit.Wrap
                                textFormat: TextEdit.PlainText
                                color: pal.text
                                font.family: root.fam; font.pixelSize: 13
                                selectionColor: pal.dark ? "#345E92" : "#B6D7FF"
                                persistentSelection: true
                                readOnly: !!root.current && !!root.current.deleted
                                onTextChanged: if (!root.loading && root.current && text !== root.current.body) {
                                    root.markDirty();
                                    root.checkMathNote();
                                }
                            }
                            ScrollBar.vertical: ScrollBar { width: 6; policy: ScrollBar.AsNeeded }
                        }
                    }
                    Item {
                        id: lockedNoteOverlay
                        anchors.fill: parent
                        anchors.topMargin: trashBanner.visible ? trashBanner.height : 0
                        visible: root.view === "text" && !!root.current && !!root.current.locked && !root.currentUnlocked
                        Rectangle { anchors.fill: parent; color: pal.paper }
                        Column {
                            anchors.centerIn: parent
                            spacing: 12
                            NoteIcon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                kind: "lock"
                                size: 44
                                strokeWidth: 1.8
                                color: pal.text3
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "This note is locked"
                                color: pal.text; font.family: root.fam
                                font.pixelSize: 16; font.weight: Font.DemiBold
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "The contents of this note are protected."
                                color: pal.text3; font.family: root.fam
                                font.pixelSize: 12
                            }
                            Item { width: 1; height: 6 }
                            Item {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 110; height: 32
                                GlassSurface {
                                    anchors.fill: parent
                                    dark: pal.dark
                                    cornerRadius: 16
                                    hovered: unlockBtnMa.containsMouse
                                    pressed: unlockBtnMa.pressed
                                }
                                Text {
                                    anchors.centerIn: parent
                                    text: "View Note"
                                    color: pal.text
                                    font.family: root.fam
                                    font.pixelSize: 13
                                    font.weight: Font.Medium
                                }
                                MouseArea {
                                    id: unlockBtnMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.currentUnlocked = true
                                }
                            }
                        }
                    }
                    Item {
                        id: drawingView
                        anchors.fill: parent
                        anchors.topMargin: trashBanner.visible ? trashBanner.height : 0
                        visible: root.view === "drawing"
                        Corners.ContinuousRectangle {
                            x: 18; y: 10; width: parent.width - 36; height: parent.height - 21
                            radius: 9; normalizeRadius: false; color: pal.dark ? "#F4F4F5" : "#FFFFFF"
                            border.width: 1; border.color: pal.sep
                        }
                        Canvas {
                            id: drawingCanvas
                            x: 19; y: 11
                            width: parent.width - 38; height: parent.height - 23
                            renderStrategy: Canvas.Cooperative
                            onPaint: {
                                var ctx = getContext("2d");
                                ctx.reset();
                                var W = width, H = height;
                                function drawStroke(s) {
                                    var pts = s.points || [];
                                    if (pts.length < 2) return;
                                    var brush = s.brush || "Pen";
                                    ctx.save();
                                    ctx.strokeStyle = s.color || "#1D1D1F";
                                    ctx.fillStyle = s.color || "#1D1D1F";
                                    var pw = Math.max(1, (s.width || 0.003) * W);
                                    var a = 1.0;
                                    if (brush === "Monoline") pw *= 0.85;
                                    else if (brush === "Marker") { pw *= 2.4; a = 0.50; }
                                    else if (brush === "Pencil") { pw *= 0.72; a = 0.62; }
                                    else if (brush === "Crayon") { pw *= 1.65; a = 0.76; }
                                    else if (brush === "Fountain Pen") pw *= 1.25;
                                    else if (brush === "Reed") pw *= 1.85;
                                    else if (brush === "Watercolour") { pw *= 2.8; a = 0.24; }
                                    ctx.globalAlpha = a;
                                    ctx.lineWidth = pw;
                                    ctx.lineCap = "round"; ctx.lineJoin = "round";
                                    ctx.beginPath();
                                    if (s.tool === "pen" || s.tool === "eraser") {
                                        ctx.moveTo(pts[0] * W, pts[1] * H);
                                        for (var i=2; i<pts.length; i+=2) ctx.lineTo(pts[i] * W, pts[i+1] * H);
                                        if (s.tool === "eraser") {
                                            ctx.restore(); return; // eraser preview outlined separately below
                                        }
                                        ctx.stroke();
                                        if (brush === "Watercolour" || brush === "Crayon") {
                                            ctx.globalAlpha = brush === "Watercolour" ? 0.10 : 0.13;
                                            ctx.lineWidth = pw * 1.5; ctx.stroke();
                                        }
                                    } else if (s.tool === "line") {
                                        ctx.moveTo(pts[0]*W,pts[1]*H); ctx.lineTo(pts[2]*W,pts[3]*H); ctx.stroke();
                                    } else if (s.tool === "rect") {
                                        ctx.strokeRect(Math.min(pts[0],pts[2])*W,Math.min(pts[1],pts[3])*H,
                                                       Math.abs(pts[2]-pts[0])*W,Math.abs(pts[3]-pts[1])*H);
                                    } else if (s.tool === "ellipse") {
                                        ctx.ellipse((pts[0]+pts[2])*0.5*W,(pts[1]+pts[3])*0.5*H,
                                                    Math.abs(pts[2]-pts[0])*0.5*W,Math.abs(pts[3]-pts[1])*0.5*H,
                                                    0,0,Math.PI*2); ctx.stroke();
                                    }
                                    ctx.restore();
                                }
                                for (var i=0; i<root.strokes.length; i++) drawStroke(root.strokes[i]);
                                if (root.drawing && root.pendingStroke) {
                                    if (root.pendingStroke.tool === "eraser") {
                                        var e = root.pendingStroke.points;
                                        if (e.length >= 2) {
                                            ctx.save(); ctx.strokeStyle="#808080"; ctx.lineWidth=1.5;
                                            ctx.beginPath(); ctx.arc(e[e.length-2]*W,e[e.length-1]*H,
                                                                  root.penWidth+9,0,Math.PI*2); ctx.stroke(); ctx.restore();
                                        }
                                    } else drawStroke(root.pendingStroke);
                                }
                            }
                            MouseArea {
                                id: drawArea
                                anchors.fill: parent
                                enabled: !!root.current && !root.current.deleted
                                onPressed: function (mouse) { root.startStroke(mouse.x/width,mouse.y/height); }
                                onPositionChanged: function (mouse) { if (root.drawing) root.moveStroke(mouse.x/width,mouse.y/height); }
                                onReleased: root.endStroke()
                            }
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: root.strokes.length === 0 && !root.drawing
                            text: "Draw with the pen or shape tools"
                            color: "#B9BAC0"; font.family: root.fam; font.pixelSize: 12
                        }
                    }
                    Column {
                        anchors.centerIn: parent
                        visible: root.view === "text" && !root.current
                        spacing: 10
                        NoteIcon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            kind: "compose"
                            size: 44
                            strokeWidth: 1.5
                            color: pal.text3
                            opacity: 0.6
                        }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "No Note Selected"; color: pal.text2; font.family: root.fam; font.pixelSize: 15; font.weight: Font.DemiBold }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Choose a note from the list, or create a new one."; color: pal.text3; font.family: root.fam; font.pixelSize: 12 }
                    }
                }
            }

            // Snapshot once, use for all controls and popovers. `recursive: false`
            // guarantees that glass surfaces cannot create recursive captures.
            ShaderEffectSource {
                id: backdropSnapshot
                visible: false
                width: baseScene.width; height: baseScene.height
                sourceItem: baseScene
                hideSource: false
                recursive: false
                live: false
            }

            // Window-edge resize handles float ABOVE baseScene.
            MouseArea { x: parent.width-9; y: parent.height-9; width: 9; height: 9; z: 99; cursorShape: Qt.SizeFDiagCursor; onPressed: win.startSystemResize(Qt.BottomEdge | Qt.RightEdge) }
            MouseArea { x: parent.width-5; y: 12; width: 5; height: parent.height-24; z: 99; cursorShape: Qt.SizeHorCursor; onPressed: win.startSystemResize(Qt.RightEdge) }
            MouseArea { x: 12; y: parent.height-5; width: parent.width-24; height: 5; z: 99; cursorShape: Qt.SizeVerCursor; onPressed: win.startSystemResize(Qt.BottomEdge) }

            // Toolbar controls: independent, physically refracting glass pills.
            // Left cluster (above sidebar) — Golden Gate layout: new folder + sidebar toggle.
            Row {
                id: topLeftActions
                x: root.sidebarCollapsed ? 82 : Math.max(82, win.currentSidebarWidth - 70)
                y: 11; spacing: 5; z: 40
                Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                GlassButton {
                    visible: !root.sidebarCollapsed
                    icon: "folder-new"; tip: "New folder"; slim: true; dark: pal.dark
                    backdropSource: backdropSnapshot; sceneRoot: baseScene
                    onClicked: { root.addingFolder = true; newFolderEdit.text = ""; newFolderEdit.forceActiveFocus(); }
                }
                GlassButton {
                    icon: "sidebar"; tip: root.sidebarCollapsed ? "Show sidebar" : "Hide sidebar"
                    slim: true; dark: pal.dark; active: !root.sidebarCollapsed
                    backdropSource: backdropSnapshot; sceneRoot: baseScene
                    onClicked: root.sidebarCollapsed = !root.sidebarCollapsed
                }
            }
            // "•••" pill next to the folder title with divider — Golden Gate list-level menu.
            Row {
                id: listHeaderActions
                x: win.currentSidebarWidth + win.listWidth - 46; y: 11; z: 40
                spacing: 6
                Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                GlassButton {
                    id: listHeaderMoreBtn
                    icon: "more"; tip: "Sort & view options"; slim: true
                    dark: pal.dark
                    dimmed: root.notes.length === 0
                    onClicked: {
                        var p = listHeaderMoreBtn.mapToItem(frame, width / 2, height + 6);
                        sortMenu.anchorX = p.x;
                        sortMenu.anchorY = p.y;
                        sortMenu.open = !sortMenu.open;
                    }
                }
                Rectangle {
                    width: 1; height: 18; color: pal.sep
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // Editor toolbar — Golden Gate layout matching Foto 2:
            // Compose note, divider, segmented capsule [ Aa | Checklist | Table | Attachment | Markup | Writing Tools | Lock ], divider, capsule [ Share | More ]
            Row {
                id: topActions
                x: win.currentSidebarWidth + win.listWidth + 12
                y: 11; spacing: 6; z: 40
                Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                // Compose / New note circular button
                GlassButton {
                    icon: "compose"; tip: "New note"; bigger: true; dark: pal.dark
                    onClicked: root.newNote()
                }

                // Vertical separator
                Rectangle {
                    width: 1; height: 18; color: pal.sep
                    anchors.verticalCenter: parent.verticalCenter
                }

                // Unified capsule toolbar: [ Aa | Checklist | Table | Attachment | Markup | Writing Tools | Lock ]
                Item {
                    id: toolsCapsule
                    height: 30
                    width: capsuleRow.width + 4
                    anchors.verticalCenter: parent.verticalCenter
                    GlassSurface { anchors.fill: parent; dark: pal.dark; cornerRadius: 15; circle: true }
                    Row {
                        id: capsuleRow
                        x: 2; anchors.verticalCenter: parent.verticalCenter
                        spacing: 1
                        ToolPillButton {
                            id: styleBtn
                            sym: "Aa"; tip: "Format"; dark: pal.dark
                            dimmed: !root.current || root.current.deleted
                            onClicked: {
                                root.brushMenuOpen = false;
                                var p = styleBtn.mapToItem(frame, width / 2, height + 6);
                                styleMenu.anchorX = p.x;
                                styleMenu.anchorY = p.y;
                                styleMenu.open = !styleMenu.open;
                            }
                        }
                        ToolPillButton {
                            icon: "checklist"; tip: "Checklist"; dark: pal.dark
                            dimmed: !root.current || root.current.deleted
                            onClicked: root.toggleChecklist()
                        }
                        ToolPillButton {
                            id: tableBtn
                            icon: "table"; tip: "Table"; dark: pal.dark
                            dimmed: !root.current || root.current.deleted
                            onClicked: root.insertTable()
                        }
                        ToolPillButton {
                            id: attachmentBtn
                            icon: "attachment"; tip: "Attachment"; dark: pal.dark
                            dimmed: !root.current || root.current.deleted
                            onClicked: {
                                var p = attachmentBtn.mapToItem(frame, width / 2, height + 6);
                                attachmentMenu.anchorX = p.x;
                                attachmentMenu.anchorY = p.y;
                                attachmentMenu.open = !attachmentMenu.open;
                            }
                        }
                        ToolPillButton {
                            icon: "markup"; tip: "Markup"; dark: pal.dark
                            active: root.view === "drawing"
                            onClicked: { root.view = root.view === "drawing" ? "text" : "drawing"; if (root.view === "drawing") drawingCanvas.requestPaint(); }
                        }
                        ToolPillButton {
                            id: writingToolsBtn
                            icon: "sparkles"; tip: "Writing Tools (Apple Intelligence)"; dark: pal.dark
                            dimmed: !root.current || root.current.deleted
                            onClicked: {
                                var p = writingToolsBtn.mapToItem(frame, width / 2, height + 6);
                                writingToolsMenu.anchorX = p.x;
                                writingToolsMenu.anchorY = p.y;
                                writingToolsMenu.open = !writingToolsMenu.open;
                            }
                        }
                        ToolPillButton {
                            id: lockBtn
                            icon: "lock"; tip: (root.current && root.current.locked) ? "Unlock / Lock" : "Lock Note"; dark: pal.dark
                            dimmed: !root.current || root.current.deleted
                            active: !!(root.current && root.current.locked)
                            onClicked: root.toggleLockCurrent()
                        }
                    }
                }

                // Vertical separator
                Rectangle {
                    width: 1; height: 18; color: pal.sep
                    anchors.verticalCenter: parent.verticalCenter
                }

                // Share & More capsule: [ Share | More ]
                Item {
                    id: shareMoreCapsule
                    height: 30
                    width: shareMoreRow.width + 4
                    anchors.verticalCenter: parent.verticalCenter
                    GlassSurface { anchors.fill: parent; dark: pal.dark; cornerRadius: 15; circle: true }
                    Row {
                        id: shareMoreRow
                        x: 2; anchors.verticalCenter: parent.verticalCenter
                        spacing: 1
                        ToolPillButton {
                            id: shareBtn
                            icon: "share"; tip: "Share / Export"; dark: pal.dark
                            dimmed: !root.current
                            onClicked: {
                                var p = shareBtn.mapToItem(frame, width / 2, height + 6);
                                exportMenu.anchorX = p.x;
                                exportMenu.anchorY = p.y;
                                exportMenu.open = !exportMenu.open;
                            }
                        }
                        Rectangle {
                            width: 1; height: 16
                            color: pal.dark ? "#18FFFFFF" : "#14000000"
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        ToolPillButton {
                            id: editorMoreBtn
                            icon: "more"; tip: "More options"; dark: pal.dark
                            dimmed: !root.current
                            onClicked: {
                                var p = editorMoreBtn.mapToItem(frame, width / 2, height + 6);
                                moreMenu.anchorX = p.x;
                                moreMenu.anchorY = p.y;
                                moreMenu.open = !moreMenu.open;
                            }
                        }
                    }
                }
            }

            // Right-most pill search field, as in macOS Tahoe Notes.
            Item {
                id: searchPill
                anchors.right: parent.right; anchors.rightMargin: 13
                y: 11; width: 175; height: 30; z: 40
                GlassSurface { anchors.fill: parent; dark: pal.dark; cornerRadius: 15; circle: true }
                NoteIcon {
                    x: 10; anchors.verticalCenter: parent.verticalCenter
                    kind: "search"; size: 15; strokeWidth: 1.5; color: pal.text2
                }
                TextField {
                    id: searchField
                    x: 32; width: parent.width - 42; height: parent.height
                    verticalAlignment: TextInput.AlignVCenter
                    placeholderText: "Search"
                    color: pal.text; placeholderTextColor: pal.text3
                    font.family: root.fam; font.pixelSize: 13
                    background: null
                    onTextEdited: { root.query = text; root.refreshList(); }
                    Keys.onEscapePressed: { text = ""; root.query = ""; root.refreshList(); }
                }
            }

            // Trash actions shown only on deleted notes.
            Row {
                visible: !!root.current && !!root.current.deleted
                x: win.currentSidebarWidth + win.listWidth + 280; y: 60
                spacing: 7; z: 45
                Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                GlassButton { icon: "restore"; tip: "Restore"; dark: pal.dark; backdropSource: backdropSnapshot; sceneRoot: baseScene; onClicked: root.restoreCurrent() }
                GlassButton { icon: "close"; tip: "Delete forever (two clicks)"; dark: pal.dark; backdropSource: backdropSnapshot; sceneRoot: baseScene; onClicked: root.purgeCurrent() }
            }

            // Floating pen palette — Golden Gate compact bottom bar.
            Item {
                id: penDock
                visible: root.view === "drawing" && !!root.current
                x: win.currentSidebarWidth + win.listWidth + (frame.width - (win.currentSidebarWidth + win.listWidth) - width) / 2
                y: frame.height - 52
                width: paletteControls.width + 16
                height: 38
                z: 45
                Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                GlassSurface {
                    anchors.fill: parent; cornerRadius: 19
                    backdropSource: backdropSnapshot; sceneRoot: baseScene; dark: pal.dark
                }
                Row {
                    id: paletteControls
                    x: 8; anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    // Lasso / Selection
                    GlassButton { icon: "lasso"; tip: "Selection / Lasso"; slim: true; dark: pal.dark; backdropSource: backdropSnapshot; sceneRoot: baseScene }
                    // Brush selector with black pill highlight
                    Item {
                        width: 44; height: 28
                        Corners.ContinuousRectangle {
                            anchors.fill: parent; radius: 14; normalizeRadius: false
                            color: root.brushMenuOpen ? (pal.dark ? "#FFFFFF" : "#1D1D1F") : (penBtnMa.containsMouse ? pal.ctrlHover : (pal.dark ? "#33FFFFFF" : "#18000000"))
                        }
                        Row {
                            anchors.centerIn: parent
                            spacing: 3
                            NoteIcon {
                                kind: root.tool === "eraser" ? "eraser" : "pen"
                                size: 13; strokeWidth: 1.3
                                color: root.brushMenuOpen ? (pal.dark ? "#1D1D1F" : "#FFFFFF") : pal.text
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            NoteIcon {
                                kind: "chevron-down"
                                size: 8; strokeWidth: 1.2
                                color: root.brushMenuOpen ? (pal.dark ? "#1D1D1F" : "#FFFFFF") : pal.text2
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        MouseArea {
                            id: penBtnMa
                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: root.brushMenuOpen = !root.brushMenuOpen
                        }
                    }
                    // Color dot
                    Item {
                        width: 26; height: 28
                        Corners.ContinuousRectangle {
                            width: 18; height: 18; radius: 9; normalizeRadius: false
                            anchors.centerIn: parent
                            color: root.palette[root.penIndex]
                            border.width: 1.5; border.color: pal.dark ? "#80FFFFFF" : "#60000000"
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: colorMenu.open = !colorMenu.open }
                    }
                    // Shapes
                    GlassButton {
                        icon: "shapes"
                        tip: "Shapes"; slim: true; dark: pal.dark
                        backdropSource: backdropSnapshot; sceneRoot: baseScene
                        onClicked: {
                            var tools = ["pen", "line", "rect", "ellipse"];
                            root.tool = tools[(tools.indexOf(root.tool) + 1) % tools.length];
                            if (root.tool === "pen" && root.brushName === "Eraser") root.brushName = "Pen";
                            root.brushMenuOpen = false;
                        }
                    }
                    // Text / Aa
                    GlassButton {
                        sym: "Aa"; tip: "Text mode"; fontPx: 12; slim: true; dark: pal.dark
                        backdropSource: backdropSnapshot; sceneRoot: baseScene
                        onClicked: { root.view = "text"; }
                    }
                    // Stylus / Draw
                    GlassButton {
                        icon: "stylus"; tip: "Stylus / Pen mode"; slim: true; dark: pal.dark
                        backdropSource: backdropSnapshot; sceneRoot: baseScene
                        active: root.tool === "pen" && root.brushName !== "Eraser"
                        onClicked: { root.tool = "pen"; root.brushName = "Pen"; }
                    }
                    // Undo
                    GlassButton { icon: "undo"; tip: "Undo"; slim: true; dark: pal.dark; backdropSource: backdropSnapshot; sceneRoot: baseScene; onClicked: root.undoDrawing() }
                }
            }
            // Clicking outside any menu closes all menus; menu surfaces are above catcher.
            MouseArea {
                anchors.fill: parent
                z: 46
                visible: styleMenu.open || moreMenu.open || exportMenu.open || sortMenu.open || writingToolsMenu.open || attachmentMenu.open || root.brushMenuOpen || colorMenu.open
                onClicked: {
                    styleMenu.open = false;
                    moreMenu.open = false;
                    exportMenu.open = false;
                    sortMenu.open = false;
                    writingToolsMenu.open = false;
                    attachmentMenu.open = false;
                    root.brushMenuOpen = false;
                    colorMenu.open = false;
                }
            }

            // Sort & View Options popover (for listHeaderMoreBtn)
            Item {
                id: sortMenu
                property bool open: false
                property real anchorX: 0
                property real anchorY: 48
                visible: open
                x: anchorX > 0 ? Math.max(10, Math.min(frame.width - width - 12, anchorX - width / 2)) : win.currentSidebarWidth + win.listWidth - width
                y: anchorY > 0 ? anchorY : 48
                width: 195; height: 215
                z: 47
                MenuSurface {
                    anchors.fill: parent
                    dark: pal.dark; cornerRadius: 13
                }
                Column {
                    x: 6; y: 6; width: parent.width - 12; spacing: 1
                    Text {
                        x: 10; height: 20; verticalAlignment: Text.AlignVCenter
                        text: "Sort by"; color: pal.text3
                        font.family: root.fam; font.pixelSize: 11; font.weight: Font.DemiBold
                    }
                    MenuItemRow {
                        width: parent.width; dark: pal.dark; fam: root.fam
                        label: "Date Edited"; hasCheck: true; checked: root.sortBy === "updated"
                        onClicked: { root.sortBy = "updated"; root.refreshList(); sortMenu.open = false; }
                    }
                    MenuItemRow {
                        width: parent.width; dark: pal.dark; fam: root.fam
                        label: "Date Created"; hasCheck: true; checked: root.sortBy === "created"
                        onClicked: { root.sortBy = "created"; root.refreshList(); sortMenu.open = false; }
                    }
                    MenuItemRow {
                        width: parent.width; dark: pal.dark; fam: root.fam
                        label: "Title"; hasCheck: true; checked: root.sortBy === "title"
                        onClicked: { root.sortBy = "title"; root.refreshList(); sortMenu.open = false; }
                    }
                    Rectangle { width: parent.width; height: 1; color: pal.sep }
                    MenuItemRow {
                        width: parent.width; dark: pal.dark; fam: root.fam
                        label: "Newest First"; hasCheck: true; checked: root.sortOrder === "desc"
                        onClicked: { root.sortOrder = "desc"; root.refreshList(); sortMenu.open = false; }
                    }
                    MenuItemRow {
                        width: parent.width; dark: pal.dark; fam: root.fam
                        label: "Oldest First"; hasCheck: true; checked: root.sortOrder === "asc"
                        onClicked: { root.sortOrder = "asc"; root.refreshList(); sortMenu.open = false; }
                    }
                }
            }

            // Apple Intelligence — Writing Tools popover
            Item {
                id: writingToolsMenu
                property bool open: false
                property real anchorX: 0
                property real anchorY: 48
                visible: open
                x: anchorX > 0 ? Math.max(10, Math.min(frame.width - width - 12, anchorX - width / 2)) : topActions.x + 120
                y: anchorY > 0 ? anchorY : 48
                width: 205; height: 175
                z: 47
                MenuSurface {
                    anchors.fill: parent
                    dark: pal.dark; cornerRadius: 13
                }
                Column {
                    x: 6; y: 6; width: parent.width - 12; spacing: 1
                    Row {
                        x: 8; height: 24; spacing: 5
                        NoteIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            kind: "sparkles"; size: 12; color: "#A855F7"
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Apple Intelligence"; color: pal.text3
                            font.family: root.fam; font.pixelSize: 11; font.weight: Font.DemiBold
                        }
                    }
                    MenuItemRow {
                        width: parent.width; dark: pal.dark; fam: root.fam
                        label: "Summarize"
                        onClicked: root.applyWritingTool("summarize")
                    }
                    MenuItemRow {
                        width: parent.width; dark: pal.dark; fam: root.fam
                        label: "Proofread"
                        onClicked: root.applyWritingTool("proofread")
                    }
                    MenuItemRow {
                        width: parent.width; dark: pal.dark; fam: root.fam
                        label: "Make Professional"
                        onClicked: root.applyWritingTool("formal")
                    }
                    MenuItemRow {
                        width: parent.width; dark: pal.dark; fam: root.fam
                        label: "Make Concise"
                        onClicked: root.applyWritingTool("concise")
                    }
                }
            }

            // Attachment popover
            Item {
                id: attachmentMenu
                property bool open: false
                property real anchorX: 0
                property real anchorY: 48
                visible: open
                x: anchorX > 0 ? Math.max(10, Math.min(frame.width - width - 12, anchorX - width / 2)) : topActions.x + 80
                y: anchorY > 0 ? anchorY : 48
                width: 195; height: 115
                z: 47
                MenuSurface {
                    anchors.fill: parent
                    dark: pal.dark; cornerRadius: 13
                }
                Column {
                    x: 6; y: 6; width: parent.width - 12; spacing: 1
                    MenuItemRow {
                        width: parent.width; dark: pal.dark; fam: root.fam
                        label: "Add Web Link"
                        onClicked: root.insertAttachment("link")
                    }
                    MenuItemRow {
                        width: parent.width; dark: pal.dark; fam: root.fam
                        label: "Add Photo / Image"
                        onClicked: root.insertAttachment("photo")
                    }
                    MenuItemRow {
                        width: parent.width; dark: pal.dark; fam: root.fam
                        label: "Add Document / PDF"
                        onClicked: root.insertAttachment("file")
                    }
                }
            }

            // Format popover
            Item {
                id: styleMenu
                property bool open: false
                property real anchorX: 0
                property real anchorY: 48
                visible: open
                x: anchorX > 0 ? Math.max(10, Math.min(frame.width - width - 12, anchorX - width / 2)) : topActions.x + 34
                y: anchorY > 0 ? anchorY : 48
                width: 195; height: 310
                z: 47
                MenuSurface {
                    anchors.fill: parent
                    dark: pal.dark; cornerRadius: 13
                }
                Column {
                    x: 6; y: 6; width: parent.width - 12; spacing: 1
                    Repeater {
                        model: [
                            { id:"title", label:"Title" }, { id:"heading", label:"Heading" },
                            { id:"subheading", label:"Subheading" }, { id:"body", label:"Body" },
                            { id:"bulleted", label:"Bulleted List" }, { id:"dashed", label:"Dashed List" },
                            { id:"numbered", label:"Numbered List" }, { id:"quote", label:"Block Quote" },
                            { id:"divider", label:"Divider" }
                        ]
                        delegate: MenuItemRow {
                            required property var modelData
                            width: parent.width
                            dark: pal.dark; fam: root.fam
                            label: modelData.label
                            onClicked: modelData.id === "divider" ? root.insertDivider() : root.applyFormat(modelData.id)
                        }
                    }
                }
            }

            // More actions (keeps all existing note management features).
            Item {
                id: moreMenu
                property bool open: false
                property real anchorX: 0
                property real anchorY: 48
                visible: open
                x: anchorX > 0 ? Math.max(10, Math.min(frame.width - width - 12, anchorX - width / 2)) : Math.min(frame.width - width - 12, topActions.x + 180)
                y: anchorY > 0 ? anchorY : 48
                width: 210
                height: Math.min(390, 130 + root.folders.length * 32)
                z: 47
                MenuSurface {
                    anchors.fill: parent; dark: pal.dark
                    cornerRadius: 13
                }
                Flickable {
                    x: 6; y: 6; width: parent.width - 12; height: parent.height - 12
                    contentWidth: width; contentHeight: moreCol.height
                    clip: true
                    Column {
                        id: moreCol
                        width: parent.width; spacing: 2
                        MenuItemRow {
                            width: parent.width; dark: pal.dark; fam: root.fam
                            label: root.current && root.current.pinned ? "Unpin Note" : "Pin Note"
                            onClicked: { root.pinToggle(); moreMenu.open = false; }
                        }
                        MenuItemRow {
                            width: parent.width; dark: pal.dark; fam: root.fam
                            label: "Duplicate Note"
                            onClicked: { root.duplicateCurrent(); moreMenu.open = false; }
                        }
                        MenuItemRow {
                            width: parent.width; dark: pal.dark; fam: root.fam; danger: true
                            label: root.confirmDelete !== "" ? "Click again to delete" : "Delete Note"
                            onClicked: { root.requestDelete(); moreMenu.open = false; }
                        }
                        Rectangle {
                            width: parent.width; height: 1
                            color: pal.dark ? "#20FFFFFF" : "#18000000"
                        }
                        Text {
                            x: 9; height: 22
                            verticalAlignment: Text.AlignVCenter
                            text: "Move to"; color: pal.text3
                            font.family: root.fam; font.pixelSize: 11; font.weight: Font.DemiBold
                        }
                        Repeater {
                            model: root.folders
                            delegate: MenuItemRow {
                                required property var modelData
                                width: parent.width
                                dark: pal.dark; fam: root.fam
                                label: modelData.name
                                dim: root.current && root.current.folder === modelData.name
                                onClicked: { root.moveTo(modelData.name); moreMenu.open = false; }
                            }
                        }
                    }
                }
            }

            // Export as md, txt, png, or svg — unchanged in the backend.
            Item {
                id: exportMenu
                property bool open: false
                property real anchorX: 0
                property real anchorY: 48
                visible: open
                x: anchorX > 0 ? Math.max(10, Math.min(frame.width - width - 12, anchorX - width / 2)) : Math.min(frame.width - width - 12, topActions.x + 145)
                y: anchorY > 0 ? anchorY : 48
                width: 215; height: 142
                z: 47
                MenuSurface {
                    anchors.fill: parent; dark: pal.dark
                    cornerRadius: 13
                }
                Column {
                    x: 6; y: 6; width: parent.width - 12; spacing: 1
                    Repeater {
                        model: [
                            {fmt:"md", label:"Export as Markdown"},
                            {fmt:"txt",label:"Export as Text"},
                            {fmt:"png",label:"Export Drawing as PNG"},
                            {fmt:"svg",label:"Export Drawing as SVG"}
                        ]
                        delegate: MenuItemRow {
                            required property var modelData
                            width: parent.width; dark: pal.dark; fam: root.fam
                            label: modelData.label
                            onClicked: root.exportNote(modelData.fmt)
                        }
                    }
                }
            }

            // macOS Golden Gate brush menu shown directly above the floating penDock.
            Item {
                id: brushMenu
                visible: root.brushMenuOpen && penDock.visible
                x: Math.max(10, Math.min(frame.width - width - 10, penDock.x + (penDock.width - width) / 2))
                y: Math.max(50, penDock.y - height - 10)
                width: 184; height: 336
                z: 48
                MenuSurface {
                    anchors.fill: parent
                    dark: pal.dark; cornerRadius: 14
                }
                // Top row: stroke weight choices (5 wavy lines, active has orange border as in Golden Gate)
                Row {
                    x: 10; y: 10; spacing: 3
                    Repeater {
                        model: [1, 2, 3, 4, 5]
                        delegate: Item {
                            id: tipChoice
                            required property int modelData
                            readonly property real w: modelData * 2
                            readonly property bool activeTip: Math.abs(root.penWidth - w) < 1.0
                            width: 30; height: 28
                            Corners.ContinuousRectangle {
                                anchors.fill: parent; radius: 6; normalizeRadius: false
                                color: tipChoice.activeTip ? (pal.dark ? "#40E28B24" : "#FFEED6") : (tipMa.containsMouse ? pal.ctrlHover : "transparent")
                                border.width: tipChoice.activeTip ? 1.5 : 0
                                border.color: "#E28B24"
                            }
                            Canvas {
                                anchors.centerIn: parent
                                width: 22; height: 16
                                readonly property real strokeW: Math.max(1.2, tipChoice.w * 0.55)
                                readonly property color strokeC: tipChoice.activeTip ? "#E28B24" : pal.text
                                antialiasing: true
                                onPaint: {
                                    var c = getContext("2d");
                                    c.reset();
                                    c.strokeStyle = strokeC;
                                    c.lineWidth = strokeW;
                                    c.lineCap = "round";
                                    c.beginPath();
                                    c.moveTo(2, 11);
                                    c.bezierCurveTo(7, 3, 11, 14, 15, 6);
                                    c.lineTo(19, 5);
                                    c.stroke();
                                }
                            }
                            MouseArea {
                                id: tipMa
                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: root.penWidth = tipChoice.w
                            }
                        }
                    }
                }
                Rectangle { x: 10; y: 44; width: parent.width - 20; height: 1; color: pal.sep }
                Column {
                    x: 6; y: 49; width: parent.width - 12; spacing: 0
                    Repeater {
                        model: ["Pen", "Monoline", "Marker", "Pencil", "Crayon",
                                "Fountain Pen", "Reed", "Watercolour", "Eraser"]
                        delegate: Item {
                            id: brushChoice
                            required property string modelData
                            width: parent.width; height: 30
                            readonly property bool isSelected: root.brushName === modelData
                            Corners.ContinuousRectangle {
                                anchors.fill: parent; radius: 6; normalizeRadius: false
                                color: brushMouse.containsMouse ? pal.ctrlHover : "transparent"
                            }
                            // Left checkmark (macOS Notes style)
                            NoteIcon {
                                x: 6; anchors.verticalCenter: parent.verticalCenter
                                kind: "check"; size: 12; strokeWidth: 1.8
                                color: pal.text
                                visible: brushChoice.isSelected
                            }
                            // Brush Icon
                            NoteIcon {
                                x: 23; anchors.verticalCenter: parent.verticalCenter
                                kind: brushChoice.modelData === "Eraser" ? "eraser" : "pen"
                                size: 13
                                color: pal.text
                            }
                            // Brush Name
                            Text {
                                x: 42; anchors.verticalCenter: parent.verticalCenter
                                text: brushChoice.modelData
                                color: pal.text; font.family: root.fam; font.pixelSize: 12
                                font.weight: brushChoice.isSelected ? Font.DemiBold : Font.Normal
                            }
                            MouseArea {
                                id: brushMouse
                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: root.selectBrush(brushChoice.modelData)
                            }
                        }
                    }
                }
            }

            // Colour palette in a smaller glass popover.
            Item {
                id: colorMenu
                property bool open: false
                visible: open && penDock.visible
                x: Math.max(10, Math.min(frame.width - width - 10, penDock.x + 30))
                y: Math.max(50, penDock.y - height - 10)
                width: 204; height: 46
                z: 48
                MenuSurface {
                    anchors.fill: parent; dark: pal.dark
                    cornerRadius: 13
                }
                Row {
                    anchors.centerIn: parent
                    spacing: 5
                    Repeater {
                        model: root.palette
                        delegate: Item {
                            id: colorChoice
                            required property var modelData
                            required property int index
                            width: 20; height: 26
                            Corners.ContinuousRectangle {
                                anchors.centerIn: parent
                                width: 18; height: 18; radius: 9; normalizeRadius: false
                                color: colorChoice.modelData
                                border.width: root.penIndex === colorChoice.index ? 2 : 1
                                border.color: root.penIndex === colorChoice.index ? root.accent : (pal.dark ? "#40FFFFFF" : "#30000000")
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.penIndex = colorChoice.index; colorMenu.open = false; } }
                        }
                    }
                }
            }
        }
    }
}
