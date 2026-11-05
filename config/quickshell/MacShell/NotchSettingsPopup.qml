pragma ComponentBehavior: Bound
import QtQuick
import "NotchGeometry.js" as Geometry
import QtQuick.Controls
import QtQuick.Shapes
import "Common" as Common

// Settings live in the window overlay, outside the animated notch clip.
// Blur the visible notch composited over the desktop; exclude this overlay popup.
Popup {
    id: popup
    required property var host
    required property Item control
    property string title: "Settings"
    property string subtitle: ""
    property bool acceptable: true
    property string acceptText: "Save"
    property bool showCancel: true
    default property alias settingsContent: fields.data
    signal saveRequested()
    readonly property bool dark: !host.bar || host.bar.effDark !== false
    // Menu-bar dropdowns use a 42 px clear blur and the shared material preset.
    readonly property real backdropBlurRadius: Common.GlassMaterial.blurRadius(42)
    readonly property real materialOpacity: host.bar && host.bar.effGlassOpacity!==undefined ? host.bar.effGlassOpacity : host.glassOpacity
    readonly property real materialLiquid: host.bar && host.bar.effGlassLiquid!==undefined ? host.bar.effGlassLiquid : host.glassLiquid
    readonly property real materialRim: host.bar && host.bar.effGlassRim!==undefined ? host.bar.effGlassRim : host.glassRim
    readonly property real materialGrain: host.bar && host.bar.effGlassGrain!==undefined ? host.bar.effGlassGrain : host.glassGrain
    readonly property color borderTint: host.bar && host.bar.menuBorderColor!==undefined ? host.bar.menuBorderColor : "#8A9AB5"
    readonly property url materialShader: Qt.resolvedUrl("notch-menu-tail-v1.frag.qsb")
    property bool glassFailed:false
    readonly property bool opaque: !!host.bar && host.bar.reduceTransparency
    readonly property color foreground: dark ? "#F5F5F7" : "#202124"
    readonly property color secondary: dark ? "#CBD0DA" : "#535966"
    readonly property real cornerRadius:Geometry.menuRadius
    readonly property real contentPadding:Geometry.menuPadding
    readonly property real tailHeight: 9
    property real popProgress: 1
    property real jellyX: 0
    property real jellyY: 0
    property real offsetX: 0
    property real offsetY: 0
    property bool motionArmed: false
    property bool dragging: false
    property point pressPosition: Qt.point(0, 0)
    property point dragOrigin: Qt.point(0, 0)
    readonly property real elasticX: host.reducedMotion ? 0 : Math.max(-12, Math.min(12, jellyX))
    readonly property real elasticY: host.reducedMotion ? 0 : Math.max(-12, Math.min(12, jellyY))
    readonly property real elasticScaleX: host.reducedMotion ? 1 : Math.max(0.88, Math.min(1.045, 1 + (popProgress - 1) * 0.42 + Math.abs(elasticX) * 0.002 - Math.abs(elasticY) * 0.001))
    readonly property real elasticScaleY: host.reducedMotion ? 1 : Math.max(0.76, Math.min(1.055, popProgress + Math.abs(elasticY) * 0.002 - Math.abs(elasticX) * 0.001))
    readonly property real tailAmount: Math.max(0, 1 - Math.hypot(offsetX, offsetY) / 40)
    SpringAnimation {
        id: openingSpring
        target: popup; property: "popProgress"; to: 1
        spring: 4.2; damping: 0.28; mass: 0.8; epsilon: 0.001
    }
    Behavior on jellyX { enabled: popup.motionArmed && !popup.host.reducedMotion; SpringAnimation { spring: 4; damping: 0.25; mass: 0.8; epsilon: 0.02 } }
    Behavior on jellyY { enabled: popup.motionArmed && !popup.host.reducedMotion; SpringAnimation { spring: 3.6; damping: 0.26; mass: 0.9; epsilon: 0.02 } }
    readonly property point anchorPoint: {
        host.width; host.height; host.shapeProgress; host.uiScale; host.pageOffset;
        // Positioners can move the button after the page is created. Subscribe
        // to the whole ancestor chain before mapping into the window portal.
        let item = control;
        while (item && item !== parent) {
            item.x; item.y; item.width; item.height; item.scale; item.rotation;
            item = item.parent;
        }
        return control && parent ? control.mapToItem(parent, control.width / 2, control.height) : Qt.point(0, 0);
    }
    readonly property real pointerX: Math.max(cornerRadius+12, Math.min(width-cornerRadius-12, anchorPoint.x-x))
    readonly property real anchoredX: Math.max(8, Math.min(parent ? parent.width - width - 8 : 8, anchorPoint.x - width / 2))
    readonly property real desiredY: anchorPoint.y + 4
    readonly property real screenBottomLimit: Math.min(parent ? parent.height : 1080, host.screenSize.height)
    readonly property rect windowRect: Qt.rect(x - 18, y - 8, width + 36, height + 26)
    parent: control ? control.Window.contentItem : null
    width: Math.min(328, parent ? parent.width - 16 : 328)
    height: Math.min(form.implicitHeight + 2*popup.contentPadding + tailHeight, Math.max(140, screenBottomLimit - desiredY - 8))
    x: Math.max(8, Math.min(parent ? parent.width - width - 8 : 8, anchoredX + offsetX))
    y: Math.max(8, Math.min(screenBottomLimit - height - 8, desiredY + offsetY))
    padding: 0; margins: 8
    popupType: Popup.Item
    modal: false
    dim: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    transformOrigin: Item.Top
    onAboutToShow: {
        if (host.settingsPopup && host.settingsPopup !== popup) host.settingsPopup.close();
        openingSpring.stop(); motionArmed = false; dragging = false;glassFailed=false;
        offsetX = 0; offsetY = 0; jellyX = 0; jellyY = 0;
        popProgress = host.reducedMotion ? 1 : 0.78;
        contentItem.contentY = 0;
        host.settingsPopup = popup;
        Qt.callLater(function() {
            if (!popup.visible) return;
            popup.motionArmed = true;
            if (!popup.host.reducedMotion) openingSpring.restart();
        });
    }
    onAboutToHide: { openingSpring.stop(); motionArmed = false; dragging = false; jellyX = 0; jellyY = 0; }
    onClosed: if (host.settingsPopup === popup) host.settingsPopup = null
    Component.onDestruction: if (host && host.settingsPopup === popup) host.settingsPopup = null
    Connections {
        target: popup.host
        function onExpandedChanged() { if (!popup.host.expanded) popup.close(); }
        function onAvailableChanged() { if (!popup.host.available) popup.close(); }
        function onActivityChanged() { popup.close(); }
        function onReducedMotionChanged() {
            if (popup.host.reducedMotion) { openingSpring.stop(); popup.popProgress = 1; popup.jellyX = 0; popup.jellyY = 0; }
        }
    }
    function movePanel(point) {
        const dx = point.x - pressPosition.x, dy = point.y - pressPosition.y;
        if (!dragging && Math.hypot(dx, dy) < 4) return;
        dragging = true;
        const oldX = x, oldY = y;
        offsetX = Math.max(8, Math.min(parent.width - width - 8, dragOrigin.x + dx)) - anchoredX;
        offsetY = Math.max(8, Math.min(screenBottomLimit - height - 8, dragOrigin.y + dy)) - desiredY;
        if (!host.reducedMotion) {
            jellyX = Math.max(-12, Math.min(12, (oldX - x) * 0.7));
            jellyY = Math.max(-12, Math.min(12, (oldY - y) * 0.7));
        }
    }
    function releasePanel() { dragging = false; jellyX = 0; jellyY = 0; }
    function outline() {
        const w = width - 0.5, h = height - 0.5, t = tailHeight, p = pointerX;
        const r = cornerRadius + Math.min(5, (Math.abs(elasticX) + Math.abs(elasticY)) * 0.2);
        const tip = t * (1 - tailAmount) + 0.5 * tailAmount;
        const bend = Math.min(5, (Math.abs(elasticX) + Math.abs(elasticY)) * 0.25);
        return "M " + r + "," + t + " H " + (p - 12)
            + " C " + (p - 6) + "," + t + " " + (p - 4) + "," + tip + " " + p + "," + tip
            + " C " + (p + 4) + "," + tip + " " + (p + 6) + "," + t + " " + (p + 12) + "," + t
            + " H " + (w - r) + " Q " + w + "," + t + " " + w + "," + (t + r)
            + " C " + (w - bend) + "," + (h * 0.35) + " " + w + "," + (h * 0.65) + " " + w + "," + (h - r)
            + " Q " + w + "," + h + " " + (w - r) + "," + h
            + " H " + r + " Q 0.5," + h + " 0.5," + (h - r)
            + " C " + (0.5 + bend) + "," + (h * 0.65) + " 0.5," + (h * 0.35) + " 0.5," + (t + r)
            + " Q 0.5," + t + " " + r + "," + t + " Z";
    }
    background: Item {
        id: surface
        objectName:"notchFrostedMenuSurface"
        readonly property string path: { popup.width; popup.height; popup.pointerX; popup.elasticX; popup.elasticY; popup.tailAmount; return popup.outline(); }
        transform: Scale { origin.x: popup.pointerX; origin.y: 0; xScale: popup.elasticScaleX; yScale: popup.elasticScaleY }
        readonly property real captureMargin:128
        readonly property point notchOrigin:{
            popup.anchorPoint;popup.x;popup.y;popup.scale;popup.popProgress;popup.elasticScaleX;popup.elasticScaleY;
            return surface.mapToItem(popup.host,0,0);
        }
        readonly property size notchExtent:{
            notchOrigin;surface.width;surface.height;
            const end=surface.mapToItem(popup.host,surface.width,surface.height);
            return Qt.size(end.x-notchOrigin.x,end.y-notchOrigin.y);
        }
        readonly property rect notchRect:{
            const sx=notchExtent.width/Math.max(1,width),sy=notchExtent.height/Math.max(1,height);
            return Qt.rect(notchOrigin.x-captureMargin*sx,notchOrigin.y-captureMargin*sy,
                           (width+2*captureMargin)*sx,(height+2*captureMargin)*sy);
        }
        // The popup is reparented to the window overlay. Sampling only host
        // includes its glass and contents, without recapturing this dropdown.
        Loader {
            id:backdropLayer;objectName:"notchMenuBackdrop"
            active:frostLayer.active;visible:false
            sourceComponent:Item {
                id:composite
                width:surface.width+2*surface.captureMargin;height:surface.height+2*surface.captureMargin
                Item {
                    id:wallpaper;visible:false
                    width:popup.host.screenSize.width;height:popup.host.screenSize.height
                    Rectangle {anchors.fill:parent;color:"#64696F"}
                    Image {anchors.fill:parent;source:popup.host.wallpaperUrl;fillMode:Image.PreserveAspectCrop;asynchronous:true}
                }
                ShaderEffectSource {
                    objectName:"notchMenuDesktopCapture";anchors.fill:parent
                    sourceItem:popup.host.backdrop||wallpaper
                    sourceRect:Qt.rect(surface.notchRect.x+popup.host.backdropPosition.x,
                                       surface.notchRect.y+popup.host.backdropPosition.y,
                                       surface.notchRect.width,surface.notchRect.height)
                    hideSource:true;live:true
                }
                ShaderEffectSource {
                    objectName:"notchMenuSurfaceCapture";anchors.fill:parent
                    sourceItem:popup.host;sourceRect:surface.notchRect
                    hideSource:false;live:true
                }
            }
        }
        Loader {
            id:frostLayer;objectName:"notchMenuFrostLayer"
            anchors.fill: parent
            active: popup.visible && !popup.opaque && GraphicsInfo.api !== GraphicsInfo.Software
            sourceComponent: NotchMenuBarGlass {
                objectName:"notchMenuBarGlass"
                backdrop:backdropLayer.item as Item
                bx:surface.captureMargin;by:surface.captureMargin
                shaderUrl:popup.materialShader
                liquid:!!popup.host.bar && popup.host.bar.liquidActive===true && !popup.glassFailed
                dark:popup.dark
                tailHeight:popup.tailHeight;pointerX:popup.pointerX;tailAmount:popup.tailAmount
                cornerR:popup.cornerRadius
                tint:popup.materialOpacity
                thickness:22
                strength:0.55*popup.materialLiquid
                rim:popup.materialRim
                grain:popup.materialGrain
                blur:42
                rimTint:1;ringW:1.4
                onShaderError:popup.glassFailed=true
            }
        }
        // Use the menu bar's fallback tint and border treatment too.
        Shape {
            anchors.fill:parent
            visible:!frostLayer.active || popup.glassFailed || !popup.host.bar || popup.host.bar.liquidActive!==true
            preferredRendererType:Shape.CurveRenderer
            ShapePath {
                fillColor:popup.opaque || GraphicsInfo.api===GraphicsInfo.Software || popup.glassFailed
                    ? (popup.dark?"#29292D":"#F0F0F3")
                    : popup.dark?Qt.rgba(0.12,0.12,0.13,0.30+popup.materialOpacity*0.9):Qt.rgba(1,1,1,0.30+popup.materialOpacity*0.7)
                strokeColor:popup.dark?Qt.rgba(1,1,1,0.18):Qt.rgba(1,1,1,0.55);strokeWidth:1
                PathSvg {path:surface.path}
            }
        }
        Item {
            id:portalBorder;objectName:"notchMenuBarBorder";anchors.fill:parent
            readonly property bool dark:popup.dark
            readonly property color tint:popup.borderTint
            Shape {
                anchors.fill:parent;preferredRendererType:Shape.CurveRenderer
                ShapePath {fillColor:"transparent";strokeWidth:2;strokeColor:portalBorder.dark?Qt.rgba(0,0,0,0.42):Qt.rgba(0,0,0,0.14);PathSvg {path:surface.path}}
                ShapePath {fillColor:"transparent";strokeWidth:1.25;strokeColor:Qt.rgba(portalBorder.tint.r,portalBorder.tint.g,portalBorder.tint.b,portalBorder.dark?0.16:0.12);PathSvg {path:surface.path}}
            }
        }
    }

    contentItem: Flickable {
        transform: Scale { origin.x: popup.pointerX; origin.y: 0; xScale: popup.elasticScaleX; yScale: popup.elasticScaleY }
        contentHeight: form.implicitHeight + 2*popup.contentPadding + popup.tailHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        Column {
            id: form
            x: popup.contentPadding; y: popup.contentPadding + popup.tailHeight
            width: parent.width - 2*popup.contentPadding; spacing: 14
            Item {
                width: parent.width; height: heading.implicitHeight
                Column {
                    id: heading
                    width: parent.width; spacing: 4
                    Text { width: parent.width; text: popup.title; color: popup.foreground; font.family: popup.host.family; font.pixelSize: 14; font.weight: Font.DemiBold }
                    Text { width: parent.width; visible: text !== ""; text: popup.subtitle; color: popup.secondary; font.family: popup.host.family; font.pixelSize: 11; wrapMode: Text.WordWrap }
                }
                MouseArea {
                    objectName: popup.objectName + "DragHandle"
                    anchors.fill: parent; hoverEnabled: true; preventStealing: true
                    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    onPressed: mouse => {
                        popup.pressPosition = mapToItem(popup.parent, mouse.x, mouse.y);
                        popup.dragOrigin = Qt.point(popup.x, popup.y);
                    }
                    onPositionChanged: mouse => { if (pressed) popup.movePanel(mapToItem(popup.parent, mouse.x, mouse.y)); }
                    onReleased: popup.releasePanel()
                    onCanceled: popup.releasePanel()
                }
            }
            Column { id: fields; width: parent.width; spacing: 8 }
            Rectangle { width: parent.width; height: 1; color: popup.dark ? "#20FFFFFF" : "#18000000" }
            Row {
                anchors.right: parent.right; spacing: 8
                NotchAction { text: "Cancel"; visible: popup.showCancel; objectName: popup.objectName + "Cancel"; family: popup.host.family; ink: popup.foreground; fill: popup.dark ? "#15FFFFFF" : "#10000000"; onClicked: popup.close() }
                NotchAction { text: popup.acceptText; objectName: popup.objectName + "Save"; family: popup.host.family; ink: "white"; fill: "#087EF5"; enabled: popup.acceptable; onClicked: popup.saveRequested() }
            }
        }
    }
    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: popup.host.reducedMotion ? 0 : 130 }
        }
    }
    exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: popup.host.reducedMotion ? 0 : 100 } }
}
