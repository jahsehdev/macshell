"""Guard the single material source and the QML shader-resource migration."""
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[4]
QUICK = ROOT / 'config/quickshell'


class SharedGlassTests(unittest.TestCase):
    def test_components_cannot_define_separate_optical_tuning(self):
        # A shared shader alone is insufficient: the old per-component uniforms
        # made Launchpad, MacLock and the Dock render different materials.
        owners = [path.relative_to(QUICK).as_posix() for path in QUICK.rglob('*.qml')
                  if re.search(r'property real (?:dispersion|magnify):', path.read_text())]
        self.assertEqual(owners, ['Common/LiquidGlassSurface.qml'])
        shader = (QUICK / 'Common/LiquidGlass.frag').read_text()
        # Menubar dropdowns deliberately use non-refractive frosted vibrancy.
        frost = shader.split('#ifdef FROSTED_MENU', 1)[1].split('#endif', 1)[0]
        self.assertIn('backdropUv(p + srcOffset)', frost)
        self.assertIn('return;', frost)
        self.assertNotIn('sampleBackdropPx', frost)

    def test_menubar_frost_does_not_use_the_shared_lens_profile(self):
        bar = (QUICK / 'MacShell/UpstreamBar/MacBar.qml').read_text()
        self.assertIn('g.frosted ? 32 : GlassCommon.GlassMaterial.surfaceBlur', bar)
        self.assertIn('frosted ? 32 : GlassCommon.GlassMaterial.surfaceBlur', bar)
        self.assertEqual(bar.count('Qt.resolvedUrl("../Common/LiquidGlass-frosted-menu.frag.qsb")'), 2)
        self.assertIn('Qt.resolvedUrl("../Common/LiquidGlass-control-center.frag.qsb")', bar)

    def test_every_bundle_is_built_from_the_same_material_source(self):
        spec = importlib.util.spec_from_file_location('glass_build', ROOT / 'scripts/build-glass-shaders.py')
        build = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(build)
        jobs = build.shader_jobs()
        self.assertGreater(len(jobs), 1)
        self.assertEqual({source for source, _ in jobs.values()},
                         {Path('config/quickshell/Common/LiquidGlass.frag')})
        for output in jobs:
            self.assertTrue((ROOT / output).is_file(), str(output))
            self.assertEqual(output.parent, Path('config/quickshell/Common'))

    def test_no_component_can_own_another_material_source(self):
        sources = [path.relative_to(QUICK).as_posix() for path in QUICK.rglob('*.frag')
                   if re.search(r'liquidglass|dockmenu|docktooltip|notch-glass|notch-menu-tail|slider-glass|knobglass|glasstext|luma-mic',
                                path.name, re.IGNORECASE)]
        self.assertEqual(sources, ['Common/LiquidGlass.frag'])
        self.assertFalse(list((ROOT / 'extras/sddm/theme').glob('*.frag')))

    def test_shared_qml_resources_resolve_in_the_repository(self):
        references = 0
        for qml in QUICK.rglob('*.qml'):
            for target in re.findall(r'Qt\.resolvedUrl\("([^"]*LiquidGlass[^"]*)"\)', qml.read_text()):
                resolved = (qml.parent / target).resolve()
                self.assertTrue(resolved.is_file(), f'{qml}: {target}')
                self.assertEqual(resolved.parent, QUICK / 'Common')
                # Quickshell rejects a URL that lexically leaves its config root,
                # even when normal filesystem resolution finds the shared file.
                relative = qml.relative_to(QUICK)
                if relative.parts[0] in ('MacShell', 'MacLock', 'launchpad'):
                    lexical = Path(os.path.normpath(qml.parent / target))
                    self.assertTrue(lexical.is_relative_to(QUICK / relative.parts[0]),
                                    f'Quickshell config escape: {qml}: {target}')
                references += 1
        self.assertGreater(references, 15)

    @unittest.skipUnless(shutil.which('qs') and Path('/usr/lib/qt6/bin/qsb').exists(),
                         'Quickshell and Qt Shader Tools are required')
    def test_production_urls_and_source_compile_inside_quickshell_vfs(self):
        for app, flags in [('MacShell', ['-D', 'GLASS_BAR']),
                           ('MacShell', ['-D', 'GLASS_BAR', '-D', 'FROSTED_MENU']),
                           ('MacLock', ['-D', 'GLASS_LOCK']), ('launchpad', [])]:
            with self.subTest(app=app), tempfile.TemporaryDirectory(prefix='glass-vfs-') as temporary:
                root = Path(temporary)
                (root / 'Common').symlink_to(QUICK / 'Common', target_is_directory=True)
                (root / 'runtime').mkdir(mode=0o700)
                groups = {}
                for qml in (QUICK / app).rglob('*.qml'):
                    urls = re.findall(r'Qt\.resolvedUrl\("([^"]*LiquidGlass[^"]*)"\)', qml.read_text())
                    if urls:
                        groups.setdefault(qml.parent.relative_to(QUICK / app), set()).update(urls)
                loaders = []
                for directory, urls in groups.items():
                    probe = root / directory / 'ShaderUrlProbe.qml'
                    probe.parent.mkdir(parents=True, exist_ok=True)
                    expressions = ', '.join('Qt.resolvedUrl(' + json.dumps(url) + ')' for url in sorted(urls))
                    probe.write_text('import QtQuick\nQtObject {\n'
                                     'property var shaderUrls: [' + expressions + ']\n'
                                     'Component.onCompleted: console.log("SHADER_URLS", JSON.stringify(shaderUrls))\n}\n')
                    loaders.append('Loader { source: ' + json.dumps(probe.relative_to(root).as_posix()) + ' }')
                command = ['/usr/lib/qt6/bin/qsb', '--qt6'] + flags + ['-o', str(root / 'test.qsb')]
                (root / 'shell.qml').write_text('''import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
    id: shell
    property url materialSource: Qt.resolvedUrl("Common/LiquidGlass.frag")
    Process {
        running: true
        command: COMMAND.concat([decodeURIComponent(shell.materialSource.toString().replace("file://", ""))])
        stderr: StdioCollector { onStreamFinished: if (text.trim()) console.warn(text) }
        onExited: (code, status) => { console.log("GLASS_BUILD_EXIT", code); finish.start(); }
    }
    Timer { id: finish; interval: 100; onTriggered: Qt.quit() }
    LOADERS
}
'''.replace('COMMAND', json.dumps(command)).replace('LOADERS', '\n'.join(loaders)))
                env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
                           XDG_RUNTIME_DIR=str(root / 'runtime'), XDG_CONFIG_HOME=str(root / 'config'))
                env.pop('WAYLAND_DISPLAY', None)
                result = subprocess.run(['qs', '-p', str(root), '--no-color'], env=env,
                                        capture_output=True, text=True, timeout=12)
                output = result.stdout + result.stderr
                self.assertEqual(result.returncode, 0, output)
                self.assertNotIn('qs-blackhole', output, output)
                self.assertIn('GLASS_BUILD_EXIT 0', output, output)
                self.assertTrue((root / 'test.qsb').is_file(), output)
                self.assertEqual(output.count('SHADER_URLS'), len(groups), output)


if __name__ == '__main__':
    unittest.main()
