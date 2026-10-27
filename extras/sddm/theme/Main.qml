// Login layout and glass clock adapted from ~/.config/quickshell/MacLock.
// Authentication and session startup are handled exclusively by SDDM.
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Effects

Rectangle {
    id: ls
    width: 1920
    height: 1080
    color: "#0b0b10"
    readonly property real u: Math.max(0.6, height / 1200)
    readonly property bool softwareRenderer: GraphicsInfo.api === GraphicsInfo.Software
    readonly property string fam: "SF Pro Text"
    readonly property string famDisplay: "SF Pro Display"
    // Theme-local fonts are readable before the user's session starts.
    FontLoader { source: config.fontTextRegular ? Qt.resolvedUrl(config.fontTextRegular) : "" }
    FontLoader { source: config.fontTextSemibold ? Qt.resolvedUrl(config.fontTextSemibold) : "" }
    FontLoader { source: config.fontDisplay ? Qt.resolvedUrl(config.fontDisplay) : "" }
    FontLoader { source: config.fontDisplayMedium ? Qt.resolvedUrl(config.fontDisplayMedium) : "" }
    property bool shown: false
    property bool choosingUser: false
    property bool engaged: false
    property bool leaving: false
    property bool busy: false
    property string message: ""
    readonly property string selectedUser: userPicker.currentValue || userInput.text
    readonly property string displayName: selectedUser === config.defaultUser ? config.displayName : selectedUser
    readonly property bool customUser: userPicker.currentIndex < 0
    readonly property var st: QtObject {
        property date now: new Date()
        readonly property bool use24h: config.use24h === "true"
    }
    readonly property string ckFont: config.clockFont || "rounded"
    readonly property string ckFamily: ckFont === "inter" ? fam : famDisplay
    readonly property int ckWeight: Number(config.clockWeight) || 560
    readonly property bool ckShortDate: config.clockDate === "short"
    readonly property bool ckGlass: config.clockMaterial !== "solid"
    readonly property real ckIntensity: Math.max(0, Math.min(1, Number(config.clockIntensity)))
    readonly property color ckTint: config.clockTint || "#FFFFFF"
    readonly property real clockPx: (ckFont === "condensed" ? (config.clockTall === "false" ? 196 : 226) : ckFont === "serif" ? 168 : ckFont === "rounded" ? 176 : 172) * (ckWeight < 330 ? 1.12 : 1) * u
    readonly property real clockWght: ckWeight
    readonly property real lightX: -0.6
    readonly property real lightY: -0.8

    function login() {
        if (busy || !selectedUser || sessionPicker.currentIndex < 0) return;
        message = "";
        busy = true;
        sddm.login(selectedUser, password.text, sessionPicker.currentIndex);
    }
    function resetPassword() {
        password.clear();
        message = "";
        engaged = false;
        password.forceActiveFocus();
    }

    component GlassButton: Button {
        id: glassButton
        font.family: ls.fam
        font.pixelSize: 13 * ls.u
        leftPadding: 18 * ls.u
        rightPadding: 18 * ls.u
        topPadding: 10 * ls.u
        bottomPadding: 10 * ls.u
        background: Rectangle {
            radius: height / 2
            color: glassButton.down ? "#55ffffff" : glassButton.hovered ? "#35ffffff" : "#300c1014"
            border.color: glassButton.activeFocus ? "white" : "#38ffffff"
        }
        contentItem: Text {
            text: glassButton.text
            font: glassButton.font
            color: "white"
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    component GlassPicker: ComboBox {
        id: glassPicker
        implicitHeight: Math.max(36 * ls.u, 32)
        font.family: ls.fam
        font.pixelSize: 13 * ls.u
        background: Rectangle {
            radius: height / 2
            color: "#600c1014"
            border.color: glassPicker.activeFocus ? "white" : "#38ffffff"
        }
        contentItem: Text {
            text: glassPicker.displayText
            font: glassPicker.font
            color: "white"
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            leftPadding: 14 * ls.u
            rightPadding: 30 * ls.u
        }
        indicator: Text {
            anchors.right: parent.right
            anchors.rightMargin: 12 * ls.u
            anchors.verticalCenter: parent.verticalCenter
            text: "⌄"
            color: "white"
        }
    }

    Component.onCompleted: {
        var preferred = userPicker.find(userModel.lastUser || config.defaultUser);
        userPicker.currentIndex = preferred >= 0 ? preferred : (userPicker.count ? 0 : -1);
        sessionPicker.currentIndex = sessionModel.lastIndex >= 0 ? sessionModel.lastIndex : 0;
        password.forceActiveFocus();
        shown = true;
    }
    Timer { interval: 1000; running: true; repeat: true; onTriggered: st.now = new Date() }
    Connections {
        target: sddm
        function onLoginFailed() {
            ls.busy = false;
            password.clear();
            ls.message = "Incorrect password. Try again.";
            password.forceActiveFocus();
            shake.restart();
        }
        function onLoginSucceeded() { password.clear(); ls.leaving = true; }
    }

    Item {
        id: scene
        anchors.fill: parent
        Image {
            id: wallpaper
            anchors.fill: parent
            source: Qt.resolvedUrl(config.background || "assets/background.jpg")
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: Math.max(1, Math.min(2560, ls.width * 1.15))
            scale: ls.shown ? 1 : 1.06
            Behavior on scale { NumberAnimation { duration: 650; easing.type: Easing.OutQuint } }
        }
        MultiEffect {
            source: wallpaper
            anchors.fill: wallpaper
            blurEnabled: true
            blurMax: 48
            blur: ls.engaged ? 0.55 : 0
            brightness: ls.engaged ? -0.1 : 0
            opacity: ls.engaged ? 1 : 0
            visible: opacity > 0.002
            Behavior on blur { NumberAnimation { duration: 650 } }
            Behavior on brightness { NumberAnimation { duration: 650 } }
            Behavior on opacity { NumberAnimation { duration: 650 } }
        }
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0; color: "#38000000" }
                GradientStop { position: 0.35; color: "#00000000" }
                GradientStop { position: 0.72; color: "#00000000" }
                GradientStop { position: 1; color: "#4d000000" }
            }
        }
    }
    ShaderEffectSource { id: sceneTex; sourceItem: scene; visible: false; textureSize: Qt.size(Math.max(1, ls.width / 2), Math.max(1, ls.height / 2)) }
    MultiEffect {
        id: sceneBlurFx
        source: sceneTex
        width: sceneTex.textureSize.width
        height: sceneTex.textureSize.height
        blurEnabled: true
        blurMax: 32
        blur: 0.35
        autoPaddingEnabled: false
        visible: false
    }
    ShaderEffectSource { id: glassTex; sourceItem: sceneBlurFx; mipmap: true; visible: false }

    // ═════════════ CLOCK ═════════════
    Item {
        id: clock
        anchors.horizontalCenter: parent.horizontalCenter
        y: (ls.shown && !ls.leaving ? 0.075 : 0.035) * ls.height
        width: Math.max(dateTxt.implicitWidth, timeItem.width)
        height: dateTxt.implicitHeight + timeItem.y - dateTxt.height + timeItem.height
        opacity: ls.shown && !ls.leaving ? 1 : 0
        Behavior on y { NumberAnimation { duration: ls.leaving ? 420 : 650; easing.type: Easing.OutQuint } }
        Behavior on opacity { NumberAnimation { duration: ls.leaving ? 300 : 650; easing.type: Easing.OutQuint } }

        MorphText {
            id: dateTxt
            visible: !ls.softwareRenderer
            horizontalAlignment: Text.AlignHCenter
            renderType: Text.NativeRendering
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(ls.st.now, ls.ckShortDate ? "ddd MMM d" : "dddd, MMMM d")
            color: Qt.rgba(1, 1, 1, 0.92)
            font.family: ls.fam
            font.pixelSize: (ls.ckShortDate ? 23 : 25) * ls.u; font.weight: Font.DemiBold
            layer.enabled: true
            layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 0.6; shadowOpacity: 0.25; shadowVerticalOffset: 1 }
        }

        Text {
            anchors.centerIn: dateTxt
            visible: ls.softwareRenderer
            text: dateTxt.text
            font: dateTxt.font
            color: "white"
        }

        // big translucent glass clock: the text is a mask, glasstext.frag refracts the wallpaper through it
        Item {
            id: timeItem
            anchors.top: dateTxt.bottom
            anchors.topMargin: -14 * ls.u
            anchors.horizontalCenter: parent.horizontalCenter
            width: timeTxt.implicitWidth + 40
            height: timeTxt.implicitHeight
            // room captured around the digits: the morph scales / realigns a little past the text box, and the glass
            // refracts past its edges — without it the clock got cropped mid-animation
            readonly property real mp: Math.max(48 * ls.u, ls.clockPx * 0.5)
            // the digits morph into each new minute (fade + slight scale) …
            MorphText {
                id: timeTxt
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                duration: 560
                useBlur: false              // no effect INSIDE the glass's hidden source (that made the clock vanish)
                animateWidth: false         // box snaps to the new width; the digits stay centred through the morph
                stretch: false
                scaleIn: 1.03; scaleOut: 0.97
                // 12- or 24-hour, as set in MacShell (no AM/PM, like the macOS / iOS lock screen)
                // (Qt's "h" only goes 12-hour together with AP, so the hour is computed here)
                text: ls.st.use24h ? Qt.formatTime(ls.st.now, "H:mm") : ((ls.st.now.getHours() % 12) || 12) + Qt.formatTime(ls.st.now, ":mm")
                color: "white"
                font.family: ls.ckFamily; font.pixelSize: ls.clockPx
                font.weight: Math.max(100, Math.min(900, Math.round(ls.clockWght)))
                font.letterSpacing: (ls.ckFont === "condensed" ? -2 : (ls.ckWeight < 330 ? 0 : -1.5)) * ls.u
                renderType: Text.QtRendering
                visible: false
            }
            ShaderEffectSource {
                id: timeMaskRaw
                sourceItem: timeTxt; hideSource: true; visible: false; smooth: true
                sourceRect: Qt.rect(-timeItem.mp, -timeItem.mp, timeTxt.width + 2 * timeItem.mp, timeTxt.height + 2 * timeItem.mp)
            }
            // … and the glass digits go soft and come back into focus while that happens (blur + morph)
            MultiEffect {
                id: timeMaskFx
                width: timeMaskRaw.sourceRect.width; height: timeMaskRaw.sourceRect.height
                source: timeMaskRaw
                blurEnabled: true; blurMax: 48; blur: timeTxt.morphBlur
                autoPaddingEnabled: false
                visible: false
            }
            ShaderEffectSource { id: timeMask; sourceItem: timeMaskFx; visible: false; smooth: true }
            // a LIGHTLY blurred copy of the digits: only used to find the thin glass rim along the edges
            MultiEffect {
                id: timeHeightFx
                width: timeMaskFx.width; height: timeMaskFx.height
                source: timeMask
                // the rim is a fixed share of the digit size (thin weights get a finer one)
                blurEnabled: true; blurMax: 16
                blur: Math.max(0.12, Math.min(0.6, ls.clockPx * (ls.ckWeight < 330 ? 0.016 : 0.03) / 16))
                autoPaddingEnabled: false
                visible: false
            }
            ShaderEffectSource { id: timeHeight; sourceItem: timeHeightFx; visible: false; smooth: true }
            // soft shadow under the glass digits so they lift off light wallpapers too
            MultiEffect {
                x: timeTxt.x - timeItem.mp; y: timeTxt.y - timeItem.mp + 8 * ls.u
                width: timeMaskFx.width; height: timeMaskFx.height
                source: timeMask
                blurEnabled: true; blurMax: 64; blur: 1.0
                colorization: 1.0; colorizationColor: "black"; brightness: -1.0
                opacity: ls.ckGlass ? 0.22 : 0.12
                Behavior on opacity { NumberAnimation { duration: 500 } }
            }
            ShaderEffect {
                id: timeGlass
                x: timeTxt.x - timeItem.mp; y: timeTxt.y - timeItem.mp
                width: timeMaskFx.width; height: timeMaskFx.height
                fragmentShader: Qt.resolvedUrl("glasstext.frag.qsb")
                // where the glass really is on screen (follows the clock's animations)
                readonly property point fp: { ls.clockPx; clock.y; clock.x; timeItem.x; timeTxt.x; timeTxt.width; return timeGlass.mapToItem(ls, 0, 0); }
                property variant src: glassTex
                property variant mask: timeMask
                property variant hmap: timeHeight
                property vector2d itemSize: Qt.vector2d(width, height)
                property vector2d srcSize: Qt.vector2d(ls.width, ls.height)
                property vector2d srcOffset: Qt.vector2d(fp.x, fp.y)
                // Apple's two clock materials (Settings → Lock Screen → Clock): Solid = vibrancy, Glass = Liquid Glass
                property real mode: ls.ckGlass ? 1 : 0
                property real intensity: ls.ckGlass ? ls.ckIntensity : 0.55 + 0.4 * ls.ckIntensity
                property real refract: (6 + 4 * (1 - ls.ckIntensity)) * ls.u
                property real bevel: 4.5
                property color tint: ls.ckTint
                property vector2d lightDir: Qt.vector2d(ls.lightX, ls.lightY)
                Behavior on mode { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                Behavior on intensity { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                Behavior on tint { ColorAnimation { duration: 500 } }
                onStatusChanged: if (status === ShaderEffect.Error) console.log("[maclock] clock shader:", log)
            }
            // fallback when the shader is missing
            Text {
                visible: ls.softwareRenderer || timeGlass.status === ShaderEffect.Error
                anchors.fill: timeTxt
                text: timeTxt.text; font: timeTxt.font
                horizontalAlignment: Text.AlignHCenter
                color: Qt.rgba(1, 1, 1, 0.85)
            }
        }
    }



    Column {
        id: loginColumn
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 78 * ls.u
        width: 290 * ls.u
        spacing: 10 * ls.u
        opacity: ls.shown && !ls.leaving ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 500 } }

        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 70 * ls.u
            height: width
            scale: ls.engaged ? 1 : 0.94
            Behavior on scale { NumberAnimation { duration: 650; easing.type: Easing.OutQuint } }
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: "#29ffffff"
                Text {
                    anchors.centerIn: parent
                    text: (ls.displayName || "?").charAt(0).toUpperCase()
                    color: "white"
                    font.family: ls.fam
                    font.pixelSize: 30 * ls.u
                    visible: avatar.status !== Image.Ready
                }
            }
            Rectangle { id: avatarMask; anchors.fill: parent; radius: width / 2; color: "white"; visible: false; layer.enabled: true }
            Image {
                id: avatar
                visible: !ls.softwareRenderer
                anchors.fill: parent
                source: ls.selectedUser === config.defaultUser ? Qt.resolvedUrl(config.avatar || "assets/avatar.png") : ""
                fillMode: Image.PreserveAspectCrop
                sourceSize: Qt.size(256, 256)
                layer.enabled: !ls.softwareRenderer
                layer.effect: MultiEffect { maskEnabled: true; maskSource: avatarMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1 }
            }
            // QML shader masks do not work with Qt's software backend.
            Canvas {
                id: avatarFallback
                anchors.fill: parent
                visible: ls.softwareRenderer
                property url imageUrl: avatar.source
                onImageUrlChanged: { if (imageUrl.toString()) loadImage(imageUrl); requestPaint(); }
                onImageLoaded: requestPaint()
                onWidthChanged: requestPaint()
                onPaint: {
                    var ctx = getContext("2d"); ctx.reset();
                    if (!imageUrl.toString() || !isImageLoaded(imageUrl)) return;
                    ctx.beginPath(); ctx.arc(width / 2, height / 2, width / 2, 0, Math.PI * 2); ctx.clip();
                    // Canvas loads the full file, independently of Image.sourceSize.
                    // Scale that full avatar into the circular clip.
                    ctx.drawImage(imageUrl, 0, 0, width, height);
                }
            }
            Rectangle { anchors.fill: parent; radius: width / 2; color: "transparent"; border.color: "#38ffffff" }
        }
        Button {
            anchors.horizontalCenter: parent.horizontalCenter
            text: ls.displayName
            font.family: ls.fam
            font.pixelSize: 15 * ls.u
            font.weight: Font.DemiBold
            padding: 0
            background: Item {}
            contentItem: Text { text: parent.text; font: parent.font; color: "white"; horizontalAlignment: Text.AlignHCenter }
            onClicked: if (userPicker.count > 1) ls.choosingUser = !ls.choosingUser
            Accessible.name: "User: " + ls.displayName + (userPicker.count > 1 ? ". Select to switch user" : "")
        }
        GlassPicker {
            id: userPicker
            width: parent.width
            visible: ls.choosingUser && count > 1
            enabled: !ls.busy
            model: userModel
            textRole: "name"
            valueRole: "name"
            onActivated: { ls.choosingUser = false; ls.resetPassword(); }
            Accessible.name: "User"
        }
        TextField {
            id: userInput
            width: parent.width
            visible: ls.customUser
            enabled: !ls.busy
            text: config.defaultUser || ""
            placeholderText: "Username"
            onAccepted: password.forceActiveFocus()
            Accessible.name: "Username"
        }
        Item {
            id: passwordPill
            anchors.horizontalCenter: parent.horizontalCenter
            width: (ls.engaged ? 236 : 210) * ls.u
            height: Math.max(36 * ls.u, 32)
            Behavior on width { NumberAnimation { duration: 450; easing.type: Easing.OutQuint } }
            transform: Translate { id: shakeOffset }
            Glass { anchors.fill: parent; src: glassTex; frame: ls; cornerR: height / 2; thickness: 18; tint: 0.5 }
            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: "transparent"
                border.color: password.activeFocus && ls.engaged ? "#70ffffff" : "#22ffffff"
            }
            TextField {
                id: password
                objectName: "passwordField"
                anchors.fill: parent
                rightPadding: 38 * ls.u
                leftPadding: 16 * ls.u
                background: Item {}
                enabled: !ls.busy
                echoMode: TextInput.Password
                color: "white"
                placeholderTextColor: "#b0ffffff"
                placeholderText: "Enter Password"
                font.family: ls.fam
                font.pixelSize: 14 * ls.u
                selectByMouse: true
                onTextEdited: { ls.engaged = true; ls.message = ""; }
                onAccepted: ls.login()
                Keys.onEscapePressed: ls.resetPassword()
                Accessible.name: "Password"
            }
            Button {
                visible: password.length > 0 || ls.busy
                anchors.right: parent.right
                anchors.rightMargin: 4 * ls.u
                anchors.verticalCenter: parent.verticalCenter
                width: 28 * ls.u
                height: width
                enabled: !ls.busy && !!ls.selectedUser && sessionPicker.currentIndex >= 0
                text: ls.busy ? "…" : "→"
                background: Rectangle { radius: width / 2; color: parent.down ? "#70ffffff" : "#30ffffff" }
                contentItem: Text { text: parent.text; color: "white"; font.pixelSize: 20 * ls.u; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                onClicked: ls.login()
                Accessible.name: "Log in"
            }
        }
        Text {
            width: parent.width
            height: Math.max(implicitHeight, 18 * ls.u)
            horizontalAlignment: Text.AlignHCenter
            text: ls.message || (keyboard.capsLock ? "Caps Lock is on" : ls.busy ? "Logging in…" : ls.engaged ? "Enter your password to log in" : "")
            color: ls.message ? "#fff2c7c2" : "#8cffffff"
            font.family: ls.fam
            font.pixelSize: 12 * ls.u
            wrapMode: Text.WordWrap
        }
    }

    SequentialAnimation {
        id: shake
        NumberAnimation { target: shakeOffset; property: "x"; to: -14; duration: 55 }
        NumberAnimation { target: shakeOffset; property: "x"; to: 12; duration: 80 }
        NumberAnimation { target: shakeOffset; property: "x"; to: -8; duration: 75 }
        NumberAnimation { target: shakeOffset; property: "x"; to: 5; duration: 70 }
        NumberAnimation { target: shakeOffset; property: "x"; to: 0; duration: 90 }
    }

    GlassPicker {
        id: sessionPicker
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 22 * ls.u
        width: Math.max(190 * ls.u, implicitWidth)
        model: sessionModel
        textRole: "name"
        enabled: !ls.busy
        Accessible.name: "Desktop session"
    }
    Row {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 22 * ls.u
        spacing: 12 * ls.u
        GlassButton { text: "Sleep"; visible: sddm.canSuspend; enabled: !ls.busy; onClicked: sddm.suspend() }
        GlassButton { text: "Restart"; visible: sddm.canReboot; enabled: !ls.busy; onClicked: sddm.reboot() }
        GlassButton { text: "Shut Down"; visible: sddm.canPowerOff; enabled: !ls.busy; onClicked: sddm.powerOff() }
    }
}
