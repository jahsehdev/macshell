"""Exercise the shared forecast with real QML processes and an offline curl fixture."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class WeatherServiceTests(unittest.TestCase):
    def test_notch_without_desktop_widget_retry_units_and_location_changes(self):
        source = Path(__file__).resolve().parents[1] / "MacWidgets.qml"
        # Isolate the production weather section from desktop/Wayland windows.
        weather = source.read_text().split("    // ───────────── weather data (Open-Meteo) ─────────────", 1)[1].split("    // ───────────── Liquid Glass backend", 1)[0]
        with tempfile.TemporaryDirectory(prefix="notch-weather-service-") as temp:
            root = Path(temp)
            (root / "runtime").mkdir(mode=0o700)
            (root / "bin").mkdir()
            curl = root / "bin/curl"
            curl.write_text('''#!/usr/bin/env python3
import json, sys, time
args=sys.argv[1:]
def value(key, default=""):
    return next((a.split("=",1)[1] for a in args if a.startswith(key+"=")), default)
if any("ipwho.is" in a for a in args):
    print(json.dumps({"latitude":1,"longitude":2,"city":"Auto City"}))
elif any("geocoding-api" in a for a in args):
    name=value("name")
    print(json.dumps({"results": [] if name=="Missing" else [{"name":name,"latitude":3 if name=="Slow" else 4,"longitude":2}]}))
else:
    if value("latitude")=="3": time.sleep(0.8)
    t=77 if value("temperature_unit")=="fahrenheit" else 25
    print(json.dumps({"current":{"temperature_2m":t,"weather_code":61,"is_day":1,"time":"2026-11-03T16:15"},
      "hourly":{"time":[f"2026-11-03T{h:02}:00" for h in range(24)],"temperature_2m":[t]*24,"weather_code":[61]*24,"is_day":[1]*24},
      "daily":{"time":["2026-11-03"],"temperature_2m_max":[t+2],"temperature_2m_min":[t-3],"weather_code":[61]}}))
''')
            curl.chmod(0o755)
            (root / "ForecastUnderTest.qml").write_text('''import QtQuick
import Quickshell
import Quickshell.Io
Scope {
    id:root
    property bool ready:false
    property int widgetCount:0
    property string tempUnit:"C"
    property string locMode:"auto"
    property string cityName:""
    property var hub:QtObject {
        property var bar:QtObject {
            property bool notchEnabled:true
            property var notchService:QtObject {
                property bool loaded:true
                property var state:({menus:[]})
            }
        }
    }
    function count(type) {return widgetCount;}
''' + weather + "\n}\n")
            (root / "shell.qml").write_text('''import Quickshell
ShellRoot { WeatherTests {} }
''')
            (root / "WeatherTests.qml").write_text('''import QtQuick
import QtTest
Window {
    id:window
    visible:true;width:100;height:100
    ForecastUnderTest {id:weather}
    TestCase {
        name:"WeatherService";when:window.visible
        onCompletedChanged:if(completed)console.log("WEATHER_TOTALS",qtest_results.passCount,"passed,",qtest_results.failCount,"failed")
        function test_shared_forecast() {
            weather.ready=true;wait(800);verify(!weather.wxReady);verify(!weather.wxBusy);
            weather.hub.bar.notchService.state=({menus:["weather"]});
            tryVerify(()=>weather.wxReady,4000);compare(weather.widgetCount,0);compare(weather.wxCity,"Auto City");
            compare(weather.wxTemp,25);compare(weather.wxHourly.length,6);compare(weather.wxHourly[0].h,"Now");compare(weather.wxInfo.t,"Light Rain");verify(weather.wxUpdatedAt>0);
            weather.locMode="city";weather.cityName="Amsterdam";weather.tempUnit="F";weather.refreshSoon();
            tryCompare(weather,"wxCity","Amsterdam",4000);compare(weather.wxTemp,77);
            weather.cityName="Missing";weather.refreshSoon();tryCompare(weather,"wxError","city not found",4000);
            verify(weather.wxReady);compare(weather.wxCity,"Amsterdam");
            weather.cityName="Slow";weather.refreshSoon();tryVerify(()=>weather.wxBusy,2000);wait(150);
            weather.cityName="New City";weather.refreshSoon();
            tryCompare(weather,"wxCity","New City",6000);compare(weather.wxError,"");compare(weather.wxTemp,77);
            weather.hub.bar.notchService.state=({menus:[]});wait(800);verify(!weather.wxBusy);
            weather.refresh();verify(!weather.wxBusy);
        }
    }
}
''')
            env = os.environ.copy()
            env.pop("WAYLAND_DISPLAY", None)
            env.update(QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
                       XDG_RUNTIME_DIR=str(root / "runtime"), XDG_CONFIG_HOME=str(root / "config"),
                       PATH=str(root / "bin") + os.pathsep + env["PATH"])
            result = subprocess.run(["qs", "-p", str(root), "--no-color"], env=env,
                                    capture_output=True, text=True, timeout=25)
            log = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, log)
            self.assertRegex(log, r"WEATHER_TOTALS [1-9][0-9]* passed, 0 failed")
            for error in ("TypeError", "ReferenceError", "WARN qml:", "Failed to load configuration"):
                self.assertNotIn(error, log)


if __name__ == "__main__":
    unittest.main()
