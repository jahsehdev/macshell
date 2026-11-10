"""Exercise real decoding and process lifecycle without touching the desktop."""
import configparser
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[1] / 'wallpaper.py'
spec = importlib.util.spec_from_file_location('wallpaper', SOURCE)
wallpaper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wallpaper)


class WallpaperTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory(prefix='wp-test-')
        self.addCleanup(self.folder.cleanup)
        self.root = Path(self.folder.name)
        self.children = []
        for name, relative in [('CONFIG', 'config'), ('CACHE', 'cache'), ('RUNTIME', 'run'),
                               ('THEME', 'theme'), ('LOGIN', 'login')]:
            location = self.root / relative
            location.mkdir()
            task = patch.object(wallpaper, name, location)
            task.start()
            self.addCleanup(task.stop)
        task = patch.object(wallpaper, 'STATE', wallpaper.CONFIG / 'macshell/wallpaper.json')
        task.start()
        self.addCleanup(task.stop)
        self.addCleanup(self.stop_children)
        self.video = self.root / "motion # ' $ sample.mp4"
        subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'lavfi', '-i',
                        'testsrc2=size=160x90:rate=12', '-t', '0.5', '-c:v', 'libx264',
                        '-pix_fmt', 'yuv420p', str(self.video)], check=True, capture_output=True)
        self.picture = self.root / 'picture.png'
        from PIL import Image
        Image.new('RGB', (160, 90), '#3278bc').save(self.picture)
        self.commands = []

    def stop_children(self):
        for child in self.children:
            if child.poll() is None:
                child.terminate()
            child.wait(timeout=5)

    def spawn(self, command, output):
        self.commands.append(command)
        child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(120)'])
        self.children.append(child)
        return child, dict(pid=child.pid, token=wallpaper.process_token(child.pid), output=output)

    @staticmethod
    def backend_command(command, timeout=30):
        if command[0] == 'ffmpeg':
            return subprocess.run(command, capture_output=True, text=True, timeout=timeout)
        return subprocess.CompletedProcess(command, 0, '', '')

    def test_picture_video_restore_picture_and_login_sync(self):
        with patch.object(wallpaper, 'monitors', return_value=['DP-1', 'HDMI-A-1']), \
             patch.object(wallpaper, 'spawn', side_effect=self.spawn), \
             patch.object(wallpaper, 'run', side_effect=self.backend_command):
            media = wallpaper.apply(self.video)
            self.assertEqual(media['mode'], 'live')
            self.assertEqual(len(self.children), 2)
            self.assertTrue(all(wallpaper.alive(p) for p in wallpaper.read_json(wallpaper.RUNTIME / 'players.json')))
            self.assertEqual(wallpaper.state()['path'], str(self.video))
            self.assertTrue(Path(media['poster']).stat().st_size)
            self.assertEqual((wallpaper.LOGIN / 'video.mp4').read_bytes(), self.video.read_bytes())
            cfg = configparser.ConfigParser(interpolation=None)
            cfg.read(wallpaper.LOGIN / 'theme.conf.user')
            self.assertEqual(cfg['General']['backgroundVideo'], str(wallpaper.LOGIN / 'video.mp4'))
            wallpaper.apply(self.video, restore=True)
            self.assertEqual(len(self.children), 2, 'Restore must not duplicate players')
            self.assertEqual(self.commands[0][-1], str(self.video), 'Pass special characters as a single argv element')
            self.assertIn('no-audio', self.commands[0][self.commands[0].index('-o') + 1])
            self.assertIn('loop-file=inf', self.commands[0][self.commands[0].index('-o') + 1])
            media = wallpaper.apply(self.picture)
            self.assertEqual(media['mode'], 'picture')
            for child in self.children:
                self.assertEqual(child.wait(timeout=5), -15)
            self.assertFalse((wallpaper.CONFIG / 'macshell/wallpaper-video').exists())
            self.assertFalse((wallpaper.LOGIN / 'video.mp4').exists())
            cfg.read(wallpaper.LOGIN / 'theme.conf.user')
            self.assertEqual(cfg['General']['backgroundVideo'], '')
            self.assertEqual(wallpaper.state()['path'], str(self.picture))

    def test_failed_video_keeps_last_selection_and_player(self):
        with patch.object(wallpaper, 'monitors', return_value=['DP-1']), \
             patch.object(wallpaper, 'spawn', side_effect=self.spawn), \
             patch.object(wallpaper, 'run', side_effect=self.backend_command):
            wallpaper.apply(self.video)
            before = wallpaper.STATE.read_bytes()
            broken = self.root / 'broken.mp4'
            broken.write_bytes(b'not a video')
            with self.assertRaises(ValueError):
                wallpaper.apply(broken)
            self.assertEqual(wallpaper.STATE.read_bytes(), before)
            self.assertIsNone(self.children[0].poll())
            self.assertEqual((wallpaper.LOGIN / 'video.mp4').read_bytes(), self.video.read_bytes())

    def test_monitor_change_reconciles_players_on_restore(self):
        with patch.object(wallpaper, 'monitors', return_value=['DP-1']) as monitors, \
             patch.object(wallpaper, 'spawn', side_effect=self.spawn), \
             patch.object(wallpaper, 'run', side_effect=self.backend_command):
            wallpaper.apply(self.video)
            monitors.return_value = ['DP-1', 'HDMI-A-1']
            wallpaper.apply(self.video, restore=True)
            self.assertEqual(len(self.children), 3)
            self.assertEqual(self.children[0].wait(timeout=5), -15)
            self.assertTrue(all(child.poll() is None for child in self.children[1:]))

    def test_pid_reuse_cannot_stop_unrelated_process(self):
        child, record = self.spawn([], 'DP-1')
        record['token'] = 'incorrect-start-time'
        wallpaper.stop([record])
        self.assertIsNone(child.poll())

    def test_player_start_failure_preserves_existing_player(self):
        with patch.object(wallpaper, 'monitors', return_value=['DP-1']), \
             patch.object(wallpaper, 'spawn', side_effect=self.spawn) as spawn, \
             patch.object(wallpaper, 'run', side_effect=self.backend_command):
            wallpaper.apply(self.video)
            before = wallpaper.STATE.read_bytes()
            def fail(command, output):
                child = subprocess.Popen(['false'])
                self.children.append(child)
                return child, dict(pid=child.pid, token=wallpaper.process_token(child.pid), output=output)
            spawn.side_effect = fail
            with self.assertRaises(ValueError):
                wallpaper.apply(self.video)
            self.assertIsNone(self.children[0].poll())
            self.assertEqual(wallpaper.STATE.read_bytes(), before)


if __name__ == '__main__':
    unittest.main()
