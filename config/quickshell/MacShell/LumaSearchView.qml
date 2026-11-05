pragma ComponentBehavior: Bound
import QtQuick

FocusScope {
    id: root
    required property var controller
    property url wallpaper: ""
    property Item backdrop: null
    property size screenSize: Qt.size(1920, 1080)
    property point screenPosition: Qt.point(0, 0)
    property string fontFamily: "sans-serif"
    property real maxBodyHeight: 360
    property bool microphoneAllowed: true
    property bool dictationEnabled: true
    property bool listening: false
    property bool resetting: false
    property bool microphonePrimed: false
    // Personal-context results passed down from the menu's context bridge.
    property var contextResults: []
    property bool contextSearching: false
    signal contextResultActivated(var result)
    property url microphoneBackend: Qt.resolvedUrl("LumaMicrophone.qml")
    property url voiceBackend: Qt.resolvedUrl("LumaVoice.qml")
    readonly property real micVolume: microphone.item ? microphone.item.volume : 0
    readonly property string microphoneError: (voice && voice.error) || (microphone.status === Loader.Error ? "Microphone unavailable." : (microphone.item ? microphone.item.error : ""))
    property real voiceProgress: listening ? 1 : 0
    // Slightly smaller than the old 104 px sphere: the mic orb should sit under
    // the menu bar without crowding it.
    readonly property real voiceDiameter: 88
    readonly property real shrinkProgress: smooth(0, 0.68, voiceProgress)
    readonly property real roundProgress: smooth(0.48, 1, voiceProgress)
    readonly property real voiceReveal: smooth(0.68, 1, voiceProgress)
    readonly property real searchReveal: 1 - smooth(0, 0.24, voiceProgress)
    readonly property bool voiceVisible: listening || voiceProgress > 0.001
    readonly property bool showBody: panel.showBody
    width: 380
    height: Math.max(panel.height, inputGlass.y + inputGlass.height,
                     errorLabel.visible ? errorLabel.y + errorLabel.height : 0)
    signal dismissed()
    signal fullRequested()
    signal settingsRequested()
    function smooth(start, end, value) {
        const t = Math.max(0, Math.min(1, (value - start) / (end - start)));
        return t * t * (3 - 2 * t);
    }
    function focusInput() { if (voiceVisible) forceActiveFocus(); else panel.focusInput(); }
    function resetMessages() {
        resetting = true;
        listening = false;
        voiceProgress = 0;
        voiceProgress = Qt.binding(function() { return root.listening ? 1 : 0; });
        panel.resetMessages();
        resetting = false;
    }
    function toggleMicrophone() {
        if (voice && voice.state === "transcribing") return;
        if (listening) { listening = false; return; }
        panel.resetMessages();
        microphonePrimed = true;
        listening = true;
        forceActiveFocus();
    }
    Behavior on voiceProgress {
        enabled: root.microphoneAllowed && root.visible && !root.resetting
        NumberAnimation { duration: 520; easing.type: Easing.InOutCubic }
    }
    onVoiceVisibleChanged: if (!voiceVisible && microphoneAllowed && visible) Qt.callLater(panel.focusInput)
    onMicrophoneAllowedChanged: if (!microphoneAllowed) listening = false
    onVisibleChanged: if (!visible) listening = false
    Keys.onEscapePressed: event => {
        if (voiceVisible) listening = false;
        else dismissed();
        event.accepted = true;
    }

    readonly property var voice: voiceLoader.item
    Loader {
        id: voiceLoader
        active: root.dictationEnabled && root.microphonePrimed
        source: root.voiceBackend
        onLoaded: item.active = Qt.binding(function() { return root.listening && root.microphoneAllowed && root.visible; })
    }
    Connections {
        target: root.voice
        function onTranscript(text) { root.controller.draft = text; root.listening = false; root.focusInput(); }
        // Dictation is optional: keep the microphone orb open on recognizer
        // failure. microphoneError shows the reason while levels still animate.
    }
    Connections { target: root; function onMicrophoneAllowedChanged() { if (!root.microphoneAllowed && root.voice) root.voice.cancel(); } }
    Loader {
        id: microphone
        active: root.microphonePrimed
        source: root.microphoneBackend
        onLoaded: item.active = Qt.binding(function() { return root.listening && root.microphoneAllowed && root.visible; })
    }

    LumaSearchGlass {
        id: inputGlass
        objectName: "lumaInputGlass"
        // One persistent glass surface: capsule -> short pill -> exact circle.
        width: root.width + (60 - root.width) * root.shrinkProgress + (root.voiceDiameter - 60) * root.roundProgress
        height: 60 + (root.voiceDiameter - 60) * root.roundProgress
        x: (root.width - width) / 2; y: (60 - height) / 2
        radius: height / 2
        // Clear "liquid" glass: a light frost (~20 px) instead of the old
        // double 64 px blur, and a thinner tint so the backdrop (and its
        // warmth) reads through the pill. Photo reference: the search bar
        // that stays glassy rather than frosted.
        tintMix: 0.32 * (1 - root.roundProgress)
        frostAmount: 0.26 * (1 - root.roundProgress)
        // Fade the capsule's exterior rim away as it becomes the voice sphere.
        rimStrength: 0.40 * (1 - root.roundProgress)
        // Keep the blur buffers at a fixed size while the shape morphs.
        captureSize: Qt.size(root.width + 256, root.voiceDiameter + 256)
        wallpaper: root.wallpaper; screenSize: root.screenSize
        backdrop: root.backdrop
        screenPosition: Qt.point(root.screenPosition.x + x, root.screenPosition.y + y)
    }
    Rectangle {
        id: topGradient
        objectName: "lumaTopGradient"
        z: 1
        x: inputGlass.x; y: inputGlass.y
        width: inputGlass.width; height: inputGlass.height
        radius: inputGlass.radius
        opacity: 1 - root.roundProgress
        visible: opacity > 0
        antialiasing: true
        gradient: Gradient {
            GradientStop { position: 0; color: "#fa000000" }
            GradientStop { position: 0.25; color: "#dc000000" }
            GradientStop { position: 0.65; color: "#70000000" }
            GradientStop { position: 1; color: "#08000000" }
        }
    }
    LumaSearchGlass {
        visible: panel.showBody
        y: panel.bodyY; width: parent.width; height: panel.bodyHeight; radius: 22
        // Same clear material as the capsule above.
        tintMix: 0.32; frostAmount: 0.26; rimStrength: 0.40
        wallpaper: root.wallpaper; screenSize: root.screenSize
        backdrop: root.backdrop
        screenPosition: Qt.point(root.screenPosition.x, root.screenPosition.y + y)
    }
    LumaSearchPanel {
        id: panel
        objectName: "lumaSearchControls"
        z: 2
        opacity: root.searchReveal
        visible: opacity > 0.001
        enabled: !root.voiceVisible
        width: parent.width; controller: root.controller
        dark: true; externalSurface: true
        microphoneActive: root.voiceVisible
        fontFamily: root.fontFamily; maxBodyHeight: root.maxBodyHeight
        localResults: root.contextResults
        localSearching: root.contextSearching
        onLocalResultActivated: result => root.contextResultActivated(result)
        onDismissed: root.dismissed()
        onFullRequested: root.fullRequested()
        onSettingsRequested: root.settingsRequested()
        onMicrophoneRequested: root.toggleMicrophone()
    }
    LumaMicOrb {
        id: microphonePane
        objectName: "lumaMicrophonePane"
        z: 3
        width: inputGlass.height; height: width
        x: (root.width - width) / 2; y: (60 - height) / 2
        opacity: root.voiceReveal
        visible: root.voiceVisible
        glassBackground: false // inputGlass becomes this orb's liquid backdrop.
        micVolume: root.micVolume
        animate: root.listening && root.visible
        MouseArea {
            id: orbButton
            objectName: "lumaMicrophoneOrbButton"
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            enabled: root.listening
            containmentMask: QtObject {
                function contains(point: point): bool {
                    const dx = point.x - orbButton.width / 2;
                    const dy = point.y - orbButton.height / 2;
                    return dx * dx + dy * dy <= orbButton.width * orbButton.width / 4;
                }
            }
            onClicked: root.listening = false
            Accessible.role: Accessible.Button
            Accessible.name: "Stop microphone and return to search"
        }
    }
    Text {
        id: errorLabel
        objectName: "lumaMicrophoneStatus"
        z: 3
        x: 16; y: inputGlass.y + inputGlass.height + 12; width: parent.width - 32
        visible: root.listening && root.microphoneError !== ""
        opacity: root.voiceReveal
        text: root.microphoneError
        color: "#ffb4b4"
        style: Text.Outline; styleColor: "#60000000"
        horizontalAlignment: Text.AlignHCenter
        font.family: root.fontFamily; font.pixelSize: 11
        wrapMode: Text.WordWrap
    }
    Connections {
        target: root.controller
        function onDraftChanged() { if (root.controller.draft.trim() !== "") root.listening = false; }
        function onBusyChanged() { if (root.controller.busy) root.listening = false; }
    }
}
