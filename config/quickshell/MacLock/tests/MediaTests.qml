import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import ".." as Lock
import "../Common" as Common

Window {
    id: window
    width: 1920; height: 1080; visible: true
    QtObject {
        id: fakeState
        property bool unlocking: false
        property bool engaged: false
        property string wallpaper: ""
        property string wallpaperVideo: ""
        property string userName: "Preview"
        property string avatar: ""
        property int wifiLevel: -1
        property bool ethernet: false
        property string pass: ""
        property bool busy: false
        property int fails: 0
        property string message: ""
        property string mediaSlot: "top"
        property bool capsLock: false
        property bool use24h: true
        property var clockCfg: ({m:"solid"})
        property bool artBg: false
        property string npMode: ""
        property var now: new Date(2026, 10, 10, 12, 34)
        function poke() {}
        function setMediaSlot(value) { mediaSlot = value; }
        function checkCaps() {}
        function submit() {}
    }
    FileView {
        id: typographySettings
        path: Quickshell.env("XDG_CONFIG_HOME") + "/macdock/settings.json"
        printErrors: false
    }
    QtObject {
        id: fakeAudio
        property real volume: 0.4
        property bool muted: false
    }
    QtObject { id: fakeOutput; property var audio: fakeAudio }
    QtObject {
        id: fakePlayer
        property string trackTitle: "Shoop"
        property string trackArtist: "Salt-N-Pepa"
        property string trackAlbum: "Very Necessary"
        property string trackArtUrl: ""
        property string identity: "Fixture"
        property bool isPlaying: true
        property bool lengthSupported: true
        property bool positionSupported: true
        property real position: 54
        property real length: 249
        property bool canSeek: true
        property bool canGoPrevious: true
        property bool canGoNext: true
        property bool canTogglePlaying: true
        property int nextCalls: 0
        function previous() {}
        function next() { nextCalls++; }
        function togglePlaying() { isPlaying = !isPlaying; }
    }
    Lock.LockScreen {
        id: screen
        anchors.fill: parent
        st: fakeState
        availablePlayers: [fakePlayer]
        audioOutput: fakeOutput
        shown: true
    }
    TestCase {
        name: "LockMedia"
        when: window.visible
        onCompletedChanged: if (completed) console.log("MEDIA_TOTALS", qtest_results.passCount, "passed,", qtest_results.failCount, "failed")
        function initTestCase() { findChild(screen, "lockLyricsService").active = false; }
        function cleanup() { console.log("RESULT", qtest_results.functionName, qtest_results.failed ? "FAIL" : "PASS"); }
        function init() {
            Common.DesktopPreferences.setValue("reduceTransparency", false);
            Common.DesktopPreferences.setValue("reduceMotion", false);
            screen.audioOutput=fakeOutput;fakeAudio.volume=0.4;fakeAudio.muted=false;
            fakePlayer.isPlaying=true;
            window.width = 1920; window.height = 1080;
            fakeState.npMode = ""; fakeState.mediaSlot = "top"; fakeState.pass = "";
            screen.lyrLines = [{t:0,text:"Example line"},{t:50,text:"Current example lyric"},{t:80,text:"Next example lyric"}];
            screen.lyrStatus = "synced";
            wait(750);
        }
        function test_compact_layout_and_shared_material() {
            const card = findChild(screen, "lockMediaCard");
            const glass = findChild(screen, "lockMediaGlass");
            const title = findChild(screen, "lockMediaTitle");
            const timeline = findChild(screen, "lockMediaTimeline");
            const transport = findChild(screen, "lockMediaTransport");
            const cover = findChild(screen, "lockMediaCover");
            compare(glass.cornerR,32);compare(cover.radius,32);
            compare(title.font.weight,Font.Bold);
            fuzzyCompare(title.font.pixelSize,28*screen.u,1);
            fuzzyCompare(findChild(screen,"lockMediaArtist").font.pixelSize,20*screen.u,1);
            for (const kind of ["prev","play","next"])
                fuzzyCompare(findChild(screen,"lockMediaGlyph_"+kind).width,40*screen.u,0.01);
            fuzzyCompare(findChild(screen,"lockLyricsGlyph").width,40*screen.u,0.01);
            fuzzyCompare(transport.spacing,4*screen.u,0.01);
            verify(String(glass.shaderUrl).endsWith("Common/LiquidGlass.frag.dock.qsb"));
            fuzzyCompare(card.width, 460 * screen.u, 0.01);
            verify(title.mapToItem(card,0,0).x > card.width * 0.4);
            verify(timeline.x >= card.width * 0.4);
            verify(timeline.x + timeline.width < card.width);
            const volume=findChild(screen,"lockMediaVolume");
            verify(timeline.y + timeline.height <= volume.y);
            verify(volume.y + volume.height <= transport.y);
            verify(transport.y + transport.height <= card.height);
            const graphic=findChild(screen,"lockMusicGraphic"),lyrics=findChild(screen,"lockLyricsButton");
            verify(graphic.y>=lyrics.y+lyrics.height);
            verify(graphic.y+graphic.height<=findChild(screen,"lockMediaInlineLyric").y);
            verify(findChild(screen,"lockMediaInlineLyric").visible);
        }
        function test_font_follows_settings_live_and_preserves_bold_title() {
            const title=findChild(screen,"lockMediaTitle");
            const artist=findChild(screen,"lockMediaArtist");
            typographySettings.setText(JSON.stringify({fontFamily:"SF Pro Rounded",fontStyleName:"Medium"}));
            tryCompare(screen,"fam","SF Pro Rounded",3000);
            compare(screen.famDisplay,"SF Pro Rounded");
            compare(screen.ckFamily,"SF Pro Rounded");
            compare(artist.font.family,"SF Pro Rounded");compare(artist.font.styleName,"Medium");
            compare(title.font.family,"SF Pro Rounded");compare(title.font.weight,Font.Bold);
            compare(title.font.styleName,"");
            typographySettings.setText(JSON.stringify({fontFamily:"SF Mono",fontStyleName:"Bold Italic"}));
            tryCompare(screen,"fam","SF Mono",3000);compare(screen.fontItalic,true);
            compare(title.font.family,"SF Mono");compare(title.font.weight,Font.Bold);compare(title.font.italic,true);
            typographySettings.setText(JSON.stringify({fontFamily:"SF Pro Text",fontStyleName:"Regular"}));
            tryCompare(screen,"fam","SF Pro Text",3000);
            compare(artist.font.styleName,"Regular");compare(title.font.weight,Font.Bold);
        }
        function test_playback_lyrics_and_artwork_controls() {
            const playing = fakePlayer.isPlaying;
            mouseClick(findChild(screen,"lockMedia_play"));
            compare(fakePlayer.isPlaying,!playing);
            const next = fakePlayer.nextCalls;
            mouseClick(findChild(screen,"lockMedia_next"));compare(fakePlayer.nextCalls,next+1);
            const bar = findChild(screen,"lockMediaSeekBar");
            const target = findChild(screen,"lockMediaSeekTarget");
            mouseClick(target, 8 + bar.width * 0.75, target.height / 2);
            fuzzyCompare(fakePlayer.position, fakePlayer.length * 0.75, 2);
            mouseClick(findChild(screen,"lockLyricsButton"));compare(fakeState.npMode,"lyrics");
            mouseClick(findChild(screen,"lockCoverToggle"));compare(fakeState.npMode,"artlyrics");
            wait(750);
            mouseClick(findChild(screen,"lockLyricsButton"));compare(fakeState.npMode,"art");
            wait(750);
            screen.forceActiveFocus();keyClick(Qt.Key_A);compare(fakeState.pass,"a");
        }
        function test_system_volume_drag_keyboard_mute_and_external_updates() {
            const slider=findChild(screen,"lockMediaVolume"),card=findChild(screen,"lockMediaCard");
            verify(slider.enabled);fuzzyCompare(slider.value,0.4,0.001);
            function xFor(value) {return slider.handle.width/2+(slider.width-slider.handle.width)*value;}
            mouseClick(slider,xFor(0.75),slider.height/2);
            fuzzyCompare(fakeAudio.volume,0.75,0.03);
            fakeAudio.muted=true;compare(slider.value,0);
            mouseClick(slider,xFor(0.5),slider.height/2);
            compare(fakeAudio.muted,false);fuzzyCompare(fakeAudio.volume,0.5,0.03);
            const y=card.y;
            mouseDrag(slider,slider.handle.x+slider.handle.width/2,slider.height/2,xFor(0.9)-xFor(slider.value),0);
            fuzzyCompare(fakeAudio.volume,0.9,0.04);fuzzyCompare(card.y,y,0.1);
            fakeAudio.volume=0.2;fuzzyCompare(slider.value,0.2,0.001);
            slider.forceActiveFocus();keyClick(Qt.Key_Right);fuzzyCompare(fakeAudio.volume,0.21,0.001);
            screen.audioOutput=null;verify(!slider.enabled);
            mouseClick(slider,xFor(0.8),slider.height/2);fuzzyCompare(fakeAudio.volume,0.21,0.001);
        }
        function test_music_graphic_follows_playback_and_reduce_motion() {
            const graphic=findChild(screen,"lockMusicGraphic");
            verify(graphic.playing);const start=graphic.phase;wait(150);verify(Math.abs(graphic.phase-start)>0.05);
            fakePlayer.isPlaying=false;verify(!graphic.playing);
            const paused=graphic.phase;wait(100);fuzzyCompare(graphic.phase,paused,0.001);
            for(let i=0;i<4;i++)fuzzyCompare(findChild(graphic,"playbackBar"+i).height,5*screen.u,0.01);
            Common.DesktopPreferences.setValue("reduceMotion",true);
            fakePlayer.isPlaying=true;const still=graphic.phase;wait(150);fuzzyCompare(graphic.phase,still,0.001);
        }
        function test_missing_cover_and_reduce_transparency() {
            const cover = findChild(screen,"lockMediaCover");
            const glass = findChild(screen,"lockMediaGlass");
            compare(cover.ready,false);
            Common.DesktopPreferences.setValue("reduceTransparency",true);
            compare(glass.reduced,true);
            Common.DesktopPreferences.setValue("reduceTransparency",false);
            compare(glass.reduced,false);
        }
        function test_lyrics_blur_tracks_playback_and_plain_scroll() {
            fakeState.npMode="lyrics";fakePlayer.isPlaying=false;fakePlayer.position=54;
            screen.posBase=54;screen.posPlaying=false;screen.estPos=54;
            wait(750);
            const pane=findChild(screen,"lockLyricsPane");
            const previous=findChild(screen,"lockLyricLine_0");
            const current=findChild(screen,"lockLyricLine_1");
            const next=findChild(screen,"lockLyricLine_2");
            compare(pane.focusIndex,1);
            tryVerify(()=>current.focusBlur<0.001);
            verify(previous.focusBlur>0.13);verify(next.focusBlur>0.13);
            fakePlayer.position=85;screen.estPos=85;screen.posBase=85;
            wait(35);
            verify(current.focusBlur>0 && current.focusBlur<0.14,"Outgoing line must blur smoothly");
            verify(next.focusBlur>0 && next.focusBlur<0.14,"Incoming line must sharpen smoothly");
            tryVerify(()=>next.focusBlur<0.001);
            screen.lyrStatus="plain";
            pane.manual=0;wait(500);compare(pane.focusIndex,0);
            verify(current.focusBlur>0.13);
            pane.manual=current.y;wait(750);
            compare(pane.focusIndex,1);verify(current.focusBlur<0.001);
            verify(previous.focusBlur>0.13);verify(next.focusBlur>0.13);
            screen.estPos=180;wait(100);
            compare(pane.focusIndex,1,"Plain lyrics follow scrolling, not guessed timestamps");
        }
        function test_layout_sizes_and_positions() {
            const card = findChild(screen,"lockMediaCard");
            for (const dims of [[1280,720],[1920,1080],[2560,1440]]) {
                window.width=dims[0];window.height=dims[1];
                for (const slot of ["top","bottom"]) {
                    fakeState.mediaSlot=slot;
                    for (const mode of ["","art","lyrics","artlyrics"]) {
                        fakeState.npMode=mode;wait(700);
                        verify(card.x>=0 && card.x+card.width<=screen.width,"card horizontal bounds "+mode);
                        verify(card.y>=0 && card.y+card.height<=screen.height,"card vertical bounds "+mode);
                        compare(findChild(screen,"lockMediaGlass").cornerR,32);
                        compare(findChild(screen,"lockMediaCover").radius,32);
                        const transport=findChild(screen,"lockMediaTransport");
                        verify(transport.y+transport.height<=card.height,"transport bounds "+mode);
                        const volume=findChild(screen,"lockMediaVolume"),lyrics=findChild(screen,"lockLyricsButton");
                        verify(volume.x>=0 && volume.x+volume.width<=card.width,"volume bounds "+mode);
                        verify(volume.y+volume.height<=transport.y,"volume vertical bounds "+mode);
                        verify(lyrics.y+lyrics.height<=card.height,"lyrics button bounds "+mode);
                        if(mode==="art" || mode==="artlyrics")verify(!findChild(screen,"lockMusicGraphic").visible);
                    }
                }
            }
        }
    }
}
