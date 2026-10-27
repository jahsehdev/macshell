import QtQuick

// Keep the scene through close animations and quick reopen, then release it.
// Persistent window hosts and application state stay outside this Loader.
Loader {
    id: loader
    property bool requested: false
    property int releaseDelay: 1500
    property bool retained: false
    active: requested || retained
    onRequestedChanged: if (requested) retained = true
    Component.onCompleted: retained = requested
    Timer {
        interval: loader.releaseDelay
        running: loader.retained && !loader.requested
        onTriggered: loader.retained = false
    }
}
