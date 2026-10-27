import QtQuick
import "file:@DATA_HOME@/sddm/themes/macshell" as Theme
Item {
    id: preview
    // config is read from the actual theme.conf by the renderer.
    property bool validationPassed: false
    property QtObject keyboard: QtObject { property bool capsLock: false }
    property ListModel userModel: ListModel {
        property string lastUser: "icentry"
        ListElement { name: "icentry" }
    }
    property ListModel sessionModel: ListModel {
        property int lastIndex: 0
        ListElement { name: "Hyprland (uwsm)" }
    }
    property QtObject sddm: QtObject {
        property bool canSuspend: true
        property bool canReboot: true
        property bool canPowerOff: true
        property string attemptedUser: ""
        property int attemptedSession: -1
        signal loginFailed()
        signal loginSucceeded()
        function login(user, password, session) {
            attemptedUser = user;
            attemptedSession = session;
            loginFailed();
        }
        function suspend() {}
        function reboot() {}
        function powerOff() {}
    }
    Theme.Main { id: theme; anchors.fill: parent }
    Timer {
        interval: 1100
        running: true
        onTriggered: {
            if (previewState === "idle") {
                preview.validationPassed = theme.selectedUser === "icentry" && !theme.busy && !theme.engaged;
                return;
            }
            var field;
            function findField(item) {
                if (item.objectName === "passwordField") return item;
                for (var i = 0; i < item.children.length; ++i) {
                    var found = findField(item.children[i]);
                    if (found) return found;
                }
                return null;
            }
            field = findField(theme);
            if (!field) return;
            field.insert(0, "preview-only");
            field.textEdited();
            if (previewState === "engaged") {
                preview.validationPassed = theme.engaged && field.text.length > 0;
            } else if (previewState === "failure") {
                theme.login();
                preview.validationPassed = sddm.attemptedUser === "icentry"
                    && sddm.attemptedSession === 0 && !theme.busy
                    && field.text.length === 0 && theme.message.length > 0;
            } else if (previewState === "reset") {
                theme.resetPassword();
                preview.validationPassed = !theme.engaged && !theme.busy
                    && field.text.length === 0 && theme.message.length === 0;
            }
            console.log("Preview state:", previewState, "passed:", preview.validationPassed);
        }
    }
}
