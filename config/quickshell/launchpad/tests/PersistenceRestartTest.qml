import QtQuick
import Quickshell
import Quickshell.Io
import ".."
Scope {
    FileView { id: expected; path: Theme.stateDir + "/expected-layout.json"; preload:true; blockLoading:true }
    Component.onCompleted: { Theme.columns=4; Theme.rows=3; console.log("Restart state ready:", LaunchpadState.ready); }
    Timer {
        interval:800; running:true
        onTriggered: {
            const actual=JSON.stringify(LaunchpadState.pages.map(p=>p.map(LaunchpadState.serializeItem)));
            if (actual === expected.text()) console.log("PASS restart round trip");
            else console.error("FAIL restart round trip",actual,expected.text());
            Qt.quit();
        }
    }
}
