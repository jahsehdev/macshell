"""Exercise production glass filtering bindings and Launchpad size constraints in Qt."""
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

SHELL = Path(__file__).resolve().parents[1]
COMMON = SHELL.parent / 'Common'


class GlassWindowLifecycleTests(unittest.TestCase):
    def test_minimize_release_and_fullscreen_backdrop(self):
        binding = re.search(r'readonly property var glassClients: ([^\n]+)',
                            (SHELL / 'shell.qml').read_text())[1]
        binding = binding.replace('macMinimize.records', 'state.records')
        source = (SHELL / 'UpstreamBar/MacBar.qml').read_text()
        start = source.index('function sync() {', source.index('id: backdropComp'))
        end = start + len('function sync() {')
        depth = 1
        while depth:
            depth += (source[end] == '{') - (source[end] == '}')
            end += 1
        sync = source[start:end].replace('root.', 'state.').replace('win.modelData.name', '"test"')
        delegates = []
        for name, identifier in [('UpstreamBar/MacBar.qml', 'gw'), ('MacDock.qml', 'gw'),
                                 ('DockGlassSurface.qml', 'windowCapture'),
                                 ('LumaSearchBackdrop.qml', 'window')]:
            source = (SHELL / name).read_text()
            source = source[source.index('id: ' + identifier + '\n'):]
            source = source[:source.index('ScreencopyView')]
            visible = re.search(r'^\s*visible: ([^/\n]+)', source, re.M)[1].strip()
            delegates.append('Rectangle { width: 10; height: 10; x: %d; color: "blue"; '
                             'property bool gone: false; visible: %s }' % (len(delegates) * 10, visible))
        with tempfile.TemporaryDirectory(prefix='glass-window-lifecycle-') as directory:
            root = Path(directory)
            (root / 'runtime').mkdir(mode=0o700)
            (root / 'components').mkdir()
            (root / 'Common').mkdir()
            (root / 'Common/GlassBackdrop.js').write_text((COMMON / 'GlassBackdrop.js').read_text())
            (root / 'Common/qmldir').write_text('LaunchpadBackground 1.0 LaunchpadBackground.qml\nActivityLoader 1.0 ActivityLoader.qml\n')
            (root / 'Common/ActivityLoader.qml').write_text((COMMON / 'ActivityLoader.qml').read_text())
            (root / 'Common/LaunchpadBackground.qml').write_text('''import QtQuick
Item { property string screenName; property url imageSource; property real backgroundBlur; property real dimming }
''')
            for name, properties in {
                'Theme': 'property string backgroundType: "custom"; property url customImage: ""; property string tahoeWallpaper: ""; property real backgroundBlur: 0; property real backgroundOpacity: 0',
                'LaunchpadState': 'property bool windowVisible: true',
            }.items():
                (root / (name + '.qml')).write_text('pragma Singleton\nimport QtQml\nQtObject { ' + properties + ' }')
            (root / 'qmldir').write_text('singleton Theme 1.0 Theme.qml\nsingleton LaunchpadState 1.0 LaunchpadState.qml\n')
            (root / 'components/LaunchpadBackdrop.qml').write_text(
                (SHELL.parent / 'launchpad/components/LaunchpadBackdrop.qml').read_text())
            qml = '''import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import "Common/GlassBackdrop.js" as GlassBackdrop
import "components"
ShellRoot {
    QtObject {
        id: state
        property var records: ({})
        property var monData: [{id: 0, name: "test", x: 0, y: 0, activeWorkspace: {id: 1}, specialWorkspace: {id: 0}}]
        property var glassRawClients: [{address: "0x123", pid: 42, title: "Console", mapped: true, hidden: false, monitor: 0,
            workspace: {id: 1, name: "1"}, at: [0, 0], size: [40, 10], floating: false}]
        readonly property var glassClients: BINDING
    }
    LaunchpadBackdrop { id: backdrop; modelData: Quickshell.screens[0] }
    Window {
        id: host; width: 40; height: 10; color: "white"; visible: true
        Item { id: captures; anchors.fill: parent; DELEGATES }
        Item {
            id: bd; anchors.fill: parent; visible: false
            ListModel { id: wm }
            Repeater {
                model: wm
                delegate: Rectangle {
                    required property bool gone
                    width: 40; height: 10; color: "red"; visible: !gone
                }
            }
            SYNC
            Timer { id: sweep; interval: 600; onTriggered: {
                for (let i = wm.count - 1; i >= 0; --i) if (wm.get(i).gone) wm.remove(i);
            } }
            Connections {
                target: state
                function onGlassClientsChanged() { bd.sync(); }
                function onMonDataChanged() { bd.sync(); }
            }
            Component.onCompleted: sync()
        }
        TestCase {
            name: "GlassWindowLifecycle"
            when: host.visible && backdrop.visible
            onCompletedChanged: if (completed) console.log("TOTALS", qtest_results.passCount, "passed,", qtest_results.failCount, "failed")
            function test_recordsImmediatelyRefilterWithoutGeometryPoll() {
                compare(state.glassClients.length, 1);
                state.records = {"123": {pid: 42}};
                compare(state.glassClients.length, 0);
                state.records = {};
                compare(state.glassClients.length, 1);
            }
            function test_releasedCaptureHidesRetainedPixelsBeforeSweep() {
                wait(30);
                for (let i = 0; i < captures.children.length; ++i) {
                    const capture = captures.children[i];
                    capture.gone = false;
                    wait(10);
                    compare(grabImage(host.contentItem).pixel(i * 10 + 5, 5), Qt.color("blue"));
                    capture.gone = true;
                    wait(10);
                    compare(grabImage(host.contentItem).pixel(i * 10 + 5, 5), Qt.color("white"));
                }
            }
            function test_hiddenWorkspaceClearsRetainedPixelsAndRestoreReadmits() {
                captures.visible = false; bd.visible = true; bd.sync();
                wait(30);
                compare(grabImage(host.contentItem).pixel(5, 5), Qt.color("red"));
                const original = state.glassRawClients;
                for (const name of ["special:hidden", "special:minimized", "special:macshell-desktop", "special:macshell-stage"]) {
                    state.glassRawClients = [Object.assign({}, original[0], {workspace: {id: -98, name: name}})];
                    compare(state.glassClients.length, 0);
                    wait(10);
                    compare(grabImage(host.contentItem).pixel(5, 5), Qt.color("white"));
                    state.glassRawClients = original;
                    wait(10);
                    compare(grabImage(host.contentItem).pixel(5, 5), Qt.color("red"));
                }
                const monitors = state.monData;
                state.monData = [Object.assign({}, monitors[0], {activeWorkspace: {id: 2}})];
                wait(10);
                compare(grabImage(host.contentItem).pixel(5, 5), Qt.color("white"));
                state.monData = monitors;
                wait(10);
                compare(grabImage(host.contentItem).pixel(5, 5), Qt.color("red"));
                bd.visible = false; captures.visible = true;
            }
            function test_backdropKeepsScreenConstraintsOnReopen() {
                const screen = Quickshell.screens[0];
                for (let i = 0; i < 3; ++i) {
                    backdrop.visible = true;
                    tryCompare(backdrop, "width", screen.width);
                    tryCompare(backdrop, "height", screen.height);
                    compare(backdrop.minimumSize.width, screen.width);
                    compare(backdrop.minimumSize.height, screen.height);
                    compare(backdrop.maximumSize, backdrop.minimumSize);
                    backdrop.visible = false;
                    wait(10);
                }
                backdrop.visible = true;
            }
        }
    }
}'''.replace('BINDING', binding).replace('DELEGATES', '\n'.join(delegates)).replace('SYNC', sync)
            (root / 'shell.qml').write_text(qml)
            env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
                       XDG_RUNTIME_DIR=str(root / 'runtime'), XDG_CONFIG_HOME=str(root / 'config'),
                       XDG_STATE_HOME=str(root / 'state'))
            env.pop('WAYLAND_DISPLAY', None)
            result = subprocess.run(['qs', '-p', str(root), '--no-color'], env=env,
                                    capture_output=True, text=True, timeout=25)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertRegex(output, r'TOTALS [1-9][0-9]* passed, 0 failed', output)
            self.assertNotRegex(output, r'ERROR qml:|TypeError|ReferenceError')


if __name__ == '__main__':
    unittest.main()
