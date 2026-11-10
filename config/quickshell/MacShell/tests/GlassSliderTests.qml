pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import "../Common" as Common
import ".." as Shell
import "../UpstreamBar" as Upstream

Window {
    id: window
    visible: true
    width: 640; height: 650
    property real modelValue: 0.5
    Common.GlassSlider {
        id: slider
        x: 30; y: 20; width: 300; height: 32
        from: -1; to: 1; stepSize: 0.1
        value: window.modelValue
        onMoved: window.modelValue = value
    }
    Shell.PlayerWidget {
        id: player
        x: 20; y: 90
        size: "medium"; hasPlayer: true; canSeek: true
        title: "Local test"; length: 240; position: 60
    }
    Upstream.PlayerWidget {
        id: upstreamPlayer
        x: 20; y: 280
        size: "medium"; hasPlayer: true; canSeek: true
        title: "Local test"; length: 240; position: 60
    }
    QtObject {
        id: cornerHost
        property real cornerSquircle: 0.4
        property real effGlassOpacity: 0.42
        property real effGlassBlur: 5
        property real effGlassLiquid: 1
        property real effGlassRim: 0.45
    }
    Shell.CornerSmoothingSettingsRow {
        id: corner
        x: 10; y: 480; width: 600
        host: cornerHost
        t: QtObject {
            property bool dark: false
            property string fam: "sans-serif"
            property color text: "#222222"
            property color text2: "#777777"
            property color accent: "#007aff"
            property color track: "#bbbbbb"
            property color sep: "#dddddd"
        }
    }
    SignalSpy { id: seekSpy; target: player; signalName: "seek" }
    TestCase {
        name: "CapsuleSliders"
        when: window.visible
        onCompletedChanged: if (completed) console.log("TOTALS", qtest_results.passCount, "passed,", qtest_results.failCount, "failed")
        function cleanup() { console.log("RESULT", qtest_results.functionName, qtest_results.failed ? "FAIL" : "PASS"); }
        function init() {
            slider.enabled = true;
            window.modelValue = 0;
            Common.DesktopPreferences.setValue("reduceMotion", false);
            Common.DesktopPreferences.setValue("reduceTransparency", false);
            for (const widget of [player, upstreamPlayer]) {
                widget.preview = false;
                widget.seeking = false;
                widget.seekHold = false;
            }
            seekSpy.clear();
            const closingLyrics = player.lyricsOn;
            player.lyricsOn = false;
            if (closingLyrics) wait(450);
            player.lyrics = [];
            player.lyricsSynced = false;
        }
        function test_scale_and_value_binding() {
            verify(slider.handle.width > slider.handle.height * 1.4);
            fuzzyCompare(slider.handle.scale, 1, 0.001);
            const original = slider.value;
            mousePress(slider, slider.knobCenter, slider.height / 2);
            compare(slider.value, original, "Scaling must not move the value");
            tryVerify(() => slider.handle.scale > 1.2);
            mouseMove(slider, slider.width - slider.handle.width / 2, slider.height / 2, 10, Qt.LeftButton);
            compare(window.modelValue, 1);
            mouseRelease(slider, slider.width - slider.handle.width / 2, slider.height / 2);
            tryVerify(() => Math.abs(slider.handle.scale - 1) < 0.001);
            window.modelValue = -0.3;
            compare(slider.value, -0.3, "External settings remain bound after a drag");
            slider.forceActiveFocus();
            keyClick(Qt.Key_Right);
            fuzzyCompare(window.modelValue, -0.2, 0.001);
        }
        function test_accessibility() {
            Common.DesktopPreferences.setValue("reduceMotion", true);
            Common.DesktopPreferences.setValue("reduceTransparency", true);
            mousePress(slider, slider.knobCenter, slider.height / 2);
            compare(slider.pressProgress, 1);
            const effect = findChild(slider, "glassSliderPressedEffect");
            verify(!effect.active);
            mouseRelease(slider, slider.knobCenter, slider.height / 2);
            compare(slider.pressProgress, 0);
            slider.enabled = false;
            mouseClick(slider, slider.width - 1, slider.height / 2);
            compare(window.modelValue, 0);
        }
        function test_corner_setting() {
            const control = findChild(corner, "continuousCornerSlider");
            verify(control.handle.width > control.handle.height);
            mouseDrag(control, control.knobCenter, control.height / 2, control.width, 0);
            compare(cornerHost.cornerSquircle, 1);
            cornerHost.cornerSquircle = 0.23;
            compare(control.value, 0.23);
        }
        function test_media_seek() {
            for (const widget of [player, upstreamPlayer]) {
                seekSpy.target = widget;
                seekSpy.clear();
                const control = findChild(widget, "mediaSeekSlider");
                verify(control !== null && control.enabled);
                mousePress(control, control.knobCenter, control.height / 2);
                verify(control.pressed);
                tryVerify(() => control.handle.scale > 1.2);
                const targetX = control.handle.width / 2 + (control.width - control.handle.width) * 0.75;
                mouseMove(control, targetX, control.height / 2, 10, Qt.LeftButton);
                compare(seekSpy.count, 0, "Do not issue remote seeks during a drag");
                mouseRelease(control, targetX, control.height / 2);
                compare(seekSpy.count, 1);
                fuzzyCompare(seekSpy.signalArguments[0][0], widget.length * 0.75, widget.length / (control.width - control.handle.width));
                widget.preview = true;
                verify(!control.enabled);
                mouseClick(control, control.width / 2, control.height / 2);
                compare(seekSpy.count, 1, "Gallery previews must not seek the player");
            }
        }
        function test_desktop_lyrics_follow_seek_and_plain_scroll_with_blur() {
            player.lyrics = Array.from({length:7},(_,index)=>({t:index*10,text:"Desktop lyric "+index}));
            player.lyricsState = "ok";player.lyricsSynced = true;player.position = 15;
            player.lyricsOn = true;wait(750);
            const list=findChild(player,"desktopLyricsList");
            const first=findChild(player,"desktopLyricLine1");
            const next=findChild(player,"desktopLyricLine2");
            compare(list.currentIndex,1);verify(first.cur);verify(first.bl<0.001);verify(next.bl>0.13);
            const start=list.contentY;player.position=25;wait(50);
            verify(list.contentY>start && list.contentY<list.currentItem.y-list.preferredHighlightBegin);
            verify(first.bl>0 && first.bl<0.14);verify(next.bl>0 && next.bl<0.14);
            tryVerify(()=>next.bl<0.001);
            player.position=5;tryCompare(list,"currentIndex",0);
            tryVerify(()=>!findChild(player,"desktopLyricsScrollMotion").running,1500);
            fuzzyCompare(list.contentY,list.currentItem.y-list.preferredHighlightBegin,0.1);
            player.lyricsSynced=false;
            list.contentY=next.y-list.preferredHighlightBegin;wait(700);
            compare(list.currentIndex,2);verify(next.cur);verify(next.bl<0.001);verify(first.bl>0.13);
        }
    }
}
