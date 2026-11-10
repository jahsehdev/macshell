pragma ComponentBehavior: Bound
import QtQuick
import "NotchGeometry.js" as Geometry
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Shapes as Shapes
import "Common" as Common
import "DynamicNotchState.js" as State
import "NotchShape.js" as Shape

Item {
    id: notch
    required property var bar
    property var clock: bar && bar.hub ? bar.hub.clock : null
    property real screenWidth: parent ? parent.width : 1920
    property bool available: true
    property bool pinned: false
    property bool hovering: hover.hovered
    readonly property point hoverPosition: hover.point.position
    property bool previewing: false
    property string selected: ""
    property string heldFeedback: ""
    readonly property bool notchOsdVisible:!!bar && bar.osdVisible && bar.osdKind!=="volume"
    property bool chargingFeedback: false
    property bool focusDecisionOpen: false
    property bool calendarExpanded: false
    readonly property string pomodoroLayout: focusDecisionOpen ? "decision" : tools && tools.pomodoro.state !== "idle" ? "active" : "setup"
    readonly property real pomodoroWidth: pomodoroLayout === "decision" ? 640 : pomodoroLayout === "active" ? 480 : 520
    property Item backdrop: null
    property point backdropPosition: Qt.point(x, y)
    property size screenSize: Qt.size(screenWidth, 1080)
    property url wallpaperUrl: ""
    readonly property bool glassRequested: !!bar && bar.notchStyle === "glass" && !bar.reduceTransparency
    // Share Appearance's material tuning while the lens follows the notch's own contour.
    readonly property var glassSettings: bar && bar.hub ? bar.hub.dock || null : null
    readonly property real glassOpacity: Common.DesktopPreferences.glassOpacity(Common.GlassMaterial.baseOpacity)
    readonly property real glassBlurRadius: bar && bar.reduceTransparency ? 0 : Common.GlassMaterial.surfaceBlur
    readonly property real glassLiquid: Common.DesktopPreferences.glassLiquid(Common.GlassMaterial.baseLiquid)
    readonly property real glassRim: Common.DesktopPreferences.glassRim(Common.GlassMaterial.baseRim)
    readonly property real glassGrain: Common.DesktopPreferences.glassGrain(Common.GlassMaterial.baseGrain)
    readonly property bool glassNeeded: available && glassRequested && shapeMix > 0.001
    property int tooltipCount: 0
    property var settingsPopup: null
    readonly property bool settingsPopupOpen: !!settingsPopup && settingsPopup.visible
    readonly property rect settingsPopupRect: settingsPopupOpen ? settingsPopup.windowRect : Qt.rect(0, 0, 0, 0)
    readonly property bool settingsBlurNeeded: available && settingsPopupOpen && (!bar || !bar.reduceTransparency) && GraphicsInfo.api !== GraphicsInfo.Software
    readonly property bool tooltipGlassNeeded: available && tooltipCount > 0 && (!bar || !bar.reduceTransparency) && GraphicsInfo.api !== GraphicsInfo.Software
    readonly property bool backdropNeeded: glassNeeded || tooltipGlassNeeded || settingsBlurNeeded
    // This backend can render packaged shaders while their status still says
    // Uncompiled. Only an actual failure should restore the opaque fallback.
    readonly property bool glassRendered: glassLayer.item !== null && !glassLayer.item.failed
    readonly property bool reducedMotion: bar ? bar.reduceMotion : false
    readonly property string mode: bar ? bar.notchMode : "attached"
    readonly property real uiScale: bar ? bar.notchScale : 1
    readonly property real cornerRadius: Geometry.panelRadius
    readonly property real cornerScale: fullMetrics.scale
    readonly property real contentPadding: Geometry.padding
    readonly property real contentInset: Geometry.inset(mode,wideShape)
    readonly property string family: bar ? bar.fontFamily : "sans-serif"
    readonly property var player: bar ? bar.player : null
    readonly property var tools: bar && bar.notchService ? bar.notchService : null
    readonly property var downloadsService:bar && bar.downloadsService?bar.downloadsService:null
    readonly property bool downloadsActive:!!downloadsService && downloadsService.active
    readonly property bool downloadsFeedback:downloadsActive && downloadsService.feedback
    readonly property var recordingService:bar && bar.recordingService?bar.recordingService:null
    readonly property var recordingResult:recordingService?recordingService.result:null
    readonly property bool recordingPending:!!bar && (!!bar.recRun && !bar.recording || !!recordingService && recordingService.inspecting)
    readonly property bool recordingFeedback:!!recordingResult || !!recordingService && recordingService.error!==""
    readonly property bool recordingActive:!!bar && bar.recording || recordingPending || recordingFeedback
    readonly property string recordingStage:recordingResult?"result":recordingPending?"saving":recordingFeedback?"error":"live"
    readonly property bool downloadsLeading:downloadsActive && !recordingActive && !notchOsdVisible && !(heldFeedback!=="" && heldFeedback!=="volume") && !chargingFeedback && !deviceFeedbackActive && !(clock && clock.ringing)
    readonly property bool deviceFeedbackActive: available && !!tools && tools.deviceEvent !== "" && !recordingActive && !notchOsdVisible && !(clock && clock.ringing)
    readonly property bool deviceFeedbackExpanded: deviceFeedbackActive && (tools.deviceEvent!=="bluetooth" || tools.deviceEventExpanded)
    readonly property bool idleEyesEnabled: !bar || bar.notchIdleEyes !== false
    readonly property bool musicActive: !!player && (player.isPlaying || expanded || musicView.keepCompact)
    readonly property bool timerActive: !!clock && (clock.timerActive || !!clock.ringing)
    readonly property var activities: {
        const list = State.activities(recordingActive, timerActive, musicActive, !tools && bar && bar.charging);
        if (tools && tools.pomodoroActive && !tools.pomodoroDismissed) list.splice((bar && bar.recording ? 1 : 0) + (timerActive ? 1 : 0), 0, "pomodoro");
        if(downloadsActive)list.splice(recordingActive?1:0,0,"downloads");
        return list;
    }
    readonly property var navigationPages: {
        if (!tools) return activities;
        const list = tools.state.menus.slice();
        for (const page of activities) if ((page === "timer" || page === "recording" || page === "downloads") && list.indexOf(page) < 0) list.push(page);
        return list;
    }
    readonly property string liveActivity: State.selectActivity(activities, selected,
        notchOsdVisible ? bar.osdKind : expanded && heldFeedback !== "" && heldFeedback!=="volume" ? heldFeedback : deviceFeedbackActive && tools ? tools.deviceEvent : chargingFeedback ? "charging" : "", clock && !!clock.ringing)
    readonly property string requestedActivity: {
        if(recordingActive && !notchOsdVisible && !deviceFeedbackActive && !(clock && clock.ringing))return "recording";
        if(downloadsLeading)return "downloads";
        if (!tools || !expanded || notchOsdVisible || (heldFeedback !== "" && heldFeedback!=="volume") || deviceFeedbackActive || chargingFeedback || (clock && !!clock.ringing)) return liveActivity;
        if (selected !== "" && navigationPages.indexOf(selected) >= 0) return selected;
        return navigationPages.indexOf(tools.state.page) >= 0 ? tools.state.page : navigationPages[0] || "idle";
    }
    // Keep the old page mounted until it has faded out. Only then replace its
    // contents, so headers, controls and the page body move as one surface.
    property string activity: "idle"
    property bool pageReady: false
    property real pageOpacity: 1
    property real pageOffset: 0
    property int pageDirection: 1
    property var pendingPageAction:null
    readonly property bool pageSwitching: pageExit.running || pageEnter.running
    onRequestedActivityChanged: changeActivity()
    onReducedMotionChanged: if (pageReady && reducedMotion) settlePage()
    Component.onCompleted: { pageReady = true; settlePage(); syncRotation(); }
    Component.onDestruction: detachRotation()
    property var rotationOwner:null
    property bool rotationCounted:false
    property bool rotationHoldCounted:false
    readonly property bool rotationClientActive:available && expanded && !!tools
    readonly property bool rotationClientHold:rotationClientActive && (interacting || pageSwitching)
    onRotationClientActiveChanged:syncRotation()
    onRotationClientHoldChanged:syncRotation()
    onToolsChanged:syncRotation()
    onActivityChanged:if(activity!=="pomodoro")focusDecisionOpen=false
    function detachRotation() {
        if(rotationOwner) {
            if(rotationCounted)rotationOwner.rotationClients=Math.max(0,rotationOwner.rotationClients-1);
            if(rotationHoldCounted)rotationOwner.rotationHolds=Math.max(0,rotationOwner.rotationHolds-1);
        }
        rotationOwner=null;rotationCounted=false;rotationHoldCounted=false;
    }
    function syncRotation() {
        if(rotationOwner!==tools){detachRotation();rotationOwner=tools;}
        if(!rotationOwner)return;
        const active=rotationClientActive,hold=rotationClientHold;
        if(active!==rotationCounted){rotationOwner.rotationClients=Math.max(0,rotationOwner.rotationClients+(active?1:-1));rotationCounted=active;}
        if(hold!==rotationHoldCounted){rotationOwner.rotationHolds=Math.max(0,rotationOwner.rotationHolds+(hold?1:-1));rotationHoldCounted=hold;}
    }
    readonly property bool dashboardPage: !!tools && ["pomodoro","water","shelf","todo","calendar","weather","stats","bluetooth","charging"].indexOf(activity) >= 0
    readonly property bool wideShape: activity === "music" || activity === "recording" || activity === "downloads" || (dashboardPage && activity !== "charging")
    readonly property bool interacting: focusDecisionOpen || settingsPopupOpen || shelfDrop.containsDrag || (!!tools && tools.dialogOpen) || (!!pagesView.item && pagesView.item.interacting)
    readonly property bool shelfDragging: shelfDrop.containsDrag
    property real lastPageWheel: 0
    readonly property bool expanded: pinned || previewing || deviceFeedbackExpanded || recordingFeedback || (downloadsFeedback && downloadsLeading)
    readonly property bool hasActivity: activity !== "idle"
    readonly property bool lyricsOpen: expanded && activity === "music" && musicView.lyricsOpen
    readonly property bool mediaSideOpen: expanded && activity === "music" && musicView.sideOpen
    readonly property var metrics: State.dimensions(mode, expanded, hasActivity, bar ? bar.barHeight : 28, screenWidth, uiScale, activity === "music", mediaSideOpen, (dashboardPage || activity === "recording" || activity === "downloads") ? activity : "", pomodoroLayout, musicView.lyricsOpen, recordingStage, calendarExpanded)
    readonly property var fullMetrics: State.dimensions(mode, true, hasActivity, bar ? bar.barHeight : 28, screenWidth, uiScale, activity === "music", mediaSideOpen, (dashboardPage || activity === "recording" || activity === "downloads") ? activity : "", pomodoroLayout, musicView.lyricsOpen, recordingStage, calendarExpanded)
    // Shape and contents have separate timing: the surface leads, then the
    // contents settle into it. Keep the top edge anchored throughout.
    property real shapeProgress: expanded ? 1 : 0
    readonly property real shapeMix: Math.max(0, Math.min(1, shapeProgress))
    readonly property real revealProgress: {
        const t = Math.max(0, Math.min(1, (shapeMix - 0.40) / 0.55));
        return t * t * (3 - 2 * t);
    }
    readonly property color highlight: activity === "recording" || activity === "pomodoro" ? "#FF5B61" : activity === "timer" ? "#FFB340" : "#8FE5AC"
    readonly property string title: activity === "music" ? (player ? player.trackTitle || "Now Playing" : "Music")
        : activity === "stats" ? "System Stats"
        : activity === "pomodoro" ? "Pomodoro"
        : activity === "timer" ? (clock.ringing ? (clock.ringing.kind === "alarm" ? (clock.ringing.label || "Alarm") : "Timer finished") : (clock.timer.label || "Timer"))
        : activity === "recording" ? "Screen Recording"
        : activity === "charging" ? "Charging"
        : activity === "bluetooth" ? (tools && tools.feedbackDevice ? tools.feedbackDevice.name : "Bluetooth connected")
        : activity === "brightness" ? "Brightness" : "Dynamic Notch"
    readonly property string detail: activity === "music" ? (player ? player.trackArtist || player.identity || "Media player" : "Play a song to get started")
        : activity === "pomodoro" && tools ? (tools.pomodoro.state === "finished" ? "Done" : format(Math.ceil(tools.pomodoroLeft / 1000)))
        : activity === "timer" ? (clock.ringing ? "Ready when you are" : clock.fmtDur(clock.timerLeft(), false))
        : activity === "recording" ? bar.recTime()
        : activity === "charging" ? bar.batPct + "%"
        : activity === "bluetooth" ? "Device connected"
        : activity === "brightness" ? Math.round(bar.brightness * 100) + "%"
        : "Music, timers and live activities"
    signal opened()

    objectName: "dynamicNotch"
    width: metrics.width
    height: metrics.height
    y: metrics.top
    visible: available
    clip: true
    Connections {
        target:notch.recordingService;ignoreUnknownSignals:true
        function onDismissed(){if(notch.activity==="recording" && !(notch.bar && notch.bar.recording))notch.close();}
    }
    Connections {
        target:notch.downloadsService;ignoreUnknownSignals:true
        function onDismissed(){if(notch.activity==="downloads")notch.close();}
    }
    onAvailableChanged: if (!available) close()
    onModeChanged: close()
    onHoveringChanged: {
        if (hovering) { leaveDelay.stop(); hoverDelay.restart(); }
        else { hoverDelay.stop(); leaveDelay.restart(); }
    }
    onInteractingChanged: if (!interacting && expanded && !hovering) leaveDelay.restart()
    onExpandedChanged: {
        if (expanded) { if (notchOsdVisible) heldFeedback = bar.osdKind; opened(); }
        else heldFeedback = "";
        if (pageReady) settlePage();
    }
    function settlePage() {
        if (pageReady) { pageExit.stop(); pageEnter.stop(); }
        if(pendingPageAction){const action=pendingPageAction;pendingPageAction=null;action();}
        activity = requestedActivity; pageOpacity = 1; pageOffset = 0;
    }
    function transitionAction(action) {
        if(reducedMotion || !expanded || revealProgress<0.98 || !available){action();return;}
        pendingPageAction=action;pageDirection=1;pageEnter.stop();
        if(!pageExit.running)pageExit.restart();
    }
    function changeActivity() {
        if (!pageReady || reducedMotion || !expanded || revealProgress < 0.98 || !available) { settlePage(); return; }
        if (requestedActivity === activity) {
            if (pageExit.running) { pageExit.stop(); pageEnter.restart(); }
            return;
        }
        if (settingsPopup) settingsPopup.close();
        const from = navigationPages.indexOf(activity), to = navigationPages.indexOf(requestedActivity);
        pageDirection = from >= 0 && to >= 0 && to < from ? -1 : 1;
        pageEnter.stop();
        if (!pageExit.running) pageExit.restart();
    }
    SequentialAnimation {
        id: pageExit
        ParallelAnimation {
            NumberAnimation { target: notch; property: "pageOpacity"; to: 0; duration: 100; easing.type: Easing.InOutQuad }
            NumberAnimation { target: notch; property: "pageOffset"; to: -8 * notch.pageDirection; duration: 100; easing.type: Easing.InOutQuad }
        }
        ScriptAction { script: {
            if(notch.pendingPageAction){const action=notch.pendingPageAction;notch.pendingPageAction=null;action();}
            notch.activity = notch.requestedActivity;
            notch.pageOffset = 10 * notch.pageDirection;
            pageEnter.restart();
        } }
    }
    ParallelAnimation {
        id: pageEnter
        NumberAnimation { target: notch; property: "pageOpacity"; to: 1; duration: 240; easing.type: Easing.OutCubic }
        NumberAnimation { target: notch; property: "pageOffset"; to: 0; duration: 300; easing.type: Easing.OutQuint }
    }
    function close() { if (settingsPopup) settingsPopup.close(); hoverDelay.stop(); leaveDelay.stop(); pinned = false; previewing = false; selected = ""; focusDecisionOpen=false; }
    function toggle() {
        hoverDelay.stop();
        if(downloadsFeedback && downloadsService && activity==="downloads"){downloadsService.dismiss();close();return;}
        if(recordingFeedback && recordingService){recordingService.dismiss();close();return;}
        if (deviceFeedbackActive) { if(activity==="bluetooth" && !expanded)tools.expandDeviceEvent();else tools.dismissDeviceEvent(); return; }
        pinned = !pinned; previewing = pinned;
    }
    function selectPage(page) {
        if(page === "pomodoro" && tools) tools.pomodoroDismissed=false;
        if (tools && tools.state.menus.indexOf(page) >= 0) { tools.setPage(page); selected = ""; }
        else selected = page;
        heldFeedback = ""; chargingFeedback = false;
        if (tools) tools.dismissDeviceEvent();
    }
    function stepPage(direction) {
        if (!navigationPages.length) return;
        const at = Math.max(0, navigationPages.indexOf(requestedActivity));
        selectPage(navigationPages[(at + direction + navigationPages.length) % navigationPages.length]);
    }
    function format(seconds) { var s = Math.max(0, Math.floor(seconds)); return Math.floor(s / 60) + ":" + (s % 60 < 10 ? "0" : "") + s % 60; }
    Behavior on width {
        enabled: !notch.reducedMotion
        NumberAnimation {
            duration: notch.pageSwitching ? 360 : 520
            easing.type: notch.pageSwitching ? Easing.InOutCubic : Easing.OutBack
            easing.overshoot: 0.32
        }
    }
    Behavior on height {
        enabled: !notch.reducedMotion
        NumberAnimation {
            duration: notch.pageSwitching ? 360 : 580
            easing.type: notch.pageSwitching ? Easing.InOutCubic : Easing.OutBack
            easing.overshoot: 0.42
        }
    }
    Behavior on shapeProgress {
        enabled: !notch.reducedMotion
        NumberAnimation { duration: 480; easing.type: Easing.OutCubic }
    }
    Behavior on y { NumberAnimation { duration: notch.reducedMotion ? 0 : 220; easing.type: Easing.OutCubic } }
    property color washMiddle: activity === "music" ? "#101214" : dashboardPage && activity === "shelf" ? "#101A32" : activity === "recording" ? "#111117" : "#050505"
    property color washBottom: activity === "music" ? "#44484B" : dashboardPage && activity === "shelf" ? "#24304F" : activity === "recording" ? "#25232F" : "#050505"
    Behavior on washMiddle { enabled: !notch.reducedMotion; ColorAnimation { duration: 360; easing.type: Easing.OutCubic } }
    Behavior on washBottom { enabled: !notch.reducedMotion; ColorAnimation { duration: 360; easing.type: Easing.OutCubic } }
    Timer { id: hoverDelay; interval: 260; onTriggered: if (notch.available) {notch.previewing = true; if(notch.deviceFeedbackActive && notch.activity==="bluetooth")notch.tools.expandDeviceEvent();} }
    Timer { id: leaveDelay; interval: 650; onTriggered: if (!notch.interacting) { notch.pinned = false; notch.previewing = false; } }
    Timer { id: chargeDelay; interval: 3500; onTriggered: notch.chargingFeedback = false }
    Connections {
        target: notch.bar
        function onChargingChanged() {
            if (!notch.tools && notch.bar.charging && notch.bar.osdReady) { notch.chargingFeedback = true; chargeDelay.restart(); }
        }
        function onOsdVisibleChanged() { if (notch.notchOsdVisible && notch.expanded) notch.heldFeedback = notch.bar.osdKind; }
        function onOsdKindChanged() { if (notch.notchOsdVisible && notch.expanded) notch.heldFeedback = notch.bar.osdKind; }
    }

    Shapes.Shape {
        id:contentMask
        objectName:"notchContentMask"
        anchors.fill:parent;visible:false
        layer.enabled:GraphicsInfo.api!==GraphicsInfo.Software
        preferredRendererType:Shapes.Shape.CurveRenderer
        Shapes.ShapePath {
            fillColor:"white";strokeWidth:0;strokeColor:"transparent"
            PathSvg {path:Shape.path(contentMask.width,contentMask.height,notch.mode,notch.shapeMix,notch.wideShape,notch.cornerScale)}
        }
    }
    Item {
        id:clippedSurface
        objectName:"notchClippedSurface"
        anchors.fill:parent;clip:true
        // The outer Item clip is rectangular. Mask every painted child with
        // the animated notch silhouette, including attached-mode wings.
        layer.enabled:GraphicsInfo.api!==GraphicsInfo.Software
        layer.effect:MultiEffect {maskEnabled:true;maskSource:contentMask;autoPaddingEnabled:false}
    // The lens supplies refraction; the wash below preserves the semi-glass notch.
    Loader {
        id: glassLayer
        objectName: "notchGlassLayer"
        anchors.fill: parent
        active: notch.glassNeeded && GraphicsInfo.api !== GraphicsInfo.Software
        sourceComponent: NotchGlass { host: notch }
    }

    Rectangle {
        objectName: "notchGlassBlackWash"
        anchors.fill: parent
        visible: notch.glassRendered
        // Keep the camera seam opaque, revealing glass only toward the bottom.
        // The enclosing surface mask also clips the wash to attached shoulders.
        gradient: Gradient {
            GradientStop { position: 0; color: "#050505" }
            GradientStop { position: 0.32; color: "#050505" }
            GradientStop { position: 0.72; color: Qt.rgba(5 / 255, 5 / 255, 5 / 255, 1 - 0.28 * notch.shapeMix) }
            GradientStop { position: 1; color: Qt.rgba(5 / 255, 5 / 255, 5 / 255, 1 - 0.5 * notch.shapeMix) }
        }
    }

    Canvas {
        id: surface
        visible: !notch.glassRendered
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Connections {
            target: notch
            function onModeChanged() { surface.requestPaint(); }
            function onExpandedChanged() { surface.requestPaint(); }
            function onActivityChanged() { surface.requestPaint(); }
            function onLyricsOpenChanged() { surface.requestPaint(); }
            function onShapeProgressChanged() { surface.requestPaint(); }
            function onCornerScaleChanged() { surface.requestPaint(); }
            function onWashMiddleChanged() { surface.requestPaint(); }
            function onWashBottomChanged() { surface.requestPaint(); }
        }
        onPaint: {
            var c = getContext("2d"), w = width, h = height;
            c.reset(); c.fillStyle = "#050505"; c.beginPath();
            const wash = c.createLinearGradient(0, 0, 0, h);
            wash.addColorStop(0, "#050505"); wash.addColorStop(0.48, "#050505");
            wash.addColorStop(0.74, notch.washMiddle); wash.addColorStop(1, notch.washBottom);
            c.fillStyle = wash;
            Shape.trace(c, w, h, notch.mode, notch.shapeMix, notch.wideShape, notch.cornerScale);
            c.closePath(); c.fill();
        }
    }
    // Keep calendar selections, device cards and timer controls legible over bright windows.
    Rectangle {
        objectName: "notchPomodoroContrast"
        anchors.fill: parent
        visible: notch.glassRendered && notch.expanded && (notch.activity === "bluetooth" || notch.activity === "calendar" || (notch.activity === "pomodoro" && notch.pomodoroLayout === "setup"))
        opacity: notch.revealProgress
        gradient: Gradient {
            GradientStop { position: 0; color: "#2006070B" }
            GradientStop { position: 0.5; color: "#6606070B" }
            GradientStop { position: 1; color: "#B006070B" }
        }
    }
    HoverHandler { id: hover }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton
        onClicked: notch.toggle()
        onWheel: event => {
            if (notch.expanded && notch.tools && Math.abs(event.angleDelta.x) > Math.abs(event.angleDelta.y)) {
                if (Date.now() - notch.lastPageWheel > 280) { notch.stepPage(event.angleDelta.x > 0 ? -1 : 1); notch.lastPageWheel = Date.now(); }
                event.accepted = true;
            } else {
                // Unhandled media scrolling stays local and never changes
                // volume or leaks into an application behind this overlay.
                event.accepted = notch.activity === "music";
            }
        }
        Accessible.role: Accessible.Button
        Accessible.name: "Dynamic Notch: " + notch.title + ", " + notch.detail
        Accessible.onPressAction: notch.toggle()
    }

    Row {
        id: compact
        readonly property bool pomodoro: notch.activity === "pomodoro"
        readonly property real detailWidth: pomodoro ? 52 : 38
        x: 24; anchors.verticalCenter: parent.verticalCenter
        width: (parent.width - 48) / scale; spacing: 10
        scale: Math.min(1, Math.max(0.1, (notch.height - 4) / 24))
        transformOrigin: Item.Left
        visible: opacity > 0.01
        opacity: notch.hasActivity && notch.activity !== "music" && notch.activity !== "pomodoro" && notch.activity !== "recording" && notch.activity !== "downloads" && notch.activity !== "bluetooth" && !notch.expanded ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: notch.reducedMotion ? 0 : 100 } }
        Rectangle {
            width: 24; height: 24; radius: 6; color: compact.pomodoro ? "transparent" : "#181818"
            NotchIcon { anchors.centerIn: parent; width: compact.pomodoro ? 20 : 18; height: width; kind: notch.activity; ink: notch.highlight; strokeWidth: compact.pomodoro ? 2.5 : 1.8 }
        }
        Text { width: compact.width - 44 - compact.detailWidth; height: 24; verticalAlignment: Text.AlignVCenter; text: notch.title; elide: Text.ElideRight; color: "#F4F4F5"; font.family: notch.family; font.pixelSize: 11 }
        Text { width: compact.detailWidth; height: 24; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight; text: notch.detail; color: notch.highlight; font.family: notch.family; font.pixelSize: compact.pomodoro ? 15 : 11; font.weight: compact.pomodoro ? Font.Bold : Font.Normal }
    }

    Loader {
        anchors.fill:parent
        active:!!notch.tools && notch.activity==="pomodoro" && !notch.expanded
        sourceComponent:NotchPomodoroCompact { host:notch }
    }

    Loader {
        anchors.fill:parent
        active:!!notch.tools && notch.activity==="bluetooth" && !notch.expanded
        opacity:notch.pageOpacity
        sourceComponent:NotchDeviceCompact {host:notch}
    }

    component NotchButton: Button {
        id: control
        property color ink: "#F5F5F7"
        property bool prominent: false
        property string symbol: ""
        implicitWidth: 38; implicitHeight: 32
        opacity: enabled ? 1 : 0.28
        font.family: notch.family; font.pixelSize: 15
        background: Rectangle {
            radius: Geometry.radius(Geometry.controlRadius,width,height)
            color: control.down ? "#18FFFFFF" : control.hovered ? "#0CFFFFFF" : control.prominent ? "#08FFFFFF" : "transparent"
            Behavior on color { ColorAnimation { duration: notch.reducedMotion ? 0 : 120 } }
        }
        HoverHandler { enabled: control.enabled; cursorShape: Qt.PointingHandCursor }
        contentItem: Item {
            NotchIcon { anchors.centerIn: parent; width: 17; height: 17; visible: control.symbol !== ""; kind: control.symbol; ink: control.ink }
            Text { anchors.fill: parent; visible: control.symbol === ""; text: control.text; color: control.ink; font: control.font; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
        }
        Accessible.name: text
    }
    component NotchSlider: Slider {
        id: slider
        implicitHeight: 20
        from: 0; to: 1
        background: Rectangle { x: slider.leftPadding; y: (slider.height - height) / 2; width: slider.availableWidth; height: 4; radius: 2; color: "#343434"
            Rectangle { width: slider.visualPosition * parent.width; height: parent.height; radius: 2; color: notch.highlight }
        }
        handle: Rectangle { x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width); y: (slider.height - height) / 2; width: 10; height: 10; radius: 5; color: "#F7F7F7"; visible: slider.hovered || slider.pressed }
    }

    NotchIdle { anchors.fill: parent; host: notch }

    Item {
        id: pageContent
        objectName: "notchPageContent"
        anchors.fill: parent
        opacity: notch.expanded ? notch.pageOpacity : 1
        transform: Translate { x: notch.expanded ? notch.pageOffset * notch.uiScale : 0 }
        // Playback uses rounded local icons; Audio output uses System Settings controls.
        DynamicNotchMusic {
            id: musicView
            anchors.fill: parent
            host: notch
            visible: notch.activity === "music"
        }
        DynamicNotchDownloads {
            anchors.fill:parent;host:notch;visible:notch.activity==="downloads"
        }
        DynamicNotchRecording {
            id:recordingView
            anchors.fill:parent;host:notch;visible:notch.activity==="recording"
        }
        // Pomodoro switches between a duration ruler and a short countdown with reduced top spacing; tool pages share rounded controls.
        Loader {
            id: pagesView
            anchors.fill: parent
            active: notch.dashboardPage
            sourceComponent: NotchPages { host: notch; tools: notch.tools }
        }

        Item {
            id: content
            objectName:"notchFallbackContent"
            x: (notch.width - notch.fullMetrics.width) / 2 + (notch.contentInset+Geometry.navigationGutter) * notch.uiScale
            y: (17 - 6 * (1 - notch.revealProgress)) * notch.uiScale
            width: notch.fullMetrics.width / notch.uiScale - 2 * (notch.contentInset+Geometry.navigationGutter); height: notch.fullMetrics.height / notch.uiScale - 30
            scale: notch.uiScale
            transformOrigin: Item.TopLeft
            // Activity changes to idle before the closing shape has shrunk.
            // Never reveal the generic placeholder during that transition.
            readonly property bool hasContent:notch.expanded && notch.activity!=="idle" && notch.activity!=="music" && notch.activity!=="recording" && notch.activity!=="downloads" && !notch.dashboardPage
            opacity:hasContent?notch.revealProgress:0
            visible:hasContent && opacity>0.01
            enabled:hasContent
            Row {
                id: tabs
                spacing: 4; height: 26; visible: !notch.tools
                Repeater {
                    model: notch.activities
                    NotchButton {
                        required property string modelData
                        implicitWidth: 34; implicitHeight: 24
                        symbol: modelData; ink: notch.activity === modelData ? notch.highlight : "#929298"
                        prominent: notch.activity === modelData
                        Accessible.name: "Show " + modelData
                        onClicked: { notch.selected = modelData; notch.heldFeedback = ""; notch.chargingFeedback = false; }
                    }
                }
                Text { visible: notch.activities.length === 0; text: "LIVE ACTIVITIES"; color: "#77777F"; font.family: notch.family; font.pixelSize: 9; font.letterSpacing: 1.5; height: 24; verticalAlignment: Text.AlignVCenter }
            }
            NotchButton { anchors.right: parent.right; implicitWidth: 26; implicitHeight: 24; symbol: "close"; ink: "#95959D"; Accessible.name: "Close Dynamic Notch"; onClicked: notch.close() }
            Row {
                y: 37; width: parent.width; spacing: 12
                Rectangle {
                    width: 46; height: 46; radius: Geometry.controlRadius; color: "#1C1C1E"
                    Image { id: artwork; anchors.fill: parent; source: notch.activity === "music" && notch.player ? notch.player.trackArtUrl : ""; sourceSize.width: 128; sourceSize.height: 128; fillMode: Image.PreserveAspectCrop; visible: status === Image.Ready }
                    NotchIcon { anchors.centerIn: parent; visible: !artwork.visible; width: 27; height: 27; kind: notch.activity; ink: notch.highlight }
                }
                Column {
                    width: parent.width - 58; spacing: 5; anchors.verticalCenter: parent.verticalCenter
                    Text { width: parent.width; text: notch.title; color: "#FAFAFC"; font.family: notch.family; font.pixelSize: 13; font.weight: Font.DemiBold; elide: Text.ElideRight }
                    Text { width: parent.width; text: notch.detail; color: notch.activity === "timer" || notch.activity === "recording" ? notch.highlight : "#94949C"; font.family: notch.family; font.pixelSize: 11; elide: Text.ElideRight }
                }
            }

            Row {
                visible: notch.activity === "timer" && !!notch.clock
                y: 107; spacing: 10
                NotchButton {
                    implicitWidth: 100; prominent: true
                    text: notch.clock && notch.clock.ringing ? "Dismiss" : notch.clock && notch.clock.timer.state === "paused" ? "Resume" : "Pause"
                    onClicked: {
                        if (notch.clock.ringing) notch.clock.stopRing();
                        else if (notch.clock.timer.state === "paused") notch.clock.resumeTimer();
                        else notch.clock.pauseTimer();
                    }
                }
                NotchButton { implicitWidth: 82; text: "Cancel"; enabled: notch.clock && notch.clock.timerActive; onClicked: notch.clock.cancelTimer() }
                NotchButton { implicitWidth: 55; text: "Clock"; onClicked: notch.clock.open("timers") }
            }
            Column {
                visible: notch.activity === "brightness" || notch.activity === "charging"
                y: 103; width: parent.width; spacing: 8
                NotchSlider {
                    width: parent.width
                    enabled: notch.activity !== "charging"
                    value: notch.activity === "charging" ? notch.bar.batPct / 100 : notch.bar.brightness
                    Accessible.name: notch.title
                    onMoved: notch.bar.setBrightness(value)
                }
                Text { text: notch.activity === "charging" ? "Connected to power" : "Adjust " + notch.title.toLowerCase(); color: "#77777F"; font.family: notch.family; font.pixelSize: 10 }
            }
        }
    }
    MouseArea {
        objectName: "notchPageTransitionShield"
        anchors.fill: parent
        visible: notch.pageSwitching
        acceptedButtons: Qt.AllButtons
        cursorShape: Qt.PointingHandCursor
        onWheel: event => event.accepted = true
    }
    NotchNavigation { anchors.fill: parent; host: notch; visible: !!notch.tools && notch.activity!=="recording" && notch.activity!=="downloads" && !notch.deviceFeedbackActive && notch.expanded && notch.revealProgress > 0.001 && notch.navigationPages.length > 1 }
    DropArea {
        id: shelfDrop
        anchors.fill: parent
        enabled: !!notch.tools && notch.tools.state.menus.indexOf("shelf") >= 0
        onEntered: drag => {
            drag.accepted = drag.hasUrls;
            if (!drag.hasUrls) return;
            notch.selectPage("shelf"); notch.pinned = true; notch.previewing = true;
            hoverDelay.stop(); leaveDelay.stop();
        }
        onDropped: drop => {
            if (!drop.hasUrls) return;
            notch.tools.addShelf(drop.urls); drop.accept(Qt.CopyAction);
        }
    }
    } // clippedSurface
}
