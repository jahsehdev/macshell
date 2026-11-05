pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls

// A popup keeps the Dock label outside the notch's clipping and scaled layouts.
ToolTip {
    id: popup
    objectName: "notchTooltip"
    required property Item control
    property bool wanted: true
    // Share the notch's enabled hover observer. Disabled playback controls
    // still show labels, without creating an observer for every button.
    readonly property bool hovered: !!notchHost && notchHost.hovering && !!control && control.contains(
        control.mapFromItem(notchHost, notchHost.hoverPosition.x, notchHost.hoverPosition.y))
    readonly property var notchHost: {
        let item = control;
        while (item) {
            if (item.objectName === "dynamicNotch") return item;
            item = item.parent;
        }
        return null;
    }
    readonly property var dock: notchHost && notchHost.bar && notchHost.bar.hub ? notchHost.bar.hub.dock || null : null
    readonly property bool reducedMotion: !!notchHost && notchHost.reducedMotion
    readonly property bool reduceTransparency: !!notchHost && !!notchHost.bar && notchHost.bar.reduceTransparency
    property var countedHost: null
    parent: control ? control.Window.contentItem : null
    readonly property point anchorPoint: {
        // mapToItem does not itself subscribe to ancestor geometry changes.
        let item = control;
        while (item && item !== parent) {
            item.x; item.y; item.width; item.height; item.scale; item.rotation;
            item = item.parent;
        }
        if (notchHost) { notchHost.shapeProgress; notchHost.uiScale; notchHost.pageOffset; }
        return control && parent ? control.mapToItem(parent, control.width / 2, 0) : Qt.point(0,0);
    }
    readonly property point bottomAnchor: {
        anchorPoint;
        return control && parent ? control.mapToItem(parent, control.width / 2, control.height) : Qt.point(0,0);
    }
    readonly property bool below: anchorPoint.y - height - 6 < 8
        && !!parent && parent.height - bottomAnchor.y >= anchorPoint.y
    x: Math.max(8, Math.min(parent ? parent.width - width - 8 : anchorPoint.x, anchorPoint.x - width / 2))
    y: Math.max(8, Math.min(parent ? parent.height - height - 8 : Infinity,
        below ? bottomAnchor.y + 6 : anchorPoint.y - height - 6))
    visible: wanted && hovered && !!control && control.visible && !!notchHost && notchHost.expanded && notchHost.available
    delay: 700
    timeout: -1
    padding: 0; margins: 8
    implicitWidth: bubble.implicitWidth
    implicitHeight: bubble.implicitHeight
    popupType: Popup.Item
    closePolicy: Popup.NoAutoClose
    focus: false
    transformOrigin: below ? Item.Top : Item.Bottom
    background: null
    function syncDemand() {
        const next = visible ? notchHost : null;
        if (next === countedHost) return;
        if (countedHost) countedHost.tooltipCount = Math.max(0, countedHost.tooltipCount - 1);
        countedHost = next;
        if (countedHost) countedHost.tooltipCount++;
    }
    onVisibleChanged: syncDemand()
    onNotchHostChanged: syncDemand()
    Component.onDestruction: if (countedHost) countedHost.tooltipCount = Math.max(0, countedHost.tooltipCount - 1)
    contentItem: DockTooltip {
        id: bubble
        objectName: "notchTooltipBubble"
        text: popup.text
        maxWidth: Math.max(60, Math.min(320, popup.parent ? popup.parent.width - 16 : 320))
        fontFamily: popup.notchHost ? popup.notchHost.family : "SF Pro Text"
        pointerX: popup.anchorPoint.x - popup.x
        pointerUp: popup.below
        highContrast: true
        liquid: popup.visible && !popup.reduceTransparency && GraphicsInfo.api !== GraphicsInfo.Software
        dark: popup.dock ? popup.dock.dockDark : true
        surfaceOpacity: popup.reduceTransparency ? 1 : popup.dock ? popup.dock.effGlassOpacity : 0.65
        glassBlur: Math.max(12,popup.dock ? popup.dock.effGlassBlur : 5)
        glassLiquid: Math.min(0.65,popup.dock ? popup.dock.effGlassLiquid : 1)
        glassRim: Math.min(0.35,popup.dock ? popup.dock.effGlassRim : 0.45)
        glassGrain: Math.min(0.012,popup.dock ? popup.dock.effGlassGrain : 0.03)
        // Refract the visible notch over the desktop, not the desktop through
        // an opaque notch. The popup lives in the window overlay, so capturing
        // notchHost excludes this tooltip and cannot feed it back into itself.
        backdrop: tooltipBackdrop.item as Item
        backdropOrigin: Qt.point(captureMargin, captureMargin)
        readonly property real captureMargin: 82 // DockTooltip's padding + optical reach
        readonly property point notchOrigin: {
            if (!popup.notchHost) return Qt.point(0,0);
            popup.anchorPoint; popup.x; popup.y; popup.scale;
            const p = bubble.mapToItem(popup.notchHost,0,0);
            return p;
        }
        readonly property size notchExtent: {
            notchOrigin;
            if (!popup.notchHost) return Qt.size(width, height);
            const end = bubble.mapToItem(popup.notchHost, width, height);
            return Qt.size(end.x-notchOrigin.x, end.y-notchOrigin.y);
        }
        Loader {
            id: tooltipBackdrop
            objectName: "notchTooltipBackdrop"
            active: bubble.liquid && !!popup.notchHost
            visible: false
            sourceComponent: Item {
                id: composite
                width: bubble.width + 2*bubble.captureMargin
                height: bubble.height + 2*bubble.captureMargin
                readonly property real scaleX: bubble.notchExtent.width / Math.max(1,bubble.width)
                readonly property real scaleY: bubble.notchExtent.height / Math.max(1,bubble.height)
                readonly property rect notchRect: Qt.rect(
                    bubble.notchOrigin.x-bubble.captureMargin*scaleX,
                    bubble.notchOrigin.y-bubble.captureMargin*scaleY,
                    width*scaleX, height*scaleY)
                ShaderEffectSource {
                    objectName: "notchTooltipDesktopCapture"
                    anchors.fill: parent
                    sourceItem: popup.notchHost ? popup.notchHost.backdrop : null
                    sourceRect: Qt.rect(composite.notchRect.x+popup.notchHost.backdropPosition.x,
                                        composite.notchRect.y+popup.notchHost.backdropPosition.y,
                                        composite.notchRect.width, composite.notchRect.height)
                    hideSource: true; live: true
                }
                ShaderEffectSource {
                    objectName: "notchTooltipSurfaceCapture"
                    anchors.fill: parent
                    sourceItem: popup.notchHost
                    sourceRect: composite.notchRect
                    // Keep the actual notch visible while sampling its surface.
                    hideSource: false; live: true
                }
            }
        }
    }
    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property:"opacity"; from:0; to:1; duration:popup.reducedMotion ? 0 : 120 }
            NumberAnimation { property:"scale"; from:0.96; to:1; duration:popup.reducedMotion ? 0 : 160; easing.type:Easing.OutCubic }
        }
    }
    exit: Transition { NumberAnimation { property:"opacity"; from:1; to:0; duration:popup.reducedMotion ? 0 : 90 } }
}
