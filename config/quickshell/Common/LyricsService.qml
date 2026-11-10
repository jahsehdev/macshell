import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: lyrics
    property var player: null
    property bool active: true
    property var lines: []
    property string status: "idle" // idle | loading | synced | plain | none | instrumental | offline
    property string helperPath: decodeURIComponent(Qt.resolvedUrl("lyrics.py").toString().replace("file://", ""))
    property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/macshell/lyrics-v3"
    readonly property string trackKey: player ? JSON.stringify([player.trackTitle || "", player.trackArtist || "",
        player.trackAlbum || "", player.lengthSupported ? Math.round(player.length) : 0]) : ""
    property string requestKey: ""
    property var requestArgs: []
    property string response: ""
    property int attempts: 0
    property real retryAt: 0
    // MPRIS reports positions sparsely. Keep the lyric clock moving between
    // reports, reanchoring on real seeks, track changes and pause/resume.
    readonly property real reportedPosition: player && player.positionSupported ? player.position : 0
    readonly property bool playing: !!player && player.isPlaying
    property real anchorPosition: 0
    property real anchorAt: Date.now()
    property real position: reportedPosition
    function anchor(value) { anchorPosition = value; anchorAt = Date.now(); position = value; }
    onReportedPositionChanged: anchor(reportedPosition)
    onPlayingChanged: anchor(playing ? reportedPosition : position)
    Timer {
        interval: 50; repeat: true
        running: lyrics.active && !!lyrics.player && lyrics.player.positionSupported
        onTriggered: {
            var elapsed = lyrics.playing ? (Date.now() - lyrics.anchorAt) / 1000 : 0;
            var next = Math.max(0, lyrics.anchorPosition + elapsed);
            lyrics.position = lyrics.player.lengthSupported ? Math.min(lyrics.player.length, next) : next;
        }
    }
    Timer {
        interval: 250; repeat: true
        running: lyrics.active && lyrics.playing && !!lyrics.player && lyrics.player.positionSupported
        onTriggered: { try { lyrics.player.positionChanged(); } catch (err) { } }
    }

    onTrackKeyChanged: {
        anchor(reportedPosition);
        lines = []; status = "idle"; attempts = 0;
        retry.stop();
        if (active) delay.restart();
    }
    onActiveChanged: {
        anchor(reportedPosition);
        if (active) delay.restart();
        else { delay.stop(); retry.stop(); }
    }
    Timer { id: delay; interval: 400; onTriggered: lyrics.fetch() }
    Timer { id: retry; interval: 12000; onTriggered: lyrics.fetch() }

    function fetch() {
        if (!active || !player || !player.trackTitle) return;
        if (Date.now() < retryAt) {
            status = "offline";
            retry.interval = Math.max(1, retryAt - Date.now()); retry.restart();
            return;
        }
        if (process.running) return;
        requestKey = trackKey;
        requestArgs = ["python3", helperPath, player.trackTitle, player.trackArtist || "", player.trackAlbum || "",
            String(player.lengthSupported ? Math.round(player.length) : 0), cacheDir];
        response = ""; status = "loading";
        process.running = true;
    }

    function applyResult(result) {
        var out = [], i, m;
        if (result.syncedLyrics) {
            var raw = String(result.syncedLyrics), offset = /\[offset:([+-]?\d+)\]/i.exec(raw);
            var shift = offset ? Number(offset[1]) / 1000 : 0;
            var rows = raw.split(/\r?\n/);
            for (i = 0; i < rows.length; i++) {
                var line = rows[i], tags = [], re = /\[(\d+):(\d+(?:\.\d+)?)\]/g;
                while ((m = re.exec(line)) !== null) tags.push(parseInt(m[1]) * 60 + parseFloat(m[2]) + shift);
                var text = line.replace(/\[[^\]]*\]/g, "").trim();
                if (/^(制作人|作词|作曲|编曲|混音|母带|制作|和声|吉他|贝斯|鼓|录音|监制|出品|发行|OP|SP|Producer|Lyricist|Composer|Lyrics|Composed|Written)\s*[:：]/i.test(text)) continue;
                for (var j = 0; j < tags.length; j++) out.push({t: tags[j], text: text});
            }
            out.sort(function(a, b) { return a.t - b.t; });
            if (out.length) { lines = out; status = "synced"; return; }
        }
        if (result.plainLyrics) {
            var plain = String(result.plainLyrics).split(/\r?\n/);
            for (i = 0; i < plain.length; i++) if (plain[i].trim()) out.push({t: -1, text: plain[i].trim()});
            if (out.length) { lines = out; status = "plain"; return; }
        }
        lines = [];
        if (result.instrumental) status = "instrumental";
        else if (result.state === "none") status = "none";
        else {
            status = "offline";
            if (active && attempts < 3) {
                attempts++;
                retry.interval = Math.max(12000, retryAt - Date.now()); retry.restart();
            }
        }
    }

    Process {
        id: process
        command: lyrics.requestArgs
        stdout: StdioCollector { onStreamFinished: lyrics.response = text }
        onExited: (code, exitStatus) => {
            var result = {state: "error"};
            try { if (code === 0) result = JSON.parse(lyrics.response); } catch (err) { }
            if (result.retryAfter) lyrics.retryAt = Date.now() + Math.max(1, Number(result.retryAfter) || 60) * 1000;
            if (!lyrics.active) { lyrics.status = "idle"; return; }
            if (lyrics.requestKey !== lyrics.trackKey) {
                Qt.callLater(lyrics.fetch);
                return;
            }
            lyrics.applyResult(result);
        }
    }
}
