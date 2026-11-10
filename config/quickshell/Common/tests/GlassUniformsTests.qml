import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import ".." as Common
import "../../MacLock" as Lock
import "../../MacShell" as Shell
import "../../launchpad/components" as Launchpad

Window {
    id: window
    width: 600; height: 360; visible: true
    Rectangle { id: backdrop; anchors.fill: parent; color: "#6089ad" }
    ShaderEffectSource { id: texture; sourceItem: backdrop; visible: false }
    Common.LiquidGlassSurface { id: dock; width: 180; height: 48; src: texture }
    Lock.Glass { id: password; y: 70; width: 180; height: 36; src: texture; frame: window.contentItem; cornerSmoothing: 0 }
    Lock.Glass { id: notification; y: 120; width: 280; height: 72; src: texture; frame: window.contentItem }
    Launchpad.SearchGlassSurface { id: search; y: 210; width: 240; height: 40 }
    Common.FrostedMenuSurface { id: menu; x: 320; width: 180; height: 130; backdrop: backdrop }
    Shell.GlassMaterialTile {
        id: preview
        x: 320; y: 160
        t: QtObject {
            property bool dark: true
            property color text: "white"
            property color text2: "#bbbbbb"
            property color cardBorder: "#777777"
            property string fam: "sans-serif"
        }
    }
    FileView {
        id: settings
        path: Quickshell.env("XDG_CONFIG_HOME") + "/macdock/settings.json"
        printErrors: false
    }
    FileView {
        id: preference
        path: Quickshell.env("XDG_CONFIG_HOME") + "/macshell/liquidglass.json"
        printErrors: false
    }
    TestCase {
        name: "SharedGlassUniforms"
        when: window.visible
        onCompletedChanged: if (completed) console.log("GLASS_TOTALS", qtest_results.passCount, "passed,", qtest_results.failCount, "failed")
        function cleanup() { console.log("RESULT", qtest_results.functionName, qtest_results.failed ? "FAIL" : "PASS"); }
        function init() {
            Common.DesktopPreferences.setValue("reduceTransparency", false);
            Common.DesktopPreferences.setValue("increaseContrast", false);
            Common.GlassMaterial.setIntensity(0);
            settings.setText(JSON.stringify({glassLiquid:0.5,glassOpacity:0,glassBlur:0,glassRim:0.55,glassGrain:0}));
            tryCompare(Common.GlassMaterial, "baseLiquid", 0.5);
            tryCompare(Common.GlassMaterial, "baseOpacity", 0);
        }
        function surfaces() {
            return [dock, search, findChild(password,"sharedLiquidGlassSurface"), findChild(notification,"sharedLiquidGlassSurface")];
        }
        function assertShared() {
            for (const surface of surfaces()) {
                verify(surface !== null);
                // Each config root owns a singleton instance; file watchers
                // propagate the shared preference across those roots.
                for (const key of ["thickness","dispersion","magnify","tintMix","rim","grain"])
                    tryVerify(()=>Math.abs(surface[key]-dock[key])<0.0001);
                verify(String(surface.fragmentShader).endsWith("Common/LiquidGlass.frag.dock.qsb"));
            }
            compare(menu.blurRadius,32);
            verify(String(menu.shaderUrl).endsWith("LiquidGlass-frosted-menu.frag.qsb"));
        }
        function test_material_changes_propagate_to_lock_launchpad_and_dock() {
            assertShared();
            const initial=dock.thickness;
            settings.setText(JSON.stringify({glassLiquid:1.2,glassOpacity:0.3,glassBlur:22,glassRim:0.8,glassGrain:0.02}));
            tryCompare(Common.GlassMaterial,"baseLiquid",1.2);
            verify(dock.thickness>initial);
            fuzzyCompare(dock.tintMix,0.3*0.55,0.0001);
            compare(menu.blurRadius,32);assertShared();
            settings.setText("{");wait(200);
            compare(Common.GlassMaterial.baseLiquid,1.2);assertShared();
        }
        function test_shared_intensity_file_updates_all_surfaces_and_previews_stay_local() {
            wait(250);preference.setText(JSON.stringify({mode:"tinted",intensity:0.72}));
            tryCompare(Common.GlassMaterial,"intensity",0.72);
            verify(dock.tintMix>0);compare(menu.blurRadius,32);assertShared();
            const glass=findChild(preview,"sharedLiquidGlassSurface");
            verify(glass!==null);const clear=glass.thickness;
            preview.tinted=true;verify(glass.thickness<clear);
            compare(Common.GlassMaterial.intensity,0.72);assertShared();
        }
        function test_accessibility_keeps_shared_surfaces_consistent() {
            Common.DesktopPreferences.setValue("reduceTransparency",true);
            for (const surface of surfaces()) {
                tryCompare(surface,"thickness",0);compare(surface.dispersion,0);compare(surface.magnify,0);
                compare(surface.tintMix,0.94);
            }
            Common.DesktopPreferences.setValue("reduceTransparency",false);
            Common.DesktopPreferences.setValue("increaseContrast",true);
            for (const surface of surfaces()) tryVerify(()=>surface.rim>=0.85);
        }
        function test_production_consumers_compile() {
            for (const name of ["DockGlassSurface","DockTooltip","NotchGlass","NotchMenuBarGlass","LumaSearchGlass","LumaGooey","SpotlightGooey","GlassMaterialPreview","PlayerWidget","ClockWidget","CalendarWidget","WeatherWidget","UpstreamBar/PlayerWidget","UpstreamBar/ClockWidget","UpstreamBar/CalendarWidget","UpstreamBar/WeatherWidget"]) {
                const component=Qt.createComponent("../../MacShell/"+name+".qml");
                tryCompare(component,"status",Component.Ready,5000);compare(component.errorString(),"");
            }
            for (const name of ["FolderPanel","ContextMenu","SearchGlassSurface","SearchGlassContext"]) {
                const component=Qt.createComponent("../../launchpad/components/"+name+".qml");
                tryCompare(component,"status",Component.Ready,5000);compare(component.errorString(),"");
            }
        }
    }
}
