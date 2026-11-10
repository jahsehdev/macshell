"""Lyrics matching and the production QML Process lifecycle, without network."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from urllib.error import HTTPError, URLError

SOURCE = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("lyrics", SOURCE.parent / "Common/lyrics.py")
lyrics = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lyrics)


def record(title="Shoop", artist="Salt-N-Pepa", duration=249, **extra):
    return dict(trackName=title, artistName=artist, duration=duration,
                plainLyrics="Example line", **extra)


class LookupTests(unittest.TestCase):
    def lookup(self, fetch, **kwargs):
        return lyrics.lookup("Shoop", "Salt-N-Pepa", fetch=fetch, pause=lambda _: None, **kwargs)

    def test_decorated_browser_metadata(self):
        self.assertEqual(lyrics.metadata("Salt-N-Pepa - Shoop (Official Music Video)", "Salt-N-PepaVEVO"),
                         ("Shoop", "Salt-N-Pepa"))
        self.assertEqual(lyrics.clean("Shoop - 2024 Remaster"), "Shoop")
        self.assertEqual(lyrics.clean("Song (Live at Wembley)"), "Song (Live at Wembley)")

    def test_unknown_duration_and_album_are_omitted(self):
        queries = []
        def fetch(endpoint, params):
            queries.append((endpoint, params))
            return record(syncedLyrics="[00:01.00]Example")
        self.lookup(fetch)
        self.assertEqual(queries, [("get", {"track_name": "Shoop", "artist_name": "Salt-N-Pepa"})])

    def test_search_after_signature_404(self):
        queries = []
        def fetch(endpoint, params):
            queries.append((endpoint, params))
            if endpoint == "get":
                raise HTTPError("url", 404, "missing", {}, None)
            return [record(artist="Someone Else", syncedLyrics="wrong"), record()]
        self.assertEqual(self.lookup(fetch, duration=255)["artistName"], "Salt-N-Pepa")
        self.assertEqual(queries[0][1]["duration"], 255)
        self.assertNotIn("duration", queries[1][1])

    def test_matching_precedes_sync_preference(self):
        records = [record(title="Other Song", syncedLyrics="wrong"),
                   record(duration=360, syncedLyrics="other version"), record()]
        self.assertEqual(lyrics.pick(records, "Shoop", "Salt-N-Pepa", "", 249)["duration"], 249)

    def test_synced_wins_when_metadata_matches(self):
        result = lyrics.pick([record(), record(syncedLyrics="[00:01.00]Example")],
                             "Shoop", "Salt-N-Pepa", "", 249)
        self.assertIn("syncedLyrics", result)

    def test_title_only_search_when_artist_is_missing(self):
        calls = []
        def fetch(endpoint, params):
            calls.append((endpoint, params))
            return [record()]
        self.assertIn("plainLyrics", lyrics.lookup("Shoop", "", fetch=fetch))
        self.assertEqual(calls, [("search", {"track_name": "Shoop"})])

    def test_network_errors_are_not_not_found(self):
        def fetch(*_):
            raise URLError("offline")
        self.assertEqual(self.lookup(fetch), {"state": "error"})
        self.assertEqual(self.lookup(lambda *_: []), {"state": "none"})

    def test_rate_limit_stops_fallbacks(self):
        calls = []
        def fetch(*args):
            calls.append(args)
            raise HTTPError("url", 429, "limited", {"Retry-After": "120"}, None)
        self.assertEqual(self.lookup(fetch), {"state": "error", "retryAfter": 120})
        self.assertEqual(len(calls), 1)

    def test_instrumental_does_not_fall_back_to_different_version(self):
        self.assertEqual(self.lookup(lambda *_: {"instrumental": True}),
                         {"state": "none", "instrumental": True})

    def test_plain_signature_continues_search_for_timed_lyrics(self):
        calls = []
        def fetch(endpoint, params):
            calls.append(endpoint)
            return record() if endpoint == "get" else [record(syncedLyrics="[00:01.00]Timed")]
        self.assertEqual(self.lookup(fetch, duration=249)["syncedLyrics"], "[00:01.00]Timed")
        self.assertEqual(calls, ["get", "search"])

    def test_plain_lyrics_are_kept_if_sync_search_is_limited(self):
        def fetch(endpoint, params):
            if endpoint == "get":
                return record()
            raise HTTPError("url", 429, "limited", {"Retry-After":"90"}, None)
        result = self.lookup(fetch)
        self.assertEqual(result["plainLyrics"], "Example line")
        self.assertEqual(result["retryAfter"], 90)

    def test_sync_search_does_not_choose_different_length_recording(self):
        def fetch(endpoint, params):
            return record() if endpoint == "get" else [record(duration=360, syncedLyrics="wrong version")]
        self.assertNotIn("syncedLyrics", self.lookup(fetch, duration=249))


class CacheTests(unittest.TestCase):
    def test_old_plain_cache_is_upgraded_instead_of_hiding_synced_lyrics(self):
        with tempfile.TemporaryDirectory() as temp:
            lyrics.cached_lookup("Shoop","Salt-N-Pepa",cache_dir=temp,resolve=lambda *_:record())
            path = next(Path(temp).glob("*.json"))
            old = json.loads(path.read_text());old.pop("_syncSearchVersion",None)
            path.write_text(json.dumps(old))
            timed = record(syncedLyrics="[00:01.00]Timed")
            result = lyrics.cached_lookup("Shoop","Salt-N-Pepa",cache_dir=temp,resolve=lambda *_:timed)
            self.assertIn("syncedLyrics", result)
            self.assertEqual(lyrics.cached_lookup("Shoop","Salt-N-Pepa",cache_dir=temp,resolve=lambda *_:self.fail("cache miss")),timed)

    def test_plain_cache_remains_available_when_upgrade_is_offline(self):
        with tempfile.TemporaryDirectory() as temp:
            lyrics.cached_lookup("Shoop","Salt-N-Pepa",cache_dir=temp,resolve=lambda *_:record())
            path = next(Path(temp).glob("*.json"))
            old = json.loads(path.read_text());old.pop("_syncSearchVersion",None)
            path.write_text(json.dumps(old))
            result=lyrics.cached_lookup("Shoop","Salt-N-Pepa",cache_dir=temp,resolve=lambda *_:{"state":"error","retryAfter":60})
            self.assertEqual(result["plainLyrics"],"Example line")
            self.assertEqual(result["retryAfter"],60)

    def test_empty_and_failed_results_are_not_cached_forever(self):
        with tempfile.TemporaryDirectory() as temp:
            for result in [{"state":"none"},{"state":"error"},{"instrumental":True}]:
                lyrics.cached_lookup("Shoop","Salt-N-Pepa",cache_dir=temp,resolve=lambda *_:result)
                self.assertEqual(list(Path(temp).glob("*.json")),[])
            expected=record()
            self.assertEqual(lyrics.cached_lookup("Shoop","Salt-N-Pepa",cache_dir=temp,resolve=lambda *_:expected),expected)
            self.assertEqual(lyrics.cached_lookup("Shoop","Salt-N-Pepa",cache_dir=temp,resolve=lambda *_:self.fail("positive cache was ignored")),expected)

    def test_legacy_empty_cache_does_not_block_lookup(self):
        with tempfile.TemporaryDirectory() as temp:
            cache=Path(temp);(cache/"old-cache.json").write_text("{}")
            result=lyrics.cached_lookup("Shoop","Salt-N-Pepa",cache_dir=cache,resolve=lambda *_:record())
            self.assertIn("plainLyrics",result)


class QmlLyricsTests(unittest.TestCase):
    def test_desktop_and_notch_share_service_and_notch_only_demand_polls(self):
        source = SOURCE.parent.joinpath("MacShell/MacWidgets.qml").read_text()
        section = source[source.index('    // ───────────── lyrics ('):source.index('    // ───────────── weather data')]
        poll = source[source.index('    // MPRIS does not announce'):source.index('    // screen rectangles')]
        with tempfile.TemporaryDirectory(prefix="shared-desktop-lyrics-") as temp:
            root = Path(temp)
            (root / "runtime").mkdir(mode=0o700)
            (root / "Common").symlink_to(SOURCE.parent / "Common", target_is_directory=True)
            (root / "helper.py").write_text('''import json,sys
print(json.dumps({"syncedLyrics":"[00:01.00]"+sys.argv[1]+"\\n[00:02.00]Second"}))
''')
            (root / "Service.qml").write_text('''import QtQuick
import Quickshell
import "Common" as Corners
Scope {
 id:root
 property alias backend:lyricService
 property int widgetCount:0
 function count(type) {return widgetCount;}
 property var player:QtObject {
  property string trackTitle:"First"
  property string trackArtist:"Artist"
  property string trackAlbum:"Album"
  property real position:1.1
  property real length:120
  property bool positionSupported:true
  property bool lengthSupported:true
  property bool isPlaying:true
  property int polls:0
  onPositionChanged:polls++
 }
''' + poll + section + '\n}\n')
            (root / "shell.qml").write_text('''import QtQuick
import QtTest
import Quickshell
ShellRoot {
 Service {id:service}
 Window {visible:true;width:100;height:100
  TestCase {
   name:"SharedDesktopLyrics";when:true
   onCompletedChanged:if(completed)console.log("SHARED_TOTALS",qtest_results.passCount,"passed,",qtest_results.failCount,"failed")
   function test_shared_demand() {
    const backend=service.backend;
    backend.helperPath=Qt.resolvedUrl("helper.py").toString().replace("file://","");
    wait(500);compare(service.lyricsState,"idle");
    service.notchLyricsWanted=true;
    tryCompare(service,"lyricsState","ok",3000);
    verify(service.lyricsSynced);compare(service.lyricsLines[0].text,"First");
    verify(service.player.polls>0,"Notch-only playback still polls position without desktop widgets");
    const pos=service.lyricsPosition;wait(150);verify(service.lyricsPosition>pos);
    service.lyricsWanted=true;service.notchLyricsWanted=false;
    verify(backend.active,"Closing notch must not stop desktop lyrics");
    service.player.trackTitle="Second";
    tryCompare(service,"lyricsState","ok",3000);compare(service.lyricsLines[0].text,"Second");
    service.lyricsWanted=false;verify(!backend.active);
   }
  }
 }
}''')
            env = os.environ.copy();env.pop("WAYLAND_DISPLAY",None)
            env.update(QT_QPA_PLATFORM="offscreen",QT_QUICK_BACKEND="software",XDG_RUNTIME_DIR=str(root/"runtime"),XDG_CONFIG_HOME=str(root/"config"))
            result = subprocess.run(["qs","-p",str(root),"--no-color"],env=env,capture_output=True,text=True,timeout=15)
            log=result.stdout+result.stderr
            self.assertEqual(result.returncode,0,log)
            self.assertRegex(log,r"SHARED_TOTALS [1-9][0-9]* passed, 0 failed")
            for error in ("TypeError","ReferenceError","WARN qml:","WARN scene:","Failed to load configuration"):
                self.assertNotIn(error,log)

    def test_track_changes_errors_retry_and_lrc_parsing(self):
        with tempfile.TemporaryDirectory(prefix="maclock-lyrics-") as temp:
            root = Path(temp)
            (root / "runtime").mkdir(mode=0o700)
            (root / "Lyrics.qml").symlink_to(SOURCE / "Lyrics.qml")
            (root / "Common").symlink_to(SOURCE.parent / "Common", target_is_directory=True)
            (root / "helper.py").write_text('''import json,sys,time
title=sys.argv[1]
if title=="Slow":time.sleep(1.1)
if title=="Failure":sys.exit(1)
if title=="Limited":print(json.dumps({"state":"error","retryAfter":60}))
else:print(json.dumps({"syncedLyrics":"[00:01.00][00:03.00]"+title+"\\n[00:02.00]Second"}))
''')
            (root / "shell.qml").write_text('''import QtQuick
import QtTest
import Quickshell
ShellRoot {
    QtObject {
        id:player
        property string trackTitle:"Slow"
        property string trackArtist:"Artist"
        property string trackAlbum:""
        property bool lengthSupported:false
        property real length:0
        property bool positionSupported:true
        property real position:0
        property bool isPlaying:false
    }
    Lyrics {id:service;player:player;active:false;helperPath:Qt.resolvedUrl("helper.py").toString().replace("file://","")}
    Window {visible:true;width:100;height:100
        TestCase {
            name:"LockLyrics";when:true
            onCompletedChanged:if(completed)console.log("LYRICS_TOTALS",qtest_results.passCount,"passed,",qtest_results.failCount,"failed")
            function test_process_lifecycle() {
                wait(500);compare(service.status,"idle");
                service.active=true;
                tryCompare(service,"status","loading",3000);
                player.trackTitle="Current";
                tryCompare(service,"status","synced",5000);
                compare(service.lines[0].text,"Current");compare(service.lines.length,3);
                compare(service.lines[1].t,2);compare(service.lines[2].t,3);
                player.trackTitle="Failure";
                tryCompare(service,"status","offline",4000);compare(service.lines.length,0);
                player.trackTitle="Limited";
                tryVerify(()=>service.retryAt>Date.now(),4000);
                player.trackTitle="AfterLimit";wait(800);
                compare(service.status,"offline");compare(service.lines.length,0);
                service.retryAt=0;service.fetch();
                tryCompare(service,"status","synced",4000);
                compare(service.lines[0].text,"AfterLimit");
                service.applyResult({plainLyrics:"One\\n\\nTwo"});
                compare(service.lines.length,2);compare(service.status,"plain");
                service.applyResult({state:"none"});compare(service.status,"none");
                service.applyResult({instrumental:true});compare(service.status,"instrumental");
                service.applyResult({syncedLyrics:"[offset:500]\\n[00:01.00]Offset line"});
                compare(service.lines[0].t,1.5);
                player.position=12;compare(service.position,12);
                player.isPlaying=true;wait(160);verify(service.position>12.1);
                player.position=2;fuzzyCompare(service.position,2,0.1);
                wait(100);player.isPlaying=false;const paused=service.position;
                wait(160);fuzzyCompare(service.position,paused,0.01);
                service.active=false;player.trackTitle="Hidden";wait(500);
                compare(service.status,"idle");compare(service.lines.length,0);
            }
        }
    }
}
''')
            env = os.environ.copy()
            env.pop("WAYLAND_DISPLAY", None)
            env.update(QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
                       XDG_RUNTIME_DIR=str(root / "runtime"), XDG_CONFIG_HOME=str(root / "config"))
            result = subprocess.run(["qs", "-p", str(root), "--no-color"], env=env,
                                    capture_output=True, text=True, timeout=20)
            log = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, log)
            self.assertRegex(log, r"LYRICS_TOTALS [1-9][0-9]* passed, 0 failed")
            for error in ("TypeError", "ReferenceError", "WARN qml:", "Failed to load configuration"):
                self.assertNotIn(error, log)


if __name__ == "__main__":
    unittest.main()
