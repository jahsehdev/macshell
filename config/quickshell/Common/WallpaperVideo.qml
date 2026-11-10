import QtQuick
import QtMultimedia

// Decode only while the enclosing Loader is active. Keep the poster visible
// until a frame arrives, and retain it if a codec or file is unavailable.
Item {
    id: root
    required property url source
    readonly property bool ready: output.videoSink.videoSize.width > 0 && player.error === MediaPlayer.NoError
    readonly property bool playing: player.playbackState === MediaPlayer.PlayingState
    MediaPlayer {
        id: player
        source: root.source
        activeAudioTrack: -1
        loops: MediaPlayer.Infinite
        videoOutput: output
        Component.onCompleted: play()
        onErrorOccurred: (error, errorString) => console.warn("[wallpaper-video]", errorString)
    }
    VideoOutput {
        id: output
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop
        visible: root.ready
    }
}
