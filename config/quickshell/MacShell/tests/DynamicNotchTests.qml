pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell.Io
import Quickshell
import Quickshell.Services.Mpris
import ".." as Shell
import "../Common" as Common
import "../NotchToolsState.js" as ToolsLogic
import "../NotchGeometry.js" as Geometry
import "../NotchCalendarState.js" as CalendarDates

Window {
    id: window
    visible: true
    width: 800; height: 480
    color: "#5D7394"
    QtObject {
        id: media
        property string trackTitle: "Going to Bubble On"
        property string trackArtist: "The Spires"
        property string trackAlbum: "Summer Flows"
        property string identity: "Test player"
        property string trackArtUrl: ""
        property bool isPlaying: true
        property bool canTogglePlaying: true
        property bool canGoNext: true
        property bool canGoPrevious: true
        property bool canSeek: true
        property bool canRaise: true
        property string dbusName: "test.player"
        property string desktopEntry: ""
        property bool shuffleSupported: true
        property bool shuffle: false
        property bool loopSupported: true
        property int loopState: MprisLoopState.None
        property bool positionSupported: true
        property real position: 48
        property real length: 192
        property int nextCalls: 0
        property int raiseCalls: 0
        function togglePlaying() { isPlaying = !isPlaying; }
        function next() { nextCalls++; }
        function previous() {}
        function raise() { raiseCalls++; }
    }
    QtObject {
        id: fakeClock
        property bool timerActive: false
        property var timer: ({ state: "running", label: "Tea", total: 60000, left: 42000 })
        property var ringing: null
        function timerLeft() { return timer.left; }
        function fmtDur(ms, tenths) { return "00:42"; }
        function pauseTimer() { timer = Object.assign({}, timer, {state: "paused"}); }
        function resumeTimer() { timer = Object.assign({}, timer, {state: "running"}); }
        function cancelTimer() { timerActive = false; }
        function stopRing() { ringing = null; }
        function open(tab) {}
    }
    QtObject {id:otherPlayer;property string dbusName:"test.other";property string identity:"Other player";property bool isPlaying:false}
    QtObject {
        id: fakeWidgets
        property var player: media
        property bool lyricsWanted: false
        property bool notchLyricsWanted: false
        property var lyricsLines: [{ t: -1, text: "Local test lyrics" }]
        property bool lyricsSynced: false
        property string lyricsState: "ok"
        property bool wxReady: true
        property bool wxBusy: false
        property string wxError: ""
        property string wxCity: "Lisbon"
        property int wxTemp: 18
        property int wxHi: 21
        property int wxLo: 12
        property bool wxDay: true
        property var wxInfo: ({t:"Sunny",k:"sun"})
        property var wxHourly: [{h:"Now",t:18,k:"sun"},{h:"11AM",t:19,k:"sun"},{h:"12PM",t:20,k:"partly"},{h:"1PM",t:21,k:"sun"},{h:"2PM",t:21,k:"sun"},{h:"3PM",t:20,k:"partly"}]
        property string locMode: "auto"
        property string cityName: ""
        property string tempUnit: "C"
        property int refreshCalls: 0
        function refresh() {refreshCalls++;}
        function refreshSoon() {refreshCalls++;}
    }
    QtObject {
        id: fakeGlassSettings
        property bool dockDark: true
        property real opacity: 0.42
        property real blur: 5
        property real liquid: 1
        property real rim: 0.45
        property real grain: 0.03
        readonly property real effGlassOpacity: Common.DesktopPreferences.glassOpacity(opacity)
        readonly property real effGlassBlur: Common.DesktopPreferences.glassBlur(blur)
        readonly property real effGlassLiquid: Common.DesktopPreferences.glassLiquid(liquid)
        readonly property real effGlassRim: Common.DesktopPreferences.glassRim(rim)
        readonly property real effGlassGrain: Common.DesktopPreferences.glassGrain(grain)
    }
    QtObject {
        id: fakeBar
        property var hub: ({clock: fakeClock, widgets: fakeWidgets})
        property string notchMode: "attached"
        property string notchStyle: "solid"
        property real notchScale: 1
        property bool reduceMotion: true
        property bool reduceTransparency: false
        property bool effDark: true
        property bool liquidActive:false
        property url glassShaderUrl:Qt.resolvedUrl("../liquidglass.frag.qsb")
        property color menuBorderColor:"#9BC9E5"
        property bool notchIdleEyes: true
        property string fontFamily: "sans-serif"
        property int barHeight: 28
        property var player: null
        property var notchService: null
        property var mediaService: null
        property var downloadsService: null
        property var recordingService: null
        property bool recRun:false
        property int recSecs:83
        property var sink: ({id:1,name:"test.speaker",description:"Test speakers"})
        property var audioOutputs: [sink,{id:2,name:"test.headset",description:"Test headphones"}]
        property bool notchEnabled: true
        property bool hasBattery: true
        property bool btOn: true
        property bool btReady: true
        property var btDevices: [{name:"Test earbuds",icon:"headphones",connected:true,bat:"70"}]
        property bool recording: false
        property bool charging: false
        property int batPct: 74
        property bool osdReady: true
        property bool osdVisible: false
        property string osdKind: "volume"
        property real osdValue: 0.65
        property real volume: 0.65
        property real brightness: 0.5
        property bool muted: false
        property int settingsCalls: 0
        function recTime() {return Math.floor(recSecs/60)+":"+(recSecs%60<10?"0":"")+recSecs%60;}
        function toggleRecording() { recording = !recording; }
        function setVolume(v) { volume = Math.max(0, Math.min(1, v)); }
        function setBrightness(v) { brightness = v; }
        function openSettings(pane) { settingsCalls++; }
        function toggleMute() { muted=!muted; }
        function chooseAudio(node) { sink=node; }
    }
    Shell.DynamicNotch {
        id: notch
        bar: fakeBar
        clock: fakeClock
        x: (window.width - width) / 2
        screenWidth: window.width
    }
    Shell.NotchTools { id:tools; bar:fakeBar; persistence:false; notifications:false }
    Shell.NotchRecording {id:recordingResults;bar:fakeBar}
    Shell.NotchDownloads {id:downloadResults;enabled:false}
    Shell.NotchMedia { id:mediaService;bar:fakeBar;persistence:false;captureEnabled:false;availablePlayers:[media] }
    Component {id:statsFixture;Shell.NotchStats {}}
    Component {id:calendarFixture;Shell.NotchCalendar {}}
    Component {id:menuBackdropFixture;Rectangle {width:800;height:760;color:"#E5608F"}}
    Component {id:glassOpticsFixture;Shell.NotchGlass {visible:false}}
    Component { id:persistentTools; Shell.NotchTools { notifications:false } }
    Component {id:liveSpectrumFixture;Shell.NotchMedia{captureEnabled:false;persistence:false;availablePlayers:[media]}}
    Component {id:persistentMedia;Shell.NotchMedia{captureEnabled:false;availablePlayers:[]}}
    Component {
        id: pendingShaderFixture
        Item { property bool failed: false; property bool ready: false }
    }
    TestCase {
        name: "DynamicNotch"
        when: window.visible
        onCompletedChanged: if (completed) console.log("TOTALS", qtest_results.passCount, "passed,", qtest_results.failCount, "failed")
        function cleanup() { console.log("RESULT", qtest_results.functionName, qtest_results.failed ? "FAIL" : "PASS"); }
        function init() {
            window.width=800;
            window.height = 480;
            mouseMove(window.contentItem, 0, 450);
            fakeBar.reduceMotion = true;fakeBar.effDark=true;
            fakeBar.downloadsService=null;downloadResults.reset();
            fakeBar.recordingService=null;fakeBar.recRun=false;fakeBar.recSecs=83;recordingResults.reset();
            fakeBar.mediaService=null;mediaService.selectedId="";mediaService.availablePlayers=[media];mediaService.visualizer=true;
            fakeWidgets.player=media;
            fakeWidgets.wxReady=true;fakeWidgets.wxBusy=false;fakeWidgets.wxError="";fakeWidgets.wxDay=true;
            fakeWidgets.wxInfo=({t:"Sunny",k:"sun"});fakeWidgets.wxTemp=18;fakeWidgets.wxCity="Lisbon";
            fakeWidgets.locMode="auto";fakeWidgets.cityName="";fakeWidgets.tempUnit="C";fakeWidgets.refreshCalls=0;
            media.shuffleSupported=true;media.loopSupported=true;media.shuffle=false;media.loopState=MprisLoopState.None;fakeBar.muted=false;
            fakeBar.notchStyle = "solid"; fakeBar.reduceTransparency = false;
            fakeBar.notchIdleEyes = true; media.isPlaying = true;
            fakeBar.notchService = null; tools.state = ToolsLogic.defaults(Date.now()); tools.error = "";
            tools.dismissDeviceEvent(); tools.deviceExpandedMs=4500;tools.deviceCompactMs=5000;tools.bluetoothPrimed=false; tools.pomodoroDismissed=false;
            fakeBar.btReady=false; fakeBar.btOn=true; fakeBar.hasBattery=true; fakeBar.notchEnabled=true;
            fakeBar.btDevices=[{name:"Test earbuds",icon:"headphones",connected:true,bat:"70"}];
            fakeBar.btReady=true; tools.observeBluetooth();
            tools.calendar.events=[];tools.calendar.error="";tools.calendar.today();notch.calendarExpanded=false;
            notch.close();tools.stats.snapshot=null;tools.stats.history=[];tools.stats.receivedAt=0;tools.stats.error="";tools.stats.nowMs=Date.now(); notch.available = true; notch.chargingFeedback = false;
            const musicView=findChild(notch,"notchMusic");musicView.lyricsOpen=false;musicView.localVisualizer=true;
            fakeBar.player = null; fakeBar.recording = false; fakeBar.charging = false;
            fakeBar.osdVisible = false; fakeBar.osdKind="volume"; fakeBar.notchMode = "attached"; fakeBar.notchScale = 1;
            fakeBar.reduceMotion = true;
            fakeWidgets.lyricsWanted = false;
            fakeWidgets.lyricsSynced = false;
            fakeWidgets.lyricsLines = [{ t: -1, text: "Local test lyrics" }];
            fakeWidgets.lyricsState = "ok";
            fakeClock.timerActive = false; fakeClock.ringing = null;
            fakeClock.timer = {state: "running", label: "Tea", total: 60000, left: 42000};
        }
        function button(label) {
            const all = [];
            function walk(item) { if (item.text === label) all.push(item); for (const c of item.children || []) walk(c); }
            walk(notch);
            return all.find(x => x.visible && x.enabled && x.clicked !== undefined) || null;
        }
        function test_click_and_auto_close() {
            compare(notch.activity, "idle");
            mouseMove(notch, notch.width / 2, 12);
            mouseClick(notch, 20, 12);
            verify(notch.expanded);
            tryVerify(() => notch.width >= 350);
            mouseMove(window.contentItem, 0, 450);
            tryVerify(() => !notch.expanded, 1500);
        }
        function test_hover_preview() {
            mouseMove(notch, notch.width / 2, 15);
            tryVerify(() => notch.expanded, 1000);
            mouseMove(window.contentItem, 0, 450);
            tryVerify(() => !notch.expanded, 1500);
        }
        function test_close_does_not_reopen_from_pending_hover() {
            mouseMove(notch, notch.width / 2, 12);
            mouseClick(notch, 20, 12);
            verify(notch.expanded);
            notch.close();
            wait(350);
            verify(!notch.expanded);
        }
        function test_activity_priority_and_switching() {
            fakeBar.player = media; compare(notch.activity, "music");
            fakeClock.timerActive = true; compare(notch.activity, "timer");
            fakeBar.recording = true; compare(notch.activity, "recording");
            notch.selected = "music"; compare(notch.activity, "recording");
            fakeBar.osdVisible = true; compare(notch.activity, "recording");
            fakeBar.osdVisible = false; compare(notch.activity, "recording");
            fakeClock.ringing = {kind: "timer"}; compare(notch.activity, "timer");
            fakeClock.ringing = null; fakeBar.player = null; compare(notch.activity, "recording");
        }
        function test_media_controls() {
            fakeBar.player = media; notch.pinned = true;
            const playing = media.isPlaying;
            const play = findChild(notch, "notchMusicPlayPause"); verify(play !== null);
            mouseClick(play); compare(media.isPlaying, !playing);
            const next = findChild(notch, "notchMusicNext"); verify(next !== null);
            const count = media.nextCalls; mouseClick(next); compare(media.nextCalls, count + 1);
            media.canGoNext = false; verify(!next.enabled); media.canGoNext = true;
        }
        function test_music_seek_and_navigation_rail() {
            fakeBar.player = media; notch.pinned = true;
            const slider = findChild(notch, "notchMusicSeek");
            verify(slider.enabled);
            media.position = 48;
            mousePress(slider, slider.width / 2, slider.height / 2);
            mouseMove(slider, slider.width * 0.75, slider.height / 2, 10, Qt.LeftButton);
            compare(media.position, 48, "Do not seek remotely until release");
            mouseRelease(slider, slider.width * 0.75, slider.height / 2);
            fuzzyCompare(media.position, media.length * 0.75, 2);
            media.position = 48;
            fuzzyCompare(slider.value, 0.25, 0.01);
            fakeBar.notchService=tools; wait(30);
            const count = media.raiseCalls;
            mouseClick(findChild(notch, "notchMediaTabpomodoro"));
            compare(notch.activity,"pomodoro"); verify(notch.expanded);
            compare(media.raiseCalls,count);
        }
        function test_media_shuffle_repeat_and_capabilities() {
            fakeBar.player=media;notch.pinned=true;wait(40);
            const shuffle=findChild(notch,"notchMusicShuffle"),repeat=findChild(notch,"notchMusicRepeat");
            mouseClick(shuffle);verify(media.shuffle);verify(shuffle.active);
            mouseClick(shuffle);verify(!media.shuffle);
            mouseClick(repeat);compare(media.loopState,MprisLoopState.Playlist);
            mouseClick(repeat);compare(media.loopState,MprisLoopState.Track);compare(repeat.symbol,"repeatOne");
            mouseClick(repeat);compare(media.loopState,MprisLoopState.None);
            media.shuffleSupported=false;media.loopSupported=false;verify(!shuffle.enabled);verify(!repeat.enabled);
        }
        function test_media_lyrics_only_toolbar_and_compact_controls() {
            fakeBar.notchService=tools;fakeBar.player=media;notch.pinned=true;wait(40);
            const view=findChild(notch,"notchMusic");
            compare(notch.width,640);
            for(const name of ["notchMusicVisualizer","notchMusicJump","notchMusicJumpPane","notchMusicMute","notchMusicSettings","notchMediaSettings","notchMediaSource","notchMediaOpenApp","notchMediaPlayers"])
                verify(findChild(notch,name)===null,"Removed media toolbar action: "+name);
            mouseClick(findChild(notch,"notchMusicLyrics"));verify(view.lyricsOpen);compare(notch.width,740);
            verify(findChild(notch,"notchMusicDensity")===null);compare(notch.height,200);
            notch.close();compare(notch.width,324);verify(view.lyricsOpen);
            const playing=media.isPlaying,count=media.nextCalls;
            mouseClick(findChild(notch,"notchMusicCompactToggle"));compare(media.isPlaying,!playing);verify(!notch.expanded);
            mouseClick(findChild(notch,"notchMusicCompactNext"));compare(media.nextCalls,count+1);verify(!notch.expanded);
            notch.pinned=true;verify(view.lyricsOpen);compare(notch.height,200);
        }
        function test_audio_capture_uses_local_path_receives_frames_and_recovers_after_exit() {
            const helper=Quickshell.env("MACSHELL_SPECTRUM_TEST_HELPER");
            if(!helper){skip("Process fixture is provided by run-dynamic-notch-tests.sh");return;}
            fakeBar.player=media;fakeBar.reduceMotion=false;
            const subject=createTemporaryObject(liveSpectrumFixture,window,{bar:fakeBar});verify(subject!==null);
            verify(subject.spectrumHelperPath.startsWith("/"));verify(!subject.spectrumHelperPath.includes("file:"));
            verify(subject.configDir.startsWith("/"));verify(!subject.configDir.includes("file:"));
            subject.spectrumHelperPath=helper;fakeBar.mediaService=subject;
            subject.captureEnabled=true;
            tryVerify(()=>subject.spectrumFrames>=3,2500);
            verify(subject.captureVerified,"A real child process must supply live spectrum frames");
            compare(subject.spectrumError,"");verify(subject.spectrumWanted);
            const bar=findChild(notch,"notchMusicCompactWaveBar2");tryVerify(()=>bar.height>4,500);
            media.isPlaying=false;tryVerify(()=>!subject.spectrumWanted,1000);
            const count=subject.spectrumFrames;wait(650);compare(subject.spectrumFrames,count);
            verify(!subject.spectrumWanted);subject.captureEnabled=false;fakeBar.mediaService=null;subject.destroy();
        }
        function test_compact_audio_wave_tracks_bands_and_stops_when_inactive() {
            fakeBar.notchService=tools;fakeBar.mediaService=mediaService;fakeBar.player=media;
            fakeBar.reduceMotion=false;notch.close();wait(140);
            const wave=findChild(notch,"notchMusicCompactWave"),bar=findChild(notch,"notchMusicCompactWaveBar2");
            verify(wave.responsive);compare(mediaService.spectrumClients,1);
            mediaService.bands=Array(24).fill(0);tryVerify(()=>Math.abs(bar.height-4)<0.1,500);
            mediaService.bands=Array(24).fill(0.8);wait(35);
            verify(bar.height>4 && bar.height<18,"Audio bar interpolates smoothly");
            tryVerify(()=>Math.abs(bar.height-18)<0.1,500);
            media.isPlaying=false;verify(!wave.responsive);compare(mediaService.spectrumClients,0);
            tryVerify(()=>Math.abs(bar.height-16)<0.1,500);compare(wave.opacity,0.35);
            media.isPlaying=true;verify(wave.responsive);
            fakeBar.reduceMotion=true;verify(!wave.responsive);compare(mediaService.spectrumClients,0);compare(bar.height,16);
            fakeBar.reduceMotion=false;notch.pinned=true;
            const view=findChild(notch,"notchMusic");view.lyricsOpen=true;wait(40);
            verify(!wave.responsive);compare(mediaService.spectrumClients,0);
            notch.close();verify(wave.responsive);compare(mediaService.spectrumClients,1);
            notch.available=false;verify(!wave.responsive);compare(mediaService.spectrumClients,0);
        }
        function test_media_primary_tabs_and_overflow_pages() {
            window.height=700;fakeBar.notchService=tools;fakeBar.player=media;notch.pinned=true;wait(30);
            const rail=findChild(notch,"notchMediaRail");compare(rail.height,120);compare(rail.cellHeight,28);
            for(const page of ["music","pomodoro","stats","more"]){const tab=findChild(notch,"notchMediaTab"+page);verify(tab!==null);compare(tab.iconSize,20);compare(tab.height,28);}
            verify(findChild(notch,"notchMediaTabwater")===null);
            const more=findChild(notch,"notchMediaTabmore");mouseClick(more);wait(30);
            const menu=notch.settingsPopup;verify(menu!==null);compare(menu.objectName,"notchMorePages");verify(menu.visible);verify(notch.interacting);
            for(const page of ["water","shelf","todo","calendar","weather"]){const row=findChild(menu.contentItem,"notchMorePage"+page);verify(row!==null);compare(row.height,40);}
            mouseClick(findChild(menu.contentItem,"notchMorePagecalendar"));wait(30);compare(notch.activity,"calendar");verify(!menu.visible);verify(notch.expanded);
            notch.selectPage("music");wait(30);mouseClick(findChild(notch,"notchMediaTabmore"));wait(20);keyClick(Qt.Key_Escape);tryVerify(()=>!notch.settingsPopupOpen,1000);
            tools.updateMenus(["music","stats","weather"]);wait(25);verify(findChild(notch,"notchMediaTabpomodoro")===null);compare(rail.height,92);
            mouseClick(findChild(notch,"notchMediaTabmore"));wait(20);verify(findChild(notch.settingsPopup.contentItem,"notchMorePageweather")!==null);verify(findChild(notch.settingsPopup.contentItem,"notchMorePagewater")===null);
            notch.close();tryVerify(()=>!notch.settingsPopupOpen,1000);
            notch.pinned=true;notch.selectPage("music");tools.updateMenus(["music","stats"]);wait(20);verify(findChild(notch,"notchMediaTabmore")===null);compare(rail.height,64);
        }
        function test_media_more_menu_fits_narrow_and_floating() {
            window.height=600;fakeBar.notchService=tools;fakeBar.player=media;
            for(const mode of ["attached","floating"])for(const width of [320,420,800]){
                window.width=width;fakeBar.notchMode=mode;notch.pinned=true;notch.selectPage("music");wait(25);
                const more=findChild(notch,"notchMediaTabmore");mouseClick(more);wait(20);const menu=notch.settingsPopup;
                verify(menu.visible);verify(menu.x>=8);verify(menu.x+menu.width<=width-8);verify(menu.y+menu.height<=window.height-8);
                menu.close();wait(10);
            }
        }
        function test_media_timeline_gutter_and_readable_medium_layout() {
            fakeBar.notchService=tools;fakeBar.player=media;notch.pinned=true;
            const view=findChild(notch,"notchMusic"),timeline=findChild(notch,"notchMusicTimeline"),rail=findChild(notch,"notchMediaRail");
            const transport=findChild(notch,"notchMusicTransport"),title=findChild(notch,"notchMusicTitle"),artist=findChild(notch,"notchMusicArtist");
            for(const mode of ["attached","floating"])for(const lyrics of [false,true]){
                fakeBar.notchMode=mode;notch.pinned=true;view.lyricsOpen=lyrics;wait(35);
                const end=timeline.mapToItem(notch,timeline.width,0),edge=rail.mapToItem(notch,0,0);
                verify(end.x+16*view.layoutScale<=edge.x,"Timeline must leave a gutter before the navigation rail");
                verify(transport.mapToItem(notch,0,transport.height).y<=notch.height-8*view.layoutScale);
                if(lyrics){const pane=findChild(notch,"notchLyricsPane");verify(transport.mapToItem(notch,transport.width,0).x+16*view.layoutScale<=pane.mapToItem(notch,0,0).x);}
                verify(title.font.pixelSize>=16);verify(artist.visible&&artist.font.pixelSize>=12);verify(findChild(notch,"notchMusicPrevious").iconSize>=26);
            }
        }
        function test_media_wheel_never_changes_volume_and_plain_lyrics_still_scroll() {
            fakeBar.notchService=tools;fakeBar.player=media;notch.pinned=true;wait(30);
            const view=findChild(notch,"notchMusic"),volume=fakeBar.volume;
            for(const lyrics of [false,true]) {
                view.lyricsOpen=lyrics;wait(20);
                const title=findChild(notch,"notchMusicTitle"),play=findChild(notch,"notchMusicPlayPause");
                for(const target of [title,play,notch]) {
                    mouseWheel(target,target.width/2,target.height-4,0,120);
                    mouseWheel(target,target.width/2,target.height-4,0,-120);
                    compare(fakeBar.volume,volume);
                }
            }
            fakeWidgets.lyricsSynced=false;
            fakeWidgets.lyricsLines=Array.from({length:20},(_,index)=>({t:-1,text:"Scrollable lyric "+index}));
            wait(30);const list=findChild(notch,"notchLyricsList"),before=list.contentY;
            mouseWheel(list,list.width/2,list.height/2,0,-120);
            tryVerify(()=>list.contentY>before,700);compare(fakeBar.volume,volume);
            notch.close();mouseWheel(notch,20,notch.height/2,0,-120);compare(fakeBar.volume,volume);
            fakeBar.osdVisible=true;fakeBar.osdKind="volume";notch.pinned=true;wait(20);
            compare(notch.activity,"music");fakeBar.volume=0.5;
            mouseWheel(notch,12,notch.height/2,0,120);fuzzyCompare(fakeBar.volume,0.5,0.001);
            fakeBar.volume=volume;fakeBar.osdVisible=false;
        }
        function test_media_player_selection_and_disconnect_fallback() {
            fakeBar.mediaService=mediaService;mediaService.availablePlayers=[media,otherPlayer];
            fakeBar.player=media;notch.pinned=true;wait(40);
            mediaService.selectPlayer(otherPlayer);compare(mediaService.player,otherPlayer);
            mediaService.availablePlayers=[media];compare(mediaService.player,media);
            mediaService.availablePlayers=[];compare(mediaService.player,null);
            mediaService.availablePlayers=[media,otherPlayer];mediaService.selectPlayer(null);compare(mediaService.player,media);
        }
        function test_media_preferences_restore_without_saving_transient_players() {
            const writer=createTemporaryObject(persistentMedia,window,{bar:fakeBar});verify(writer!==null);
            tryVerify(()=>writer.ready,1000);writer.visualizer=false;writer.selectedId="test.transient";
            wait(700);
            const reader=createTemporaryObject(persistentMedia,window,{bar:fakeBar});verify(reader!==null);
            tryVerify(()=>reader.ready,1000);compare(reader.visualizer,false);compare(reader.selectedId,"");
            writer.destroy();reader.destroy();
        }
        function test_media_narrow_layout_keeps_lyrics_and_controls_inside_notch() {
            window.width=420;fakeBar.player=media;notch.pinned=true;
            const view=findChild(notch,"notchMusic");view.lyricsOpen=true;wait(40);
            verify(view.narrow);verify(notch.width<=396);verify(notch.height>180);
            const pane=findChild(notch,"notchLyricsPane"),toggle=findChild(notch,"notchMusicPlayPause");
            verify(pane.visible);const point=toggle.mapToItem(notch,0,0);
            verify(point.x>=0&&point.x+toggle.width*view.layoutScale<=notch.width);
            const playing=media.isPlaying;mouseClick(toggle);compare(media.isPlaying,!playing);
        }
        function test_media_output_and_visualizer_demand_lifecycle() {
            fakeBar.mediaService=mediaService;fakeBar.notchService=tools;fakeBar.player=media;notch.pinned=true;wait(40);
            mouseClick(findChild(notch,"notchMusicOutput"));wait(30);
            const menu=findChild(notch,"notchMediaOutput");verify(menu.opened);
            mouseClick(findChild(menu.contentItem,"notchMediaOutput2"));compare(fakeBar.sink.id,2);
            menu.close();wait(30);fakeBar.reduceMotion=false;
            tryCompare(mediaService,"spectrumClients",1);
            mouseClick(findChild(notch,"notchMusicLyrics"));tryCompare(mediaService,"spectrumClients",0);
            tryVerify(()=>findChild(notch,"notchMusic").lyricsOpen,1500);
            wait(300);mouseClick(findChild(notch,"notchMusicLyrics"));tryCompare(mediaService,"spectrumClients",1,1500);
            mouseMove(notch,notch.width/2,10);notch.pinned=true;
            notch.selectPage("pomodoro");tryCompare(mediaService,"spectrumClients",0,1500);
            fakeBar.reduceMotion=true;
        }
        function test_music_navigation_rail_without_player() {
            fakeBar.notchService=tools;fakeBar.player=null;notch.pinned=true;wait(40);
            const page=findChild(notch,"notchMediaTabpomodoro");verify(page.enabled);
            mouseClick(page);compare(notch.activity,"pomodoro");verify(notch.expanded);
            for(const entry of tools.state.menus.slice())if(entry!=="music")tools.setMenu(entry,false);
            compare(notch.activity,"music");compare(notch.navigationPages.length,1);
            verify(findChild(notch,"notchMusicDensity")===null);
            verify(findChild(notch,"notchMusicNextPage")===null);
        }
        function test_music_lyrics_consumer_is_independent() {
            fakeBar.player = media; notch.pinned = true;
            const lyrics = findChild(notch, "notchMusicLyrics");
            verify(lyrics.enabled);
            fakeWidgets.lyricsWanted = true;
            mouseClick(lyrics);
            verify(fakeWidgets.notchLyricsWanted);
            notch.close();
            verify(!fakeWidgets.notchLyricsWanted);
            verify(fakeWidgets.lyricsWanted, "Keep lyrics requested by desktop widgets");
        }
        function test_lyrics_view_survives_close_and_reopen() {
            fakeBar.player = media; notch.pinned = true;
            const view = findChild(notch, "notchMusic");
            mouseClick(findChild(notch, "notchMusicLyrics"));
            verify(notch.lyricsOpen);
            notch.close();
            verify(view.lyricsOpen, "Remember the selected lyrics view while collapsed");
            verify(!fakeWidgets.notchLyricsWanted, "Pause lyric requests while collapsed");
            compare(notch.width, 324);
            notch.pinned = true;
            verify(notch.lyricsOpen); compare(notch.width, 740);
            verify(findChild(notch, "notchMusicLyrics").filledIcon);
            verify(fakeWidgets.notchLyricsWanted);
            fakeBar.osdVisible = true;
            verify(view.visible && view.lyricsOpen,"Volume feedback must not replace lyrics");
            fakeBar.osdVisible = false; notch.heldFeedback = "";
            verify(view.visible && view.lyricsOpen, "Restore lyrics after temporary feedback");
            mouseClick(findChild(notch, "notchMusicLyrics"));
            notch.close(); notch.pinned = true;
            verify(!notch.lyricsOpen); compare(notch.width, 640);
        }
        function test_synced_lyrics_follow_and_seek() {
            fakeBar.player = media; notch.pinned = true;
            fakeWidgets.lyricsSynced = true;
            fakeWidgets.lyricsLines = [{t: 0, text: "Opening line"}, {t: 30, text: "Current verse"}, {t: 60, text: "Next verse"}];
            media.position = 45;
            mouseClick(findChild(notch, "notchMusicLyrics"));
            verify(notch.lyricsOpen);
            compare(notch.width, 740);
            const list = findChild(notch, "notchLyricsList");
            tryCompare(list, "currentIndex", 1);
            const current = findChild(notch, "notchLyricLine1");
            verify(current !== null && current.active);
            mouseClick(current);
            compare(media.position, 30);
            media.position = 65;
            tryCompare(list, "currentIndex", 2);
            verify(findChild(notch, "notchLyricLine2").active);
            mouseClick(findChild(notch, "notchMusicLyrics"));
            verify(!notch.lyricsOpen); compare(notch.width, 640);
        }
        function test_wrapped_lyrics_have_room_for_active_previous_and_next_lines() {
            fakeBar.player=media;notch.pinned=true;fakeWidgets.lyricsSynced=true;
            fakeWidgets.lyricsLines=[{t:0,text:"Yesterday we were far away"},{t:30,text:"If you believe me, I guess I'll get on a plane (make you mine)"},{t:60,text:"Tomorrow we'll begin again"}];
            media.position=45;
            const view=findChild(notch,"notchMusic");view.lyricsOpen=true;
            const pane=findChild(notch,"notchLyricsPane"),list=findChild(notch,"notchLyricsList");
            {
                wait(50);compare(notch.height,200);verify(pane.height>=140);
                tryCompare(list,"currentIndex",1);
                const current=findChild(notch,"notchLyricLine1");verify(current.height>45,"Exercise a wrapped lyric");
                tryVerify(()=>current.mapToItem(pane,0,0).y>=12 && current.mapToItem(pane,0,current.height).y<=pane.height-12,1000);
                const previous=findChild(notch,"notchLyricLine0"),next=findChild(notch,"notchLyricLine2");
                verify(previous.mapToItem(pane,0,previous.height).y>12,"Previous lyric remains visible");
                verify(next.mapToItem(pane,0,0).y<pane.height-12,"Next lyric remains visible");
            }
            view.lyricsOpen=false;compare(notch.height,160);
        }
        function test_lyrics_show_three_entries_with_larger_text_and_top_aligned_media() {
            fakeBar.player=media;notch.pinned=true;fakeWidgets.lyricsSynced=true;
            fakeWidgets.lyricsLines=Array.from({length:7},(_,index)=>({t:index*10,text:"Lyric number "+index}));
            media.position=35;
            const view=findChild(notch,"notchMusic");view.lyricsOpen=true;wait(70);
            compare(notch.height,200);
            for(let index=0;index<7;index++){
                const line=findChild(notch,"notchLyricLine"+index);
                if(index>=2&&index<=4){verify(line!==null);verify(line.inWindow);verify(line.opacity>0);}
                else if(line)compare(line.opacity,0);
            }
            verify(findChild(notch,"notchLyricWords3").font.pixelSize>=20);
            const cover=findChild(notch,"notchMusicCover");verify(cover.mapToItem(notch,0,0).y<60,"Media stays near the top rather than vertically centered");
            media.position=15;wait(40);
            verify(findChild(notch,"notchLyricLine1").active);
            verify(!findChild(notch,"notchLyricLine3").inWindow);
        }
        function test_lyrics_animate_scroll_focus_and_window_then_settle_on_seek() {
            fakeBar.player=media;notch.pinned=true;fakeWidgets.lyricsSynced=true;
            fakeWidgets.lyricsLines=Array.from({length:7},(_,index)=>({t:index*10,text:"Animated lyric "+index}));
            media.position=15;
            const view=findChild(notch,"notchMusic");view.lyricsOpen=true;wait(50);
            const list=findChild(notch,"notchLyricsList"),motion=findChild(notch,"notchLyricsScrollMotion");
            const oldWords=findChild(notch,"notchLyricWords1"),nextWords=findChild(notch,"notchLyricWords2");
            const startY=list.contentY;fakeBar.reduceMotion=false;media.position=25;
            tryVerify(()=>motion.running,200);wait(70);
            const targetY=list.currentItem.y-list.preferredHighlightBegin;
            verify(list.contentY>startY && list.contentY<targetY,"Lyrics must glide between playback positions");
            verify(oldWords.scale<1 && oldWords.scale>0.86,"Previous lyric shrinks gradually");
            verify(nextWords.scale>0.86 && nextWords.scale<1,"Active lyric grows gradually");
            verify(findChild(notch,"notchLyricLine0").windowOpacity>0,"Departing row fades instead of disappearing");
            tryVerify(()=>!motion.running,1000);fuzzyCompare(list.contentY,targetY,0.1);
            tryVerify(()=>findChild(notch,"notchLyricLine0").windowOpacity===0,700);
            media.position=45;wait(70);media.position=5;
            tryCompare(list,"currentIndex",0);tryVerify(()=>!motion.running,1000);
            fuzzyCompare(list.contentY,list.currentItem.y-list.preferredHighlightBegin,0.1);
            media.position=35;wait(50);fakeBar.reduceMotion=true;
            verify(!motion.running);fuzzyCompare(list.contentY,list.currentItem.y-list.preferredHighlightBegin,0.1);
        }
        function test_empty_and_plain_lyrics_keep_controls() {
            fakeBar.player = media; notch.pinned = true;
            fakeWidgets.lyricsLines = []; fakeWidgets.lyricsState = "loading";
            mouseClick(findChild(notch, "notchMusicLyrics"));
            const status = findChild(notch, "notchLyricsEmpty");
            verify(status.visible); compare(status.text, "Finding lyrics…");
            fakeWidgets.lyricsState = "none";
            compare(status.text, "No lyrics available for this track");
            fakeWidgets.lyricsLines = [{t: -1, text: "Unsynced first line"}, {t: -1, text: "Unsynced second line"}];
            verify(!status.visible);
            verify(findChild(notch, "notchLyricsList").interactive);
            const playing = media.isPlaying;
            mouseClick(findChild(notch, "notchMusicPlayPause"));
            compare(media.isPlaying, !playing);
        }
        function test_timer_and_record_controls() {
            fakeClock.timerActive = true; notch.pinned = true;
            mouseClick(button("Pause")); compare(fakeClock.timer.state, "paused");
            mouseClick(button("Resume")); compare(fakeClock.timer.state, "running");
            mouseClick(button("Cancel")); verify(!fakeClock.timerActive);
            fakeBar.recording = true;
            mouseClick(findChild(notch,"notchRecordingStop")); verify(!fakeBar.recording);
        }
        function downloadJob(id,state,exact) {
            return {id:id,path:"/tmp/Launch Assets.zip",name:"Launch Assets.zip",directory:"/home/test/Downloads",received:500000000,total:exact?1000000000:-1,progress:exact?.5:-1,eta:exact?4:-1,speed:exact?125000000:0,source:exact?"browser":"folder",state:state};
        }
        function test_nested_corner_geometry_in_both_notch_shapes() {
            for(const mode of ["attached","floating"]) for(const size of [.85,1,1.2]) {
                fakeBar.notchScale=size;
                fakeBar.notchMode=mode;fakeBar.notchService=tools;fakeBar.player=media;tools.setPage("music");notch.pinned=true;wait(20);
                const cover=findChild(notch,"notchMusicCover"),music=findChild(notch,"notchMusic"),rail=findChild(notch,"notchMediaRail");
                const wing=Geometry.wing(mode,1,true),left=cover.mapToItem(notch,0,0).x/music.layoutScale-wing;
                fuzzyCompare(cover.radius+left,notch.cornerRadius,.01);
                const right=rail.mapToItem(notch,rail.width,0).x;
                fuzzyCompare(rail.geometry.radius+(notch.width-right)/music.layoutScale-wing,notch.cornerRadius,.01);
                const selection=findChild(rail,"notchMediaSelection");verify(selection!==null);
                fuzzyCompare(selection.radius+rail.innerPadding,rail.geometry.radius,.01);
                fakeBar.player=null;fakeBar.downloadsService=downloadResults;
                downloadResults.accept({items:[downloadJob("corners","complete",true)]});wait(20);
                const tile=findChild(notch,"notchDownloadTile"),view=findChild(notch,"notchDownloads");
                const bottom=(notch.height-tile.mapToItem(notch,0,tile.height).y)/view.layoutScale;
                fuzzyCompare(tile.radius+bottom,notch.cornerRadius,.01);
                downloadResults.reset();fakeBar.downloadsService=null;fakeBar.recordingService=recordingResults;
                recordingResults.acceptInspection(recordingResult(),recordingResults.generation);wait(20);
                const watch=findChild(notch,"notchRecordingWatch"),recording=findChild(notch,"notchRecording");
                const bottomGap=(notch.height-watch.mapToItem(notch,0,watch.height).y)/recording.layoutScale;
                fuzzyCompare(watch.background.radius+bottomGap,notch.cornerRadius,.01);
                recordingResults.reset();fakeBar.recordingService=null;
                notch.selectPage("pomodoro");notch.pinned=true;wait(20);
                mouseClick(findChild(notch,"notchPomodoroSettings"));
                const popup=notch.settingsPopup;
                verify(popup!==null);compare(popup.cornerRadius,Geometry.controlRadius+popup.contentPadding);
                notch.close();
            }
        }
        function test_download_unknown_and_exact_progress_and_file_actions() {
            fakeBar.downloadsService=downloadResults;fakeBar.player=media;fakeBar.notchService=tools;
            downloadResults.accept({items:[downloadJob("one","active",false)]});
            compare(notch.activity,"downloads");compare(notch.width,324);verify(!notch.expanded);
            const view=findChild(notch,"notchDownloads");compare(view.progress,-1);verify(view.compactLabel.indexOf("MB")>=0);
            notch.pinned=true;compare(notch.width,520);compare(notch.height,120);
            verify(!findChild(notch,"notchDownloadOpen").enabled);
            downloadResults.accept({items:[downloadJob("one","active",true)]});compare(view.progress,.5);compare(view.compactLabel,"4 sec");
            downloadResults.accept({items:[downloadJob("one","complete",true)]});verify(downloadResults.feedback);verify(findChild(notch,"notchDownloadOpen").enabled);verify(view.complete);
            mouseClick(findChild(notch,"notchDownloadDismiss"));verify(!notch.expanded);compare(notch.activity,"music");verify(!downloadResults.active);
            downloadResults.accept({items:[downloadJob("one","complete",true)]});verify(!downloadResults.active);
        }
        function test_download_multiple_jobs_and_recording_alarm_priority() {
            fakeBar.downloadsService=downloadResults;
            const first=downloadJob("one","active",false),second=downloadJob("two","active",true);
            downloadResults.accept({items:[first,second]});compare(downloadResults.count,2);compare(notch.activity,"downloads");
            fakeBar.recording=true;compare(notch.activity,"recording");fakeBar.recording=false;compare(notch.activity,"downloads");
            fakeClock.ringing={kind:"timer"};compare(notch.activity,"timer");fakeClock.ringing=null;compare(notch.activity,"downloads");
            fakeBar.osdKind="brightness";fakeBar.osdVisible=true;notch.pinned=true;compare(notch.activity,"brightness");
            fakeBar.osdVisible=false;compare(notch.activity,"brightness");notch.close();compare(notch.activity,"downloads");
            downloadResults.dismiss();compare(downloadResults.current.id,"two");
            downloadResults.accept({items:[downloadJob("one","waiting",false),second]});compare(downloadResults.current.id,"two");
            downloadResults.dismiss();verify(!downloadResults.active);compare(notch.activity,"idle");
            downloadResults.accept({items:[downloadJob("one","complete",true)]});verify(downloadResults.feedback);verify(notch.expanded);
        }
        function test_download_completion_does_not_expand_higher_priority_activity() {
            fakeBar.downloadsService=downloadResults;fakeBar.recording=true;
            downloadResults.accept({items:[downloadJob("one","complete",true)]});
            compare(notch.activity,"recording");verify(downloadResults.feedback);verify(!notch.expanded);
            fakeBar.recording=false;compare(notch.activity,"downloads");verify(notch.expanded);
            downloadResults.reset();notch.close();fakeClock.ringing={kind:"timer"};
            downloadResults.accept({items:[downloadJob("two","saved",false)]});
            compare(notch.activity,"timer");verify(!notch.expanded);fakeClock.ringing=null;
            compare(notch.activity,"downloads");verify(notch.expanded);
        }
        function test_download_layout_fits_narrow_and_floating() {
            window.width=420;fakeBar.downloadsService=downloadResults;
            for(const mode of ["attached","floating"]) {
                fakeBar.notchMode=mode;downloadResults.accept({items:[downloadJob("one","saved",false)]});notch.pinned=true;wait(20);
                compare(notch.width,396);
                const name=findChild(notch,"notchDownloadName"),corner=name.mapToItem(notch,name.width,name.height);
                verify(corner.x<notch.width && corner.y<notch.height);
                const dismiss=findChild(notch,"notchDownloadDismiss"),end=dismiss.mapToItem(notch,dismiss.width,dismiss.height);
                verify(end.x<=notch.width && end.y<=notch.height);
                const view=findChild(notch,"notchDownloads");verify(view.done);verify(!view.complete);compare(view.progress,-1);
                downloadResults.reset();notch.close();
            }
        }
        function recordingResult() {
            return {ok:true,path:"/tmp/Launch demo.mp4",url:"file:///tmp/Launch%20demo.mp4",name:"Launch demo.mp4",directory:"/home/test/Videos",duration:3.5,thumbnail:""};
        }
        function test_recording_compact_live_and_finalizing_states() {
            fakeBar.notchService=tools;fakeBar.recordingService=recordingResults;
            fakeBar.recording=true;compare(notch.activity,"recording");compare(notch.width,324);verify(!notch.expanded);
            compare(findChild(notch,"notchRecordingCompactTime").text,"1:23");
            notch.pinned=true;compare(notch.width,520);compare(notch.height,120);
            const stop=findChild(notch,"notchRecordingStop");verify(stop.enabled);
            fakeBar.recRun=true;mouseClick(stop);verify(!fakeBar.recording);
            compare(notch.activity,"recording");verify(notch.recordingPending);verify(!stop.enabled);
            compare(findChild(notch,"notchRecordingElapsed").text,"Saving…");
            recordingResults.acceptInspection(recordingResult(),recordingResults.generation);fakeBar.recRun=false;
            compare(notch.width,580);compare(notch.height,184);verify(notch.expanded);
            compare(findChild(notch,"notchRecordingFilename").text,"Launch demo.mp4");
            compare(findChild(notch,"notchRecordingDuration").text,"0:03");
        }
        function test_recording_result_actions_and_dismissal_preserve_previous_page() {
            fakeBar.notchService=tools;fakeBar.player=media;fakeBar.recordingService=recordingResults;
            recordingResults.acceptInspection(recordingResult(),recordingResults.generation);
            compare(notch.activity,"recording");verify(notch.expanded);
            for(const name of ["Watch","Reveal","Copy","Trash"]){const control=findChild(notch,"notchRecording"+name);verify(control.visible&&control.enabled);}
            recordingResults.error="Unable to copy file";compare(notch.activity,"recording");verify(!!notch.recordingResult);
            mouseClick(findChild(notch,"notchRecordingDismiss"));verify(recordingResults.result===null);verify(!notch.expanded);compare(notch.activity,"music");
        }
        function test_recording_new_session_ignores_stale_results_and_missing_video_fails() {
            fakeBar.recordingService=recordingResults;const token=recordingResults.generation;
            fakeBar.recording=true;recordingResults.acceptInspection(recordingResult(),token);
            verify(recordingResults.result===null);fakeBar.recording=false;
            recordingResults.acceptInspection(recordingResult(),token);verify(recordingResults.result===null);
            recordingResults.finish("/tmp/macshell-no-such-recording.mp4");
            tryVerify(()=>!recordingResults.inspecting && recordingResults.error!=="",2000);
            verify(recordingResults.result===null);verify(notch.expanded);compare(notch.activity,"recording");
            verify(!findChild(notch,"notchRecordingWatch").visible);
            mouseClick(findChild(notch,"notchRecordingErrorClose"));verify(!notch.expanded);
        }
        function test_recording_layouts_fit_narrow_attached_and_floating_screens() {
            window.width=420;fakeBar.recordingService=recordingResults;
            for(const mode of ["attached","floating"]) {
                fakeBar.notchMode=mode;fakeBar.recording=true;notch.pinned=true;wait(20);
                verify(notch.width<=396);
                const stop=findChild(notch,"notchRecordingStop"),point=stop.mapToItem(notch,stop.width,stop.height);
                verify(point.x<=notch.width && point.y<=notch.height);
                fakeBar.recording=false;recordingResults.acceptInspection(recordingResult(),recordingResults.generation);wait(20);
                const trash=findChild(notch,"notchRecordingTrash"),end=trash.mapToItem(notch,trash.width,trash.height);
                verify(end.x<=notch.width && end.y<=notch.height);
                recordingResults.dismiss();
            }
        }
        function test_modes_size_and_availability() {
            compare(notch.y, 0);
            fakeBar.notchMode = "floating"; compare(notch.y, 7);
            notch.pinned = true; verify(notch.expanded);
            notch.available = false; verify(!notch.visible); verify(!notch.expanded);
            notch.available = true; fakeBar.notchScale = 0.85; notch.pinned = true;
            fuzzyCompare(notch.width, 306, 0.1); fuzzyCompare(notch.height, 175.1, 0.1);
        }
        function test_brightness_feedback_stays_while_adjusting() {
            fakeBar.osdKind="brightness";fakeBar.osdVisible = true;
            notch.pinned = true;
            compare(notch.activity, "brightness");
            fakeBar.osdVisible = false;
            compare(notch.activity, "brightness", "Keep controls mounted after hardware feedback times out");
            notch.close(); compare(notch.activity, "idle");
        }
        function test_animated_geometry_settles() {
            fakeBar.reduceMotion = false;
            notch.pinned = true;
            tryVerify(() => Math.abs(notch.width - 360) < 0.1 && Math.abs(notch.height - 206) < 0.1);
            notch.close();
            tryVerify(() => Math.abs(notch.width - 172) < 0.1);
        }
        function test_motion_reverses_cleanly_and_respects_reduced_motion() {
            fakeBar.player = media;
            tryCompare(notch, "shapeProgress", 0);
            tryCompare(notch, "revealProgress", 0);
            fakeBar.reduceMotion = false;
            notch.pinned = true;
            wait(70);
            verify(notch.width > 324 && notch.width < 650);
            verify(notch.revealProgress < 0.1, "Let the surface lead before revealing controls");
            notch.close();
            wait(60);
            notch.pinned = true;
            tryVerify(() => Math.abs(notch.width - 640) < 0.1 && Math.abs(notch.height - 160) < 0.1);
            tryCompare(notch, "revealProgress", 1);
            fuzzyCompare(notch.shapeProgress, 1, 0.001);
            notch.close();
            tryVerify(() => Math.abs(notch.width - 324) < 0.1 && Math.abs(notch.height - fakeBar.barHeight) < 0.1);
            compare(notch.revealProgress, 0);
            fakeBar.reduceMotion = true;
            notch.pinned = true;
            compare(notch.width, 640); compare(notch.height, 160);
            compare(notch.shapeProgress, 1); compare(notch.revealProgress, 1);
        }
        function test_page_transition_keeps_outgoing_until_faded() {
            fakeBar.notchService=tools; fakeBar.player=media; notch.pinned=true; notch.selectPage("music");
            compare(notch.activity,"music"); fakeBar.reduceMotion=false;
            notch.selectPage("pomodoro");
            compare(notch.requestedActivity,"pomodoro"); compare(notch.activity,"music");
            verify(notch.pageSwitching); verify(findChild(notch,"notchPageTransitionShield").visible);
            wait(45); verify(notch.pageOpacity>0 && notch.pageOpacity<1);
            compare(notch.activity,"music","Keep the outgoing title and controls during the fade");
            tryCompare(notch,"activity","pomodoro",500);
            verify(notch.pageOpacity<1); verify(notch.pageOffset>0);
            tryVerify(()=>!notch.pageSwitching,1000);
            compare(notch.pageOpacity,1); compare(notch.pageOffset,0);
            tryVerify(()=>Math.abs(notch.height-216)<0.1,1000);
            verify(!findChild(notch,"notchPageTransitionShield").visible);
        }
        function test_page_transition_rapid_navigation_and_reverse() {
            fakeBar.notchService=tools; notch.pinned=true; notch.selectPage("music"); fakeBar.reduceMotion=false;
            notch.selectPage("pomodoro"); wait(30); notch.selectPage("water"); wait(25); notch.selectPage("todo");
            compare(notch.requestedActivity,"todo");
            tryVerify(()=>notch.activity==="todo" && !notch.pageSwitching,1000);
            compare(tools.state.page,"todo"); verify(notch.pageOpacity===1 && notch.pageOffset===0);
            notch.selectPage("water"); tryCompare(notch,"activity","water",500);
            verify(notch.pageOffset<0,"Earlier pages enter from the left");
            notch.selectPage("music"); wait(30); notch.selectPage("water");
            tryVerify(()=>notch.activity==="water" && !notch.pageSwitching,1000);
            compare(notch.pageOpacity,1); compare(notch.pageOffset,0);
            notch.stepPage(1); notch.stepPage(1);
            compare(notch.requestedActivity,"todo","Repeated next-page actions follow the pending selection");
            tryVerify(()=>notch.activity==="todo" && !notch.pageSwitching,1000);
        }
        function test_close_never_flashes_generic_idle_placeholder() {
            fakeBar.notchService=tools;fakeBar.player=media;media.isPlaying=false;
            const fallback=findChild(notch,"notchFallbackContent");verify(fallback!==null);
            for(const mode of ["attached","floating"]) {
                fakeBar.reduceMotion=true;fakeBar.notchMode=mode;notch.pinned=true;notch.selectPage("music");
                fakeBar.reduceMotion=false;notch.close();
                compare(notch.activity,"idle");verify(!fallback.visible);verify(!fallback.enabled);
                wait(55);verify(notch.revealProgress>0,"Exercise the still-open closing shape");verify(!fallback.visible);
                wait(530);verify(!fallback.visible);
                fakeBar.reduceMotion=true;fakeBar.recordingService=recordingResults;
                recordingResults.acceptInspection(recordingResult(),recordingResults.generation);
                compare(notch.activity,"recording");verify(notch.expanded);
                fakeBar.reduceMotion=false;mouseClick(findChild(notch,"notchRecordingDismiss"));
                verify(!notch.expanded);verify(!fallback.visible);wait(60);verify(!fallback.visible);
                fakeBar.reduceMotion=true;fakeBar.recordingService=null;
            }
            notch.pinned=true;notch.selectPage("water");verify(!fallback.visible);
            fakeBar.osdKind="brightness";fakeBar.osdVisible=true;verify(fallback.visible,"Real brightness controls remain available");
            fakeBar.osdVisible=false;notch.close();verify(!fallback.visible);
        }
        function test_transition_content_stays_under_animated_shape_clip() {
            fakeBar.notchService=tools;fakeBar.recordingService=recordingResults;
            const clip=findChild(notch,"notchClippedSurface"),mask=findChild(notch,"notchContentMask");
            verify(clip!==null && mask!==null);verify(clip.clip);verify(notch.clip);
            verify(mask.parent===notch,"Mask must stay outside its captured contents");
            for(const name of ["notchMusic","notchRecording","notchPageContent","notchFallbackContent"]) {
                let item=findChild(notch,name);verify(item!==null);
                while(item && item!==clip)item=item.parent;
                verify(item===clip,"Every painted page must share the silhouette clip: "+name);
            }
            for(const mode of ["attached","floating"]) {
                fakeBar.reduceMotion=true;fakeBar.notchMode=mode;fakeBar.recording=true;notch.close();
                fakeBar.reduceMotion=false;notch.pinned=true;
                for(let frame=0;frame<5;frame++) {
                    wait(35);fuzzyCompare(mask.width,notch.width,0.01);fuzzyCompare(mask.height,notch.height,0.01);
                    fuzzyCompare(clip.width,notch.width,0.01);fuzzyCompare(clip.height,notch.height,0.01);
                }
                notch.close();wait(80);fuzzyCompare(mask.width,notch.width,0.01);fuzzyCompare(mask.height,notch.height,0.01);
                fakeBar.reduceMotion=true;fakeBar.recording=false;
            }
        }
        function test_page_transition_stops_on_close_and_reduced_motion() {
            fakeBar.notchService=tools; fakeBar.player=media; notch.pinned=true; notch.selectPage("music");
            fakeBar.reduceMotion=false; notch.selectPage("pomodoro"); wait(40); notch.close();
            verify(!notch.pageSwitching); compare(notch.pageOpacity,1); compare(notch.pageOffset,0);
            fakeBar.reduceMotion=true; notch.pinned=true; notch.selectPage("water");
            compare(notch.activity,"water"); verify(!notch.pageSwitching);
            compare(notch.pageOpacity,1); compare(notch.pageOffset,0);
            fakeBar.reduceMotion=false; notch.selectPage("shelf"); wait(40); fakeBar.reduceMotion=true;
            compare(notch.activity,"shelf"); verify(!notch.pageSwitching);
            compare(notch.pageOpacity,1); compare(notch.pageOffset,0);
        }
        function test_glass_material_lifecycle_and_accessibility() {
            fakeBar.player = media;
            verify(!notch.glassRequested);
            fakeBar.notchStyle = "glass";
            verify(notch.glassRequested); verify(!notch.glassNeeded);
            notch.pinned = true;
            verify(notch.glassNeeded);
            verify(!notch.glassRendered, "Software rendering uses the solid fallback");
            fakeBar.reduceTransparency = true;
            verify(!notch.glassRequested && !notch.glassNeeded);
            fakeBar.reduceTransparency = false; verify(notch.glassNeeded);
            notch.close(); verify(!notch.glassNeeded);
            fakeBar.notchStyle = "solid"; notch.pinned = true;
            verify(!notch.glassNeeded);
        }
        function test_glass_optics_follow_notch_geometry_and_material() {
            fakeBar.player=media;notch.pinned=true;
            const optical=createTemporaryObject(glassOpticsFixture,window,{host:notch,width:640,height:160});
            verify(optical!==null);const lens=findChild(optical,"notchGlassLens");const blur=findChild(optical,"notchGlassBlur");
            verify(lens.clearSrc!==null);compare(lens.src,lens.clearSrc);compare(optical.materialBlurRadius,notch.glassBlurRadius);compare(lens.rim,0);compare(lens.wingSize,24);compare(lens.radius,36);
            compare(lens.tintOpacity,notch.glassOpacity);compare(lens.liquidStrength,notch.glassLiquid);compare(blur.blur,optical.blurAmount);
            fakeBar.notchMode="floating";notch.pinned=true;compare(lens.wingSize,0);compare(lens.radius,36);
            fakeBar.notchMode="attached";notch.pinned=true;window.width=320;wait(30);
            verify(lens.wingSize>0 && lens.wingSize<24);verify(lens.radius>0 && lens.radius<36);
            notch.close();compare(lens.radius,12);
        }
        function test_glass_follows_shared_appearance_material_live() {
            const previousHub=fakeBar.hub,previousIntensity=Common.GlassMaterial.intensity;
            try {
                fakeBar.hub=({clock:fakeClock,widgets:fakeWidgets,dock:fakeGlassSettings});
                const optical=createTemporaryObject(glassOpticsFixture,window,{host:notch,width:640,height:160});
                verify(optical!==null);
                const blur=findChild(optical,"notchGlassBlur");
                let lastOpacity=-1,lastBlur=-1,lastLiquid=2;
                for(const amount of [0,0.25,0.5,0.75,1]) {
                    Common.GlassMaterial.intensity=amount;
                    compare(optical.materialBlurRadius,notch.glassBlurRadius);compare(blur.blur,optical.blurAmount);
                    verify(notch.glassOpacity>lastOpacity);verify(notch.glassBlurRadius>lastBlur);verify(notch.glassLiquid<lastLiquid);
                    lastOpacity=notch.glassOpacity;lastBlur=notch.glassBlurRadius;lastLiquid=notch.glassLiquid;
                }
                compare(notch.glassBlurRadius,80);compare(notch.glassOpacity,0.92);compare(notch.glassLiquid,0.35);
                Common.GlassMaterial.intensity=0;
                compare(notch.glassOpacity,0.42);compare(notch.glassBlurRadius,5);compare(notch.glassLiquid,1);
                compare(optical.materialBlurRadius,5);
                fakeGlassSettings.blur=0;compare(optical.materialBlurRadius,0);verify(!blur.blurEnabled);
                fakeGlassSettings.blur=5;compare(optical.materialBlurRadius,5);verify(blur.blurEnabled);
                fakeGlassSettings.opacity=0.7;fakeGlassSettings.blur=18;fakeGlassSettings.liquid=1.8;fakeGlassSettings.rim=0.75;fakeGlassSettings.grain=0.06;
                compare(notch.glassOpacity,0.7);compare(notch.glassBlurRadius,18);compare(notch.glassLiquid,1.8);compare(notch.glassRim,0.75);compare(notch.glassGrain,0.06);
                fakeBar.notchStyle="glass";fakeBar.player=media;notch.pinned=true;verify(notch.glassNeeded);
                fakeBar.reduceTransparency=true;verify(!notch.glassNeeded);compare(notch.glassBlurRadius,0);
                fakeBar.reduceTransparency=false;compare(notch.glassBlurRadius,18);
                fakeBar.hub=previousHub;Common.GlassMaterial.intensity=1;
                compare(notch.glassBlurRadius,80);compare(notch.glassOpacity,0.92);
            } finally {
                Common.GlassMaterial.intensity=previousIntensity;fakeBar.hub=previousHub;
                fakeGlassSettings.opacity=0.42;fakeGlassSettings.blur=5;fakeGlassSettings.liquid=1;fakeGlassSettings.rim=0.45;fakeGlassSettings.grain=0.03;
            }
        }
        function test_glass_does_not_wait_for_status_to_uncover_the_effect() {
            fakeBar.player = media; fakeBar.notchStyle = "glass"; notch.pinned = true;
            const loader = findChild(notch, "notchGlassLayer");
            const original = loader.sourceComponent;
            loader.sourceComponent = pendingShaderFixture;
            loader.active = true;
            tryVerify(() => loader.item !== null);
            verify(!loader.item.ready);
            verify(notch.glassRendered, "A pending packaged shader must be allowed to draw");
            loader.item.failed = true;
            verify(!notch.glassRendered, "A real shader failure restores the solid fallback");
            loader.active = false; loader.sourceComponent = original;
            loader.active = Qt.binding(() => notch.glassNeeded && notch.GraphicsInfo.api !== GraphicsInfo.Software);
        }
        function test_idle_eyes_moods_and_activity() {
            const eyes = findChild(notch, "notchIdle");
            verify(eyes.running && eyes.visible);
            compare(eyes.mood, "curious");
            eyes.idleSeconds = 46; compare(eyes.mood, "bored");
            const boredHeight = eyes.eyeHeight;
            eyes.idleSeconds = 121; compare(eyes.mood, "sleepy");
            verify(eyes.eyeHeight < boredHeight);
            eyes.wake(); compare(eyes.mood, "curious");
            eyes.glance(4, 1); compare(eyes.gazeX, 4);
            eyes.glance(0, 0);
            fakeBar.reduceMotion = false;
            eyes.glance(4, 1);
            verify(eyes.gazeX < 4, "Gaze should move smoothly rather than jump");
            tryCompare(eyes, "gazeX", 4, 1000);
            tryVerify(() => eyes.eyeOpen < 0.9, 7500, "Idle eyes should blink automatically");
            eyes.glance(-4, -1); wait(70);
            fakeBar.reduceMotion = true;
            compare(eyes.eyeOpen, 1); compare(eyes.gazeX, 0);
            fakeBar.player = media; verify(!eyes.running && !eyes.visible);
            media.isPlaying = false;
            compare(notch.activity, "idle"); verify(eyes.running);
            notch.pinned = true;
            compare(notch.activity, "music"); verify(!eyes.running);
            notch.close(); verify(eyes.running);
            fakeBar.notchIdleEyes = false; verify(!eyes.running && !eyes.visible);
        }
        function test_charging_feedback() {
            fakeBar.charging = true; verify(notch.chargingFeedback); compare(notch.activity, "charging");
        }
        function test_tools_page_navigation_and_reopen() {
            fakeBar.notchService = tools; notch.pinned = true;
            compare(notch.activity,"music"); compare(notch.navigationPages.length,8);
            wait(30);
            mouseClick(findChild(notch,"notchMediaTabpomodoro"));
            compare(notch.activity,"pomodoro"); compare(notch.width,520);
            notch.close(); compare(notch.activity,"idle");
            notch.pinned = true; compare(notch.activity,"pomodoro");
            notch.stepPage(1); compare(notch.activity,"water");
            tools.setMenu("water",false); compare(notch.activity,"music");
            verify(notch.navigationPages.indexOf("water")<0);
            fakeBar.osdVisible=true; compare(notch.activity,"music");
            fakeBar.osdVisible=false; compare(notch.activity,"music");
            notch.close(); notch.pinned=true; compare(notch.activity,"music");
            fakeClock.ringing={kind:"timer"}; compare(notch.activity,"timer");
        }
        function test_pomodoro_controls_and_elapsed_recovery() {
            fakeBar.notchService=tools; notch.pinned=true; notch.selectPage("pomodoro");
            const start=findChild(notch,"notchPomodoroToggle"); verify(start!==null);
            mouseClick(start); compare(tools.pomodoro.state,"running");
            notch.close(); compare(notch.activity,"pomodoro");
            let s=ToolsLogic.copy(tools.state); s.pomodoro.endAt=Date.now()-1000; s.pomodoro.completed=3;
            tools.state=s; tools.refresh();
            compare(tools.pomodoro.state,"finished"); compare(tools.pomodoro.completed,4);
            compare(tools.sessionsToday,1);
            tools.refresh(); compare(tools.pomodoro.completed,4);
            tools.togglePomodoro(); compare(tools.pomodoro.mode,"long"); compare(tools.pomodoro.state,"running");
            tools.togglePomodoro(); compare(tools.pomodoro.state,"paused");
            tools.resetPomodoro(); compare(tools.pomodoro.state,"idle");
        }
        function popupClick(name) {
            const popup=notch.settingsPopup, item=findChild(popup.contentItem,name);
            verify(item!==null,"Popup control exists: "+name);
            const view=popup.contentItem, point=item.mapToItem(view.contentItem,0,0);
            view.contentY=Math.max(0,Math.min(view.contentHeight-view.height,point.y-(view.height-item.height)/2));
            wait(25); mouseClick(item); wait(25);
        }
        function openPomodoroAdvanced() {
            mouseClick(findChild(notch,"notchPomodoroSettings"));wait(25);
            popupClick("notchPomodoroAdvanced");
        }
        function test_pomodoro_presets_target_and_layout() {
            window.height=620;
            fakeBar.notchService=tools;notch.pinned=true;notch.selectPage("pomodoro");wait(30);
            openPomodoroAdvanced();popupClick("notchPresetquick");compare(tools.pomodoro.mode,"quick");compare(tools.pomodoro.total,300000);
            openPomodoroAdvanced();popupClick("notchPresetcustom");compare(tools.pomodoro.mode,"custom");compare(tools.pomodoro.total,1800000);
            tools.addTask("Focus on this real task");const id=tools.state.tasks[0].id;
            openPomodoroAdvanced();popupClick("notchPomodoroLayout");
            verify(tools.pomodoro.targetsOpen);compare(notch.width,520);
            popupClick("notchSelectTarget"+id);compare(tools.pomodoro.targetId,id);notch.settingsPopup.close();
            tools.setPhase("focus");tools.togglePomodoro();tools.skipPomodoro();
            compare(tools.pomodoro.mode,"short");compare(tools.pomodoro.state,"running");compare(tools.pomodoro.completed,0);
            compare(tools.pomodoro.targetId,id);tools.removeTask(id);compare(tools.pomodoro.targetId,"");
        }
        function test_pomodoro_ruler_and_simple_states() {
            fakeBar.notchService=tools;notch.pinned=true;notch.selectPage("pomodoro");wait(30);
            compare(notch.width,520);compare(notch.height,216);
            const ruler=findChild(notch,"notchPomodoroRuler"),input=findChild(ruler,"notchPomodoroRulerInput");
            const waterReminder=tools.state.water.lastReminder,volume=fakeBar.volume;
            mouseClick(input,input.width/2+55,40);compare(tools.settings.focus,30);compare(tools.pomodoro.total,1800000);
            mousePress(input,input.width/2,40);verify(notch.interacting);
            mouseMove(input,input.width/2-110,40,20,Qt.LeftButton);mouseRelease(input,input.width/2-110,40);
            compare(tools.settings.focus,40);verify(!ruler.pressed);
            mouseWheel(input,input.width/2,40,0,120);compare(tools.settings.focus,41);compare(fakeBar.volume,volume);
            compare(tools.state.water.lastReminder,waterReminder);compare(notch.activity,"pomodoro");
            ruler.forceActiveFocus();keyClick(Qt.Key_End);compare(tools.settings.focus,180);keyClick(Qt.Key_Right);compare(tools.settings.focus,180);
            keyClick(Qt.Key_Home);compare(tools.settings.focus,1);keyClick(Qt.Key_Left);compare(tools.settings.focus,1);
            mouseClick(findChild(notch,"notchPresetshort"));compare(tools.pomodoro.mode,"short");compare(ruler.maximum,60);
            ruler.forceActiveFocus();keyClick(Qt.Key_End);compare(tools.settings.short,60);
            mouseClick(findChild(notch,"notchPresetfocus"));compare(tools.pomodoro.total,60000);
            const sound=findChild(notch,"notchPomodoroSound");mouseClick(sound);verify(!tools.settings.pomodoroSound);mouseClick(sound);verify(tools.settings.pomodoroSound);
            const toggle=findChild(notch,"notchPomodoroToggle");mouseClick(toggle);
            compare(tools.pomodoro.state,"running");compare(notch.width,480);compare(notch.height,96);
            compare(findChild(notch,"notchPomodoroPhaseLabel").text,"Focus");verify(!ruler.visible);
            tools.nowMs=tools.pomodoro.endAt-35000;compare(findChild(notch,"notchPomodoroTime").text,"00:35");
            mouseClick(toggle);compare(tools.pomodoro.state,"paused");compare(findChild(notch,"notchPomodoroPhaseLabel").text,"Paused");
            mouseClick(toggle);compare(tools.pomodoro.state,"running");
            mouseClick(findChild(notch,"notchPomodoroStop"));compare(tools.pomodoro.state,"idle");compare(notch.height,216);compare(tools.sessionsToday,0);
            mouseClick(findChild(notch,"notchPresetshort"));mouseClick(toggle);compare(findChild(notch,"notchPomodoroPhaseLabel").text,"Break");
        }
        function test_pomodoro_compact_controls_keep_timer_alive_on_hide() {
            fakeBar.notchService=tools;tools.togglePomodoro();notch.close();wait(30);
            compare(notch.activity,"pomodoro");compare(notch.width,324);compare(notch.height,28);
            mouseClick(findChild(notch,"notchPomodoroCompactToggle"));compare(tools.pomodoro.state,"paused");
            mouseClick(findChild(notch,"notchPomodoroCompactToggle"));compare(tools.pomodoro.state,"running");
            mouseClick(findChild(notch,"notchPomodoroCompactClose"));verify(tools.pomodoroDismissed);compare(tools.pomodoro.state,"running");compare(notch.activity,"idle");
            notch.pinned=true;notch.selectPage("pomodoro");verify(!tools.pomodoroDismissed);compare(tools.pomodoro.state,"running");
        }
        function test_focus_decision_apply_cancel_manage_and_rotation() {
            window.height=700;
            fakeBar.notchService=tools;notch.pinned=true;notch.selectPage("pomodoro");wait(30);
            openPomodoroAdvanced();popupClick("notchFocusDecision");wait(30);verify(notch.focusDecisionOpen);compare(notch.width,640);
            mouseClick(findChild(notch,"notchContextwater"));mouseClick(findChild(notch,"notchFocusDismiss"));
            verify(!notch.focusDecisionOpen);verify(tools.state.focus.contexts.indexOf("water")>=0);
            openPomodoroAdvanced();popupClick("notchFocusDecision");wait(30);
            mouseClick(findChild(notch,"notchManageActivities"));wait(30);
            mouseClick(findChild(notch.settingsPopup.contentItem,"notchManagePagewater"));mouseClick(findChild(notch,"notchActivitiesSave"));
            wait(30);
            verify(tools.state.menus.indexOf("water")<0);
            mouseClick(findChild(notch,"notchContextshelf"));mouseClick(findChild(notch,"notchContexttodo"));mouseClick(findChild(notch,"notchContextcalendar"));mouseClick(findChild(notch,"notchContextweather"));mouseClick(findChild(notch,"notchContextstats"));
            mouseClick(findChild(notch,"notchRotationToggle"));mouseClick(findChild(notch,"notchFocusAccept"));
            verify(!notch.focusDecisionOpen);verify(tools.state.focus.rotate);compare(tools.focusContexts.join(","),"music,pomodoro");
            mouseMove(notch,notch.width/2,12);
            tools.configureFocus(["music","pomodoro"],true,3);verify(tools.rotationRunning);
            tryVerify(()=>tools.state.page==="music",4000);
            notch.focusDecisionOpen=true;verify(!tools.rotationRunning);notch.focusDecisionOpen=false;
            notch.close();verify(!tools.rotationRunning);compare(tools.rotationClients,0);
        }
        function seedStats() {
            tools.stats.ingest(JSON.stringify({at:Date.now(),cpu:33,ram:59,gpu:null,disk:62,battery:null,network:23000000,upload:5500000,temperature:53,temperatureMax:80,temperatureCritical:100,gpuStatus:"Unsupported driver",batteryStatus:"No battery detected"}));
        }
        function test_stats_modes_selection_and_unknown_readings() {
            fakeBar.notchService=tools;notch.pinned=true;notch.selectPage("stats");wait(40);seedStats();
            compare(notch.activity,"stats");compare(notch.width,560);compare(notch.height,256);
            compare(tools.stats.clients,1);verify(!tools.stats.running);
            const main=findChild(notch,"notchStatsPrimaryValue");compare(main.reading.value,"33");
            mouseClick(findChild(notch,"notchStatsMinigpu"));compare(tools.state.stats.primary,"gpu");compare(main.reading.value,"—");
            mouseClick(findChild(notch,"notchStatsDetail"));compare(tools.state.stats.view,"detail");
            const right=findChild(notch,"notchStatsRightCard");compare(right.reading.value,"23");compare(right.reading.unit,"MB/s");
            tools.selectStatsMetric("secondary","gpu");compare(tools.state.stats.primary,"network");compare(tools.state.stats.secondary,"gpu");
            tools.stats.nowMs=Date.now()+4000;verify(!tools.stats.fresh);compare(right.reading.value,"—");
            notch.selectPage("todo");wait(30);compare(tools.stats.clients,0);
        }
        function test_stats_chooser_and_layout_at_narrow_sizes() {
            window.height=680;fakeBar.notchService=tools;notch.pinned=true;notch.selectPage("stats");wait(40);seedStats();
            mouseClick(findChild(notch,"notchStatsPrimaryChooser"));wait(30);
            const menu=findChild(notch,"notchStatsChooser"), option=findChild(menu.contentItem,"notchStatsOptiontemperature");
            verify(menu.visible);verify(option!==null);mouseClick(option);wait(30);
            compare(tools.state.stats.primary,"temperature");verify(!menu.visible);
            for(const mode of ["attached","floating"]){
                fakeBar.notchMode=mode;notch.pinned=true;notch.selectPage("stats");
                for(const width of [320,420,800]){
                    window.width=width;
                    for(const view of ["overview","detail"]){
                        tools.setStatsView(view);wait(10);verify(notch.width<=width);verify(notch.x>=0);
                        const plot=findChild(notch,view==="overview"?"notchStatsOverviewGraph":"notchStatsGraphprimary");
                        verify(plot.width>20);verify(plot.height>20);
                        const corner=plot.mapToItem(notch,plot.width,plot.height);verify(corner.x<=notch.width);verify(corner.y<=notch.height);
                    }
                }
            }
        }
        function test_stats_shared_reader_stops_after_final_client() {
            const service=createTemporaryObject(statsFixture,window,{enabled:true,commandOverride:["python3","-u","-c","import json,time; print(json.dumps({'at':time.time()*1000,'cpu':19}),flush=True); time.sleep(20)"]});
            verify(service!==null);verify(!service.running);service.clients=2;
            tryVerify(()=>service.fresh,1500);compare(service.snapshot.cpu,19);compare(service.history.length,1);
            const received=service.receivedAt;service.ingest("not json");service.ingest(JSON.stringify({at:Date.now()-130000,cpu:100}));compare(service.receivedAt,received);
            service.clients=1;verify(service.running);service.clients=0;tryVerify(()=>!service.running,1000);
        }
        function test_weather_layout_forecast_and_failure_states() {
            fakeBar.notchService=tools;notch.pinned=true;notch.selectPage("weather");wait(30);
            compare(notch.activity,"weather");compare(notch.width,560);compare(notch.height,256);
            compare(findChild(notch,"notchWeatherTemperature").text,"18°");
            const hours=findChild(notch,"notchWeatherHours");compare(hours.children.length,7);
            const card=findChild(notch,"notchWeatherCard");const sunny=String(card.color);
            fakeWidgets.wxInfo=({t:"Light Rain",k:"rain"});verify(String(card.color)!==sunny);
            fakeWidgets.wxReady=false;fakeWidgets.wxError="network failed";wait(20);
            verify(!findChild(notch,"notchWeatherTemperature").visible);mouseClick(findChild(notch,"notchWeatherRetry"));compare(fakeWidgets.refreshCalls,1);
            fakeWidgets.wxBusy=true;verify(!findChild(notch,"notchWeatherRetry").visible);
            fakeWidgets.wxReady=true;fakeWidgets.wxBusy=false;
            for(const mode of ["attached","floating"])for(const width of [320,420,1000]) {
                fakeBar.notchMode=mode;notch.pinned=true;window.width=width;wait(30);
                verify(notch.width<=width-24);const current=findChild(notch,"notchWeatherCard");const a=current.mapToItem(notch,0,0),b=current.mapToItem(notch,current.width,current.height);
                verify(a.x>=0 && a.y>=0 && b.x<=notch.width+1 && b.y<=notch.height+1);
            }
        }
        function test_weather_location_drafts_cancel_and_apply() {
            window.height=640;fakeBar.notchService=tools;notch.pinned=true;notch.selectPage("weather");wait(30);
            mouseClick(findChild(notch,"notchWeatherLocation"));popupClick("notchWeatherCityMode");
            findChild(notch.settingsPopup.contentItem,"notchWeatherCity").text="Amsterdam";popupClick("notchWeatherFahrenheit");popupClick("notchWeatherSettingsCancel");
            compare(fakeWidgets.locMode,"auto");compare(fakeWidgets.tempUnit,"C");compare(fakeWidgets.cityName,"");
            mouseClick(findChild(notch,"notchWeatherLocation"));popupClick("notchWeatherCityMode");
            const city=findChild(notch.settingsPopup.contentItem,"notchWeatherCity");city.text="   ";verify(!notch.settingsPopup.acceptable);city.text=" Amsterdam ";
            popupClick("notchWeatherFahrenheit");popupClick("notchWeatherSettingsSave");
            compare(fakeWidgets.locMode,"city");compare(fakeWidgets.cityName,"Amsterdam");compare(fakeWidgets.tempUnit,"F");compare(fakeWidgets.refreshCalls,1);
        }
        function test_calendar_navigation_examples_dates_and_expansion() {
            fakeBar.notchService=tools;notch.pinned=true;notch.selectPage("calendar");wait(30);
            compare(notch.activity,"calendar");compare(notch.width,560);compare(notch.height,256);
            tools.calendar.select(new Date(2026,9,25,12));wait(20);
            const list=findChild(notch,"notchCalendarAgenda");compare(list.count,4);compare(list.model[0].title,"Launch review");verify(list.model[0].example);
            mouseClick(findChild(notch,"notchCalendarDay2026-10-26"));compare(CalendarDates.key(tools.calendar.selectedDate),"2026-10-26");
            mouseClick(findChild(notch,"notchCalendarNext"));compare(CalendarDates.key(tools.calendar.visibleMonth),"2026-11-01");
            mouseClick(findChild(notch,"notchCalendarPrevious"));compare(CalendarDates.key(tools.calendar.visibleMonth),"2026-10-01");
            mouseClick(findChild(notch,"notchCalendarExpand"));compare(notch.width,760);compare(notch.height,340);verify(notch.calendarExpanded);
            mouseClick(findChild(notch,"notchCalendarExpand"));compare(notch.width,560);compare(notch.height,256);
            notch.close();notch.pinned=true;compare(notch.activity,"calendar");
        }
        function test_calendar_todo_and_editor_cancel_validation() {
            window.height=620;fakeBar.notchService=tools;notch.pinned=true;notch.selectPage("calendar");wait(30);
            tools.addTask("Send actual presentation");tools.calendar.today();wait(20);
            const id=tools.state.tasks[0].id;compare(findChild(notch,"notchCalendarAgenda").count,1);
            mouseClick(findChild(notch,"notchCalendarTask"+id));verify(tools.state.tasks[0].done);
            mouseClick(findChild(notch,"notchCalendarAdd"));wait(20);verify(notch.interacting);
            const popup=notch.settingsPopup;findChild(popup.contentItem,"notchCalendarTitle").text="Planning";
            findChild(popup.contentItem,"notchCalendarStart").text="12:00";findChild(popup.contentItem,"notchCalendarEnd").text="11:00";
            verify(!findChild(popup.contentItem,"notchCalendarEditorSave").enabled);
            popupClick("notchCalendarEditorCancel");compare(tools.state.tasks.length,1);compare(tools.calendar.events.length,0);
            mouseClick(findChild(notch,"notchCalendarAdd"));popupClick("notchCalendarTaskMode");
            findChild(notch.settingsPopup.contentItem,"notchCalendarTitle").text="Task from calendar";popupClick("notchCalendarEditorSave");
            compare(tools.state.tasks.length,2);compare(tools.state.tasks[0].text,"Task from calendar");
        }
        function test_calendar_local_storage_and_stale_month_requests() {
            const service=createTemporaryObject(calendarFixture,window,{databasePath:Quickshell.env("XDG_CONFIG_HOME")+"/calendar-test.db"});
            service.select(new Date(2026,9,25,12));service.enabled=true;tryVerify(()=>service.loadedMonth==="2026-10-01",3000);
            compare(service.events.length,0);verify(service.createEvent("Actual saved event","10:00","11:00"));
            tryVerify(()=>service.events.length===1,3000);compare(service.events[0].title,"Actual saved event");
            compare(CalendarDates.onDay(service.events,"2026-10-25").length,1);
            service.changeMonth(1);service.changeMonth(1);service.changeMonth(-2);
            tryVerify(()=>service.loadedMonth==="2026-10-01" && !service.busy,3000);compare(service.events.length,1);
            const reader=createTemporaryObject(calendarFixture,window,{databasePath:service.databasePath});reader.select(new Date(2026,9,25,12));reader.enabled=true;
            tryVerify(()=>reader.events.length===1,3000);compare(reader.events[0].title,"Actual saved event");
        }
        function test_calendar_layouts_fit_both_notch_positions() {
            fakeBar.notchService=tools;notch.pinned=true;notch.selectPage("calendar");wait(30);
            for(const mode of ["attached","floating"])for(const width of [320,1000])for(const expanded of [false,true]){
                fakeBar.notchMode=mode;notch.pinned=true;window.width=width;notch.calendarExpanded=expanded;
                tryVerify(()=>notch.width<=width-24,1000);wait(30);const grid=findChild(notch,"notchCalendarGrid");
                verify(grid.mapToItem(notch,0,0).x>=0);verify(grid.mapToItem(notch,grid.width,0).x<=notch.width+.1);
            }
        }
        function test_water_and_todo_actions() {
            fakeBar.notchService=tools; notch.pinned=true; notch.selectPage("water");
            mouseClick(findChild(notch,"notchDrink")); compare(tools.waterTotal,250);
            tools.undoDrink(); compare(tools.waterTotal,0);
            notch.selectPage("todo"); mouseClick(findChild(notch,"notchTodoAdd"));
            const editor=findChild(notch,"notchTodoEditor"); editor.text="Review the report";
            verify(notch.interacting); mouseClick(findChild(notch,"notchTodoSave"));
            compare(tools.state.tasks.length,1); verify(!notch.interacting);
            const id=tools.state.tasks[0].id; tools.toggleTask(id); compare(tools.doneToday,1);
            tools.editTask(id,"Review the final report"); compare(tools.state.tasks[0].text,"Review the final report");
            tools.removeTask(id); compare(tools.state.tasks.length,0);
        }
        function test_shelf_helper_and_reference_removal() {
            const url="file://"+tools.helper.replace(/bin\/notch_shelf.py$/,"NotchIcon.qml");
            tools.addShelf([url,url,"https://example.com/not-a-local-file"]);
            tryVerify(()=>tools.state.shelf.length===1,3000);
            compare(tools.state.shelf[0].name,"NotchIcon.qml"); verify(tools.error!=="");
            tools.removeShelf(url); compare(tools.state.shelf.length,0);
        }
        function test_tools_persistence_round_trip() {
            // The test's config folder is writable even when the source tree is read-only.
            const configPath=Quickshell.env("XDG_CONFIG_HOME")+"/notch-tools-test.json";
            const writer=createTemporaryObject(persistentTools,window,{storagePath:configPath});
            tryVerify(()=>writer.loaded,2000);
            writer.addTask("Keep this task after reload"); writer.setPage("shelf");
            writer.updateSettings({quick:12,custom:35});writer.setPhase("custom");
            writer.selectTarget(writer.state.tasks[0].id);writer.setPomodoroLayout(true);
            writer.configureFocus(["music","shelf"],true,7);
            wait(400);
            const reader=createTemporaryObject(persistentTools,window,{storagePath:configPath});
            tryVerify(()=>reader.loaded,2000);
            compare(reader.state.page,"shelf"); compare(reader.state.tasks[0].text,"Keep this task after reload");
            compare(reader.settings.quick,12);compare(reader.settings.custom,35);compare(reader.pomodoro.mode,"custom");
            verify(reader.pomodoro.targetsOpen);compare(reader.pomodoro.targetId,reader.state.tasks[0].id);
            compare(reader.state.focus.seconds,7);verify(reader.state.focus.rotate);
        }
        function test_tool_settings_validate_and_cancel_drafts() {
            window.height = 620;
            fakeBar.notchService=tools; notch.pinned=true; notch.selectPage("pomodoro"); wait(30);
            mouseClick(findChild(notch,"notchPomodoroSettings"));
            findChild(notch,"notchFocusMinutes").text="40";
            popupClick("notchPomodoroCancel"); compare(tools.settings.focus,25);
            mouseClick(findChild(notch,"notchPomodoroSettings"));
            const focus=findChild(notch,"notchFocusMinutes"); compare(focus.text,"25");
            focus.text="0"; verify(!findChild(notch,"notchPomodoroSave").enabled);
            focus.text="45"; popupClick("notchPomodoroSave"); compare(tools.settings.focus,45);
            notch.selectPage("water"); wait(30); mouseClick(findChild(notch,"notchWaterSettings"));
            findChild(notch,"notchWaterGoal").text="2250";
            mouseClick(findChild(notch,"notchWaterReminders")); verify(tools.settings.remind);
            mouseClick(findChild(notch,"notchWaterCancel")); compare(tools.settings.goal,1500);
            mouseClick(findChild(notch,"notchWaterSettings")); compare(findChild(notch,"notchWaterGoal").text,"1500");
            findChild(notch,"notchWaterGoal").text="2000";
            mouseClick(findChild(notch,"notchWaterSave")); compare(tools.settings.goal,2000);
        }
        function test_all_notch_dropdowns_share_frosted_surface() {
            window.height=760;fakeBar.notchService=tools;
            const previousIntensity=Common.GlassMaterial.intensity;
            try {
                const cases=[{page:"music",control:"notchMediaTabmore"},{page:"stats",control:"notchStatsPrimaryChooser"},{page:"weather",control:"notchWeatherLocation"},{page:"water",control:"notchWaterSettings"},{page:"pomodoro",control:"notchPomodoroSettings"},{page:"calendar",control:"notchCalendarAdd"},{page:"music",control:"notchMusicOutput"}];
                for(const entry of cases){
                    notch.pinned=true;notch.selectPage(entry.page);wait(35);
                    const control=findChild(notch,entry.control);verify(control!==null,entry.control);mouseClick(control);wait(25);
                    const menu=notch.settingsPopup;verify(menu!==null && menu.visible,entry.page);
                    compare(menu.background.objectName,"notchFrostedMenuSurface");
                    Common.GlassMaterial.intensity=0;compare(menu.backdropBlurRadius,42);
                    Common.GlassMaterial.intensity=1;compare(menu.backdropBlurRadius,80);
                    fakeBar.reduceTransparency=true;verify(menu.opaque);fakeBar.reduceTransparency=false;verify(!menu.opaque);
                    fakeBar.effDark=false;verify(!menu.dark);fakeBar.effDark=true;verify(menu.dark);
                    menu.close();wait(15);
                }
            } finally {Common.GlassMaterial.intensity=previousIntensity;fakeBar.reduceTransparency=false;fakeBar.effDark=true;notch.close();}
        }
        function test_dropdown_reuses_file_edit_menu_glass_material() {
            window.height=760;fakeBar.notchService=tools;notch.pinned=true;notch.selectPage("stats");wait(35);
            mouseClick(findChild(notch,"notchStatsPrimaryChooser"));wait(25);
            const menu=notch.settingsPopup,surface=menu.background,renderer=findChild(surface,"notchMenuFrostLayer");
            const previousHub=fakeBar.hub;
            try {
                fakeBar.hub=({clock:fakeClock,widgets:fakeWidgets,dock:fakeGlassSettings});
                // Load the copied menu component's fallback on the software
                // backend to verify shared parameters without a GPU shader.
                renderer.active=true;tryVerify(()=>renderer.item!==null,1000);
                const glass=renderer.item,border=findChild(surface,"notchMenuBarBorder");
                compare(glass.objectName,"notchMenuBarGlass");compare(glass.shaderUrl,menu.materialShader);verify(String(glass.shaderUrl).endsWith("notch-menu-tail-v1.frag.qsb"));
                compare(glass.tailHeight,9);compare(glass.pointerX,menu.pointerX);compare(glass.tailAmount,menu.tailAmount);
                menu.offsetX=45;compare(glass.tailAmount,0);compare(glass.pointerX,menu.pointerX);menu.offsetX=0;compare(glass.tailAmount,1);
                compare(glass.blur,42);compare(glass.thickness,22);compare(glass.strength,0.55*notch.glassLiquid);
                compare(glass.rimTint,1);compare(glass.ringW,1.4);compare(glass.rim,notch.glassRim);compare(glass.grain,notch.glassGrain);
                compare(glass.tint,notch.glassOpacity);compare(glass.cornerR,menu.cornerRadius);compare(border.tint,fakeBar.menuBorderColor);
                compare(glass.backdrop,findChild(surface,"notchMenuBackdrop").item);compare(glass.bx,surface.captureMargin);compare(glass.by,surface.captureMargin);
                fakeGlassSettings.opacity=0.67;fakeGlassSettings.liquid=1.6;compare(glass.tint,0.67);compare(glass.strength,0.55*1.6);
                fakeBar.effDark=false;verify(!glass.dark && !border.dark);fakeBar.effDark=true;verify(glass.dark && border.dark);
                glass.shaderError();verify(menu.glassFailed);verify(!glass.liquid);
            } finally {renderer.active=false;fakeBar.hub=previousHub;fakeGlassSettings.opacity=0.42;fakeGlassSettings.liquid=1;fakeBar.effDark=true;menu.close();notch.close();}
        }
        function test_dropdown_blur_composites_visible_notch_and_desktop() {
            window.height=760;fakeBar.notchService=tools;
            const desktop=createTemporaryObject(menuBackdropFixture,window);verify(desktop!==null);notch.backdrop=desktop;
            try {
                for(const mode of ["attached","floating"]){
                    fakeBar.reduceMotion=true;fakeBar.notchMode=mode;notch.pinned=true;notch.selectPage("stats");tools.setStatsView("detail");wait(40);
                    mouseClick(findChild(notch,"notchStatsChoosesecondary"));wait(25);
                    const menu=notch.settingsPopup,surface=menu.background,loader=findChild(surface,"notchMenuBackdrop"),frost=findChild(surface,"notchMenuFrostLayer");
                    verify(!loader.active);verify(!frost.active,"Software fallback does not allocate GPU blur");
                    loader.active=true;tryVerify(()=>loader.item!==null,1000);
                    try {
                        const top=findChild(loader.item,"notchMenuSurfaceCapture"),bottom=findChild(loader.item,"notchMenuDesktopCapture");
                        verify(top!==null && bottom!==null);compare(top.sourceItem,notch);verify(!top.hideSource);verify(top.live);
                        compare(bottom.sourceItem,desktop);verify(bottom.live);
                        verify(menu.parent===window.contentItem,"Dropdown must be outside the sampled notch");
                        fakeBar.reduceMotion=false;
                        for(const state of [{scale:1,progress:1,dx:0,dy:0},{scale:0.96,progress:0.85,dx:-20,dy:17},{scale:1,progress:1.03,dx:16,dy:8}]){
                            menu.scale=state.scale;menu.popProgress=state.progress;menu.offsetX=state.dx;menu.offsetY=state.dy;wait(20);
                            const a=surface.mapToItem(notch,0,0),b=surface.mapToItem(notch,surface.width,surface.height),sx=(b.x-a.x)/surface.width,sy=(b.y-a.y)/surface.height;
                            fuzzyCompare(top.sourceRect.x,a.x-surface.captureMargin*sx,0.1);fuzzyCompare(top.sourceRect.y,a.y-surface.captureMargin*sy,0.1);
                            fuzzyCompare(top.sourceRect.width,(surface.width+2*surface.captureMargin)*sx,0.1);fuzzyCompare(top.sourceRect.height,(surface.height+2*surface.captureMargin)*sy,0.1);
                            fuzzyCompare(bottom.sourceRect.x,top.sourceRect.x+notch.backdropPosition.x,0.1);fuzzyCompare(bottom.sourceRect.y,top.sourceRect.y+notch.backdropPosition.y,0.1);
                            compare(top.sourceRect.width,bottom.sourceRect.width);compare(top.sourceRect.height,bottom.sourceRect.height);
                            compare(loader.item.width,surface.width+2*surface.captureMargin);compare(loader.item.height,surface.height+2*surface.captureMargin);
                        }
                    } finally {menu.scale=1;fakeBar.reduceMotion=true;loader.active=Qt.binding(()=>frost.active);}
                    tryVerify(()=>loader.item===null,1000);menu.close();notch.close();
                }
            } finally {notch.backdrop=null;fakeBar.reduceMotion=true;notch.close();}
        }
        function test_settings_popover_portal_anchor_and_keyboard_dismissal() {
            window.height=400;
            fakeBar.notchService=tools; notch.pinned=true; notch.selectPage("pomodoro"); wait(30);
            mouseClick(findChild(notch,"notchPomodoroSettings")); wait(30);
            const popup=notch.settingsPopup;
            verify(popup!==null && popup.opened);
            verify(popup.parent===window.contentItem);
            const button=findChild(notch,"notchPomodoroSettings");
            const anchor=button.mapToItem(window.contentItem,button.width/2,button.height);
            fuzzyCompare(popup.y,anchor.y+4,0.5,"Portal opens directly below the Settings button");
            fuzzyCompare(popup.x+popup.pointerX,anchor.x,0.5,"Tail points at the button");
            verify(popup.y<notch.y+notch.height,"Portal can overlap the notch instead of clearing its bottom edge");
            compare(popup.tailHeight,9); compare(notch.height,216);
            verify(popup.y+popup.height<=window.height-8);
            verify(popup.contentItem.contentHeight>popup.contentItem.height,"Short screens scroll the form");
            verify(notch.interacting); verify(popup.focus);
            findChild(notch,"notchFocusMinutes").text="55";
            mouseMove(popup.contentItem,20,20); wait(750);
            verify(notch.expanded && popup.opened,"Editing keeps the notch open outside its bounds");
            keyClick(Qt.Key_Escape); tryVerify(()=>!notch.settingsPopupOpen,1000);
            compare(tools.settings.focus,25);
        }
        function test_settings_popover_outside_click_and_close_cleanup() {
            fakeBar.notchService=tools; notch.pinned=true; notch.selectPage("water"); wait(30);
            mouseClick(findChild(notch,"notchWaterSettings")); wait(30);
            verify(notch.settingsPopupOpen);
            const popup=notch.settingsPopup;
            const settingsButton=findChild(notch,"notchWaterSettings");
            const anchor=settingsButton.mapToItem(window.contentItem,settingsButton.width/2,settingsButton.height);
            fuzzyCompare(popup.x+popup.pointerX,anchor.x,0.5,"Tail tracks the Water Settings button after layout");
            fuzzyCompare(popup.y,anchor.y+4,0.5);
            findChild(notch,"notchWaterGoal").text="3000";
            mouseClick(window.contentItem,10,440);
            tryVerify(()=>!notch.settingsPopupOpen,1000); compare(tools.settings.goal,1500);
            notch.pinned=true; mouseClick(findChild(notch,"notchWaterSettings")); wait(30);
            compare(findChild(notch,"notchWaterGoal").text,"1500");
            verify(popup.opened); notch.close();
            tryVerify(()=>!notch.settingsPopupOpen,1000); verify(!popup.opened);
            compare(notch.settingsPopup,null);
        }
        function test_settings_popover_spring_open_and_reduced_motion() {
            window.height=620;
            fakeBar.notchService=tools; notch.pinned=true; notch.selectPage("pomodoro"); wait(30);
            fakeBar.reduceMotion=false;
            mouseClick(findChild(notch,"notchPomodoroSettings"));
            const popup=notch.settingsPopup; verify(popup!==null);
            verify(popup.elasticScaleY<1,"Popover unfolds from its button");
            let peak=popup.popProgress;
            for(let i=0;i<40;i++) { wait(25); peak=Math.max(peak,popup.popProgress); }
            verify(peak>1.005,"A physical spring overshoots before settling");
            tryVerify(()=>Math.abs(popup.popProgress-1)<0.002,2000);
            popup.close(); tryVerify(()=>!notch.settingsPopupOpen,1000);
            notch.pinned=true; mouseClick(findChild(notch,"notchPomodoroSettings")); wait(30);
            verify(popup.elasticScaleY<1); fakeBar.reduceMotion=true;
            compare(popup.elasticScaleX,1); compare(popup.elasticScaleY,1);
            compare(popup.popProgress,1);
            popup.close(); notch.pinned=true; mouseClick(findChild(notch,"notchPomodoroSettings")); wait(30);
            compare(popup.popProgress,1); compare(popup.elasticScaleY,1);
        }
        function test_settings_popover_header_drag_and_jelly_release() {
            window.height=620;
            fakeBar.notchService=tools; notch.pinned=true; notch.selectPage("water"); wait(30);
            mouseClick(findChild(notch,"notchWaterSettings")); wait(30);
            const popup=notch.settingsPopup;
            fakeBar.reduceMotion=false;
            const handle=findChild(notch,"notchWaterDragHandle"); verify(handle!==null);
            const point=handle.mapToItem(window.contentItem,80,12);
            const startX=popup.x,startY=popup.y;
            mousePress(handle,80,12);
            mouseMove(window.contentItem,point.x-35,point.y+20,30); wait(40);
            verify(popup.dragging); verify(Math.abs(popup.elasticX)+Math.abs(popup.elasticY)>0.1);
            mouseMove(window.contentItem,point.x-70,point.y+40,30);
            mouseRelease(window.contentItem,point.x-70,point.y+40);
            verify(!popup.dragging); verify(popup.x<startX-40 && popup.y>startY+20);
            compare(popup.tailAmount,0,"Dragging detaches the pointer from the button");
            tryVerify(()=>Math.abs(popup.jellyX)<0.03 && Math.abs(popup.jellyY)<0.03,2500);
            const field=findChild(notch,"notchWaterGoal"); field.text="2500";
            mouseClick(findChild(notch,"notchWaterSave")); compare(tools.settings.goal,2500);
            tryVerify(()=>!notch.settingsPopupOpen,1000); fakeBar.reduceMotion=true; notch.pinned=true;
            mouseClick(findChild(notch,"notchWaterSettings")); wait(30);
            compare(popup.offsetX,0); compare(popup.offsetY,0); compare(popup.tailAmount,1);
        }
        function test_music_tooltip_uses_dock_label_and_releases_on_close() {
            fakeBar.player=media; media.isPlaying=false; notch.pinned=true; wait(40);
            const play=findChild(notch,"notchMusicPlayPause");
            mouseMove(play,play.width/2,play.height/2);
            const tip=findChild(play,"notchMusicTooltipplay"); verify(tip!==null);
            tryVerify(()=>tip.opened,2000);
            compare(tip.text,"Play"); compare(tip.contentItem.tailHeight,7);
            verify(!tip.below); verify(!tip.contentItem.pointerUp);
            verify(tip.y + tip.height <= tip.anchorPoint.y - 5);
            verify(tip.parent===window.contentItem,"Render above the clipped notch contents");
            compare(notch.tooltipCount,1);
            fakeBar.reduceTransparency=true; verify(!notch.tooltipGlassNeeded);
            notch.close(); tryCompare(notch,"tooltipCount",0,1000);
        }
        function test_tooltip_refraction_composites_notch_without_capturing_popup() {
            fakeBar.player=media;notch.pinned=true;wait(40);
            const control=findChild(notch,"notchMusicNext"),tip=findChild(control,"notchMusicTooltipnext");
            mouseMove(control,control.width/2,control.height/2);tryVerify(()=>tip.opened,2000);
            const bubble=tip.contentItem,loader=findChild(bubble,"notchTooltipBackdrop");
            verify(!loader.active,"Software fallback should not allocate glass captures");
            // Exercise capture wiring without asking the software renderer to
            // execute a GPU-only shader. Production enables both together.
            bubble.glassFailed=true;bubble.liquid=true;
            try {
                tryVerify(()=>loader.item!==null,1000);
                const surface=findChild(loader.item,"notchTooltipSurfaceCapture");
                verify(surface!==null);compare(surface.sourceItem,notch);verify(!surface.hideSource);
                verify(tip.parent===window.contentItem,"Popup must stay outside its sampled notch");
                for(const scale of [0.96,1]) {
                    tip.scale=scale;wait(20);
                    const start=bubble.mapToItem(notch,0,0),end=bubble.mapToItem(notch,bubble.width,bubble.height);
                    fuzzyCompare(surface.sourceRect.x,start.x-bubble.captureMargin*(end.x-start.x)/bubble.width,0.1);
                    fuzzyCompare(surface.sourceRect.y,start.y-bubble.captureMargin*(end.y-start.y)/bubble.height,0.1);
                    fuzzyCompare(surface.sourceRect.width,(bubble.width+2*bubble.captureMargin)*(end.x-start.x)/bubble.width,0.1);
                    compare(bubble.backdrop,loader.item);compare(bubble.backdropOrigin.x,bubble.captureMargin);
                }
            } finally {tip.scale=1;bubble.liquid=false;bubble.glassFailed=false;}
            tryVerify(()=>loader.item===null,1000);notch.close();tryCompare(notch,"tooltipCount",0,1000);
        }
        function test_top_button_tooltip_flips_below_with_upward_tail() {
            fakeBar.notchService=tools; notch.pinned=true; notch.selectPage("pomodoro"); wait(40);
            const control=findChild(notch,"notchPresetfocus");
            const popup=findChild(control,"notchTooltip"); verify(popup!==null);
            mouseMove(control,control.width/2,control.height/2);
            tryVerify(()=>popup.opened,2000);
            verify(popup.below); verify(popup.contentItem.pointerUp);
            verify(popup.y >= popup.bottomAnchor.y + 5);
            verify(popup.y + popup.height <= window.height - 8);
            compare(popup.transformOrigin,Item.Top);
            notch.close(); tryCompare(notch,"tooltipCount",0,1000);
        }
        function test_disabled_music_buttons_still_show_tooltips() {
            fakeBar.notchService=tools; fakeBar.player=null; notch.pinned=true;
            notch.selectPage("music"); wait(40);
            for (const entry of [{button:"notchMusicPlayPause",symbol:"play",text:"Play"},
                                 {button:"notchMusicPrevious",symbol:"previous",text:"Previous track"},
                                 {button:"notchMusicNext",symbol:"next",text:"Next track"}]) {
                const control=findChild(notch,entry.button); verify(!control.enabled);
                mouseMove(control,control.width/2,control.height/2);
                const tip=findChild(control,"notchMusicTooltip"+entry.symbol);
                tryVerify(()=>tip.opened,2000); compare(tip.text,entry.text);
                verify(tip.hovered); verify(!control.enabled);
                mouseMove(window.contentItem,0,450); tryVerify(()=>!tip.visible,1000);
                // Keep the notch open across the next button's hover delay.
                mouseMove(notch,notch.width/2,12);
            }
            notch.close(); tryCompare(notch,"tooltipCount",0,1000);
        }
        function test_bluetooth_connection_feedback_is_not_a_page() {
            fakeBar.notchService=tools; notch.pinned=true; notch.selectPage("todo");
            verify(notch.navigationPages.indexOf("bluetooth")<0); verify(!notch.deviceFeedbackActive);
            const first=fakeBar.btDevices[0];
            fakeBar.btDevices=[first,{mac:"AA:BB:01",name:"New earbuds",icon:"headphones",connected:true,bat:"70"}];
            compare(tools.deviceEvent,"bluetooth"); compare(notch.activity,"bluetooth");
            verify(notch.expanded); compare(notch.height,136); compare(tools.feedbackDevice.name,"New earbuds");
            compare(tools.state.page,"todo"); verify(notch.navigationPages.indexOf("bluetooth")<0);
            tools.dismissDeviceEvent(); compare(notch.activity,"todo");
            fakeBar.btDevices=[first,{mac:"AA:BB:01",name:"New earbuds",icon:"headphones",connected:true,bat:"60"}];
            compare(tools.deviceEvent,"","Battery updates must not trigger connection feedback");
            fakeBar.btDevices=fakeBar.btDevices.concat([{mac:"AA:BB:02",name:"Mouse",icon:"mouse",connected:true,bat:"80"}]);
            compare(tools.feedbackDevice.name,"Mouse");
            fakeBar.btDevices=fakeBar.btDevices.filter(d=>d.mac!=="AA:BB:02");
            compare(tools.deviceEvent,""); compare(notch.activity,"todo");
        }
        function test_device_connection_collapses_to_battery_glance_then_expires() {
            fakeBar.notchService=tools;tools.setPage("shelf");wait(30);tools.deviceExpandedMs=180;tools.deviceCompactMs=700;
            fakeBar.btDevices=fakeBar.btDevices.concat([{mac:"AA:01",name:"AirPods Pro",icon:"headphones",connected:true,bat:"80"}]);
            compare(notch.width,520);compare(notch.height,136);compare(findChild(notch,"notchDeviceStatus").text,"Connected");
            compare(findChild(notch,"notchDeviceBattery").percent,80);
            tryVerify(()=>!tools.deviceEventExpanded,1000);verify(!notch.expanded);compare(notch.width,324);
            compare(findChild(notch,"notchDeviceCompactArt").kind,"earbuds");compare(findChild(notch,"notchDeviceCompactBattery").percent,80);
            tryVerify(()=>tools.deviceEvent==="",1500);compare(notch.activity,"idle");compare(tools.state.page,"shelf");
        }
        function test_device_battery_glance_can_reopen_and_dismiss() {
            fakeBar.notchService=tools;tools.showDeviceEvent("bluetooth",{mac:"AA:01",name:"AirPods Pro",icon:"headphones",bat:"80"});
            tools.advanceDeviceEvent();verify(!notch.expanded);compare(notch.activity,"bluetooth");
            notch.toggle();verify(notch.expanded);verify(tools.deviceEventExpanded);compare(notch.height,136);
            notch.toggle();compare(tools.deviceEvent,"");verify(!notch.expanded);
        }
        function test_device_low_battery_alerts_follow_thresholds_without_repeating() {
            fakeBar.notchService=tools;
            const original=fakeBar.btDevices[0];
            function report(percent){fakeBar.btDevices=[Object.assign({},original,{bat:percent})];}
            report("20");compare(tools.deviceEventReason,"low");compare(findChild(notch,"notchDeviceStatus").text,"Battery low");compare(findChild(notch,"notchDeviceBattery").percent,20);
            tools.dismissDeviceEvent();report("19");compare(tools.deviceEvent,"");report("21");report("20");compare(tools.deviceEvent,"");
            report("10");compare(tools.deviceEventReason,"low");compare(findChild(notch,"notchDeviceBattery").percent,10);
            tools.dismissDeviceEvent();report("9");compare(tools.deviceEvent,"");report("26");report("20");compare(tools.deviceEventReason,"low");
            report("0");compare(findChild(notch,"notchDeviceBattery").percent,0);report("");compare(findChild(notch,"notchDeviceBattery").percent,-1);
        }
        function test_device_queue_disconnect_and_feedback_priority() {
            fakeBar.notchService=tools;const original=fakeBar.btDevices[0];
            const keyboard={mac:"AA:01",name:"G915",systemIcon:"input-keyboard",connected:true,bat:"60"};
            const mouse={mac:"AA:02",name:"MX Master",systemIcon:"input-mouse",connected:true,bat:"85"};
            fakeBar.btDevices=[original,keyboard,mouse];compare(tools.feedbackDevice.name,"G915");compare(tools.deviceEventQueue.length,1);
            fakeBar.btDevices=[original,mouse];compare(tools.feedbackDevice.name,"MX Master");compare(tools.deviceEventQueue.length,0);
            fakeBar.recording=true;compare(notch.activity,"recording");verify(!notch.deviceFeedbackActive);
            fakeClock.ringing={kind:"timer"};compare(notch.activity,"timer");fakeClock.ringing=null;fakeBar.recording=false;compare(notch.activity,"bluetooth");
            fakeBar.btOn=false;compare(tools.deviceEvent,"");compare(tools.deviceEventQueue.length,0);
        }
        function test_device_cards_fit_shapes_scales_and_unknown_batteries() {
            fakeBar.notchService=tools;window.width=320;wait(40);
            for(const mode of ["attached","floating"])for(const scale of [.85,1,1.2]){
                fakeBar.notchMode=mode;fakeBar.notchScale=scale;
                tools.showDeviceEvent("bluetooth",{mac:"AA:01",name:"Wireless Controller with a long name",systemIcon:"input-gaming",bat:""});wait(30);
                verify(notch.width<=296);const art=findChild(notch,"notchDeviceArt"),battery=findChild(notch,"notchDeviceBattery");
                compare(art.kind,"gamepad");compare(battery.percent,-1);
                verify(art.mapToItem(notch,0,0).x>=0);verify(battery.mapToItem(notch,battery.width,battery.height).x<=notch.width+.1);
                verify(battery.mapToItem(notch,0,battery.height).y<=notch.height+.1);
            }
        }
        function test_charging_feedback_expires_and_restores_last_page() {
            fakeBar.notchService=tools; tools.setPage("shelf");
            fakeBar.charging=true;
            compare(notch.activity,"charging"); verify(notch.expanded);
            verify(notch.navigationPages.indexOf("charging")<0);
            compare(tools.state.page,"shelf");
            tryVerify(()=>!notch.deviceFeedbackActive && !notch.expanded,5500);
            compare(notch.activity,"idle","A connected charger must not occupy the idle notch indefinitely");
            notch.pinned=true; compare(notch.activity,"shelf"); notch.close();
            fakeBar.charging=false; fakeBar.charging=true; compare(notch.activity,"charging");
            fakeBar.charging=false; verify(!notch.deviceFeedbackActive); verify(!notch.expanded);
        }
        function test_existing_bluetooth_devices_do_not_alert_on_initial_scan() {
            fakeBar.notchService=tools; tools.bluetoothPrimed=false; fakeBar.btReady=false;
            fakeBar.btDevices=[{mac:"AA:00",name:"Existing device",icon:"headphones",connected:true,bat:"50"}];
            compare(tools.deviceEvent,""); fakeBar.btReady=true;
            compare(tools.deviceEvent,""); verify(!notch.expanded);
            fakeBar.btOn=false; fakeBar.btDevices=[]; fakeBar.btOn=true;
            fakeBar.btDevices=[{mac:"AA:00",name:"Existing device",icon:"headphones",connected:true,bat:"50"}];
            compare(notch.activity,"bluetooth"); verify(notch.expanded);
            fakeBar.btOn=false; compare(tools.deviceEvent,""); verify(!notch.expanded);
        }
    }
}
