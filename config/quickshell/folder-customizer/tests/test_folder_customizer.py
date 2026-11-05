import importlib.util
import json
import colorsys
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('folder_customizer', SOURCE / 'bin/folder_customizer.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class Metadata:
    def __init__(self):
        self.value = 'file:///previous-icon.png'
        self.fail = False
    def get(self, path):
        return self.value
    def set(self, path, value):
        if self.fail:
            raise OSError('Metadata unavailable')
        self.value = value


class FolderTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.path = self.root / 'Recipes & 家族 $(touch nope)'
        self.path.mkdir()
        self.env = patch.dict(os.environ, XDG_DATA_HOME=str(self.root / 'data'), XDG_CONFIG_HOME=str(self.root / 'config'))
        self.env.start()
        self.addCleanup(self.env.stop)
        self.meta = Metadata()
        self.folder = module.Folder(self.path, self.meta)

    def test_apply_creates_real_png_and_metadata(self):
        modified = self.path.stat().st_mtime_ns
        result = self.folder.apply(dict(color='#FFD43B', symbol='cutlery'))
        self.assertEqual(result['settings']['color'], '#ffd43b')
        icon = Path(module.read_state(self.path)['icon'])
        with module.Image.open(icon) as image:
            self.assertEqual(image.size, (256, 256))
        self.assertEqual(self.meta.value, icon.as_uri())
        self.assertEqual(module.custom_icon(self.path), icon.as_uri())
        self.assertEqual(list(self.path.iterdir()), [])
        self.assertEqual(self.path.stat().st_mtime_ns, modified)

    def test_clear_restores_original_after_multiple_edits(self):
        self.folder.apply(dict(color='#ff453a'))
        self.folder.apply(dict(color='#ffd43b', symbol='cutlery'))
        self.folder.apply(clear=True)
        self.assertEqual(self.meta.value, 'file:///previous-icon.png')
        self.assertEqual(module.read_state(self.path), {})
        self.assertEqual(module.custom_icon(self.path), '')

    def test_rename_and_move_preserve_customization(self):
        self.folder.apply(dict(color='#30c85a', symbol='leaf'))
        destination = self.root / 'Moved'
        self.path.rename(destination)
        state = module.Folder(destination, self.meta).status()
        self.assertTrue(state['customized'])
        self.assertEqual(state['settings']['symbol'], 'leaf')

    def test_gio_failure_rolls_back_attribute(self):
        self.meta.fail = True
        with self.assertRaises(OSError):
            self.folder.apply(dict(color='#ffd43b'))
        self.assertEqual(module.read_state(self.path), {})
        self.assertEqual(self.meta.value, 'file:///previous-icon.png')

    def test_gio_failure_preserves_existing_state(self):
        self.folder.apply(dict(color='#ff453a'))
        old = module.read_state(self.path)
        self.meta.fail = True
        with self.assertRaises(OSError):
            self.folder.apply(dict(color='#30c85a'))
        self.assertEqual(module.read_state(self.path), old)

    def test_xattr_failure_does_not_change_gio(self):
        with patch.object(module.os, 'setxattr', side_effect=OSError('Unsupported filesystem')):
            with self.assertRaises(OSError):
                self.folder.apply(dict(color='#ffd43b'))
        self.assertEqual(self.meta.value, 'file:///previous-icon.png')

    def test_clear_failure_preserves_old_icon(self):
        self.folder.apply(dict(color='#ffd43b'))
        icon = self.meta.value
        with patch.object(module.os, 'removexattr', side_effect=OSError('Read only')):
            with self.assertRaises(OSError):
                self.folder.apply(clear=True)
        self.assertEqual(self.meta.value, icon)
        self.assertTrue(module.read_state(self.path))

    def test_emoji_renders_colored_pixels(self):
        base = module.render(dict(color='#ffd43b'))
        emoji = module.render(dict(color='#ffd43b', emoji='🎮'))
        self.assertNotEqual(base.tobytes(), emoji.tobytes())
        family = module.render(dict(color='#0a84ff', emoji='👨‍👩‍👧‍👦'))
        self.assertEqual(family.size, (256, 256))

    def test_invalid_input_never_applies(self):
        for value in [dict(color='red; touch nope'), dict(color='#abc'), dict(symbol='unknown'),
                      dict(emoji='\n'), dict(emoji='a'*33), dict(symbol='cutlery', emoji='🎮')]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                self.folder.apply(value)
        self.assertEqual(module.read_state(self.path), {})

    def test_files_and_symlinks_are_rejected(self):
        file = self.root / 'file'
        file.touch()
        link = self.root / 'link'
        link.symlink_to(self.path, target_is_directory=True)
        for path in [file, link]:
            with self.assertRaises(ValueError):
                module.Folder(path)

    def test_corrupt_attribute_does_not_break_listing(self):
        os.setxattr(self.path, module.ATTRIBUTE, b'{oops')
        self.assertEqual(module.custom_icon(self.path), '')
        self.assertFalse(self.folder.status()['customized'])

    def test_preview_has_no_folder_side_effects(self):
        first = module.artwork(dict(color='#ffd43b', symbol='cutlery'))
        self.assertEqual(first, module.artwork(dict(color='#ffd43b', symbol='cutlery')))
        self.assertEqual(module.read_state(self.path), {})
        self.assertEqual(self.meta.value, 'file:///previous-icon.png')

    def test_custom_color_lightness_is_preserved(self):
        light = module.render(dict(color='#eeeeee')).getpixel((64, 155))
        dark = module.render(dict(color='#222222')).getpixel((64, 155))
        self.assertGreater(min(light[:3]), 225)
        self.assertLess(max(dark[:3]), 95)
        self.assertLess(max(light[:3]) - min(light[:3]), 2)
        for color in module.COLORS:
            pixel = module.render(dict(color=color)).getpixel((64, 155))
            target = colorsys.rgb_to_hls(*(int(color[i:i+2], 16)/255 for i in (1, 3, 5)))[1]
            actual = colorsys.rgb_to_hls(*(c/255 for c in pixel[:3]))[1]
            self.assertGreaterEqual(actual, target - .02, color)
            self.assertEqual(pixel[3], 255)

    def test_every_symbol_has_an_intact_centered_export(self):
        from PIL import ImageChops
        base = module.render(dict(color='#0a84ff')).convert('RGB')
        for symbol in module.symbols():
            with self.subTest(symbol=symbol['id']):
                image = module.render(dict(color='#0a84ff', symbol=symbol['id']))
                self.assertEqual(image.size, (256, 256))
                bbox = ImageChops.difference(base, image.convert('RGB')).getbbox()
                self.assertIsNotNone(bbox)
                self.assertGreaterEqual(bbox[0], 86)
                self.assertGreaterEqual(bbox[1], 102)
                self.assertLessEqual(bbox[2], 170)
                self.assertLessEqual(bbox[3], 186)

    def test_legacy_icon_uri_is_upgraded_and_original_is_retained(self):
        with patch.object(module, 'ART_VERSION', 'art-v1'):
            self.folder.apply(dict(color='#ff453a', symbol='cake'))
        old = module.read_state(self.path)
        self.assertTrue(self.folder.repair_artwork())
        new = module.read_state(self.path)
        self.assertNotEqual(old['icon'], new['icon'])
        self.assertEqual(new['previousIcon'], 'file:///previous-icon.png')
        self.assertEqual(self.meta.value, Path(new['icon']).as_uri())
        self.assertFalse(self.folder.repair_artwork())
        self.folder.apply(clear=True)
        self.assertEqual(self.meta.value, 'file:///previous-icon.png')

    def test_missing_cached_export_is_recreated(self):
        self.folder.apply(dict(color='#30c85a', symbol='leaf'))
        icon = Path(module.read_state(self.path)['icon'])
        icon.unlink()
        self.assertEqual(module.custom_icon(self.path), icon.as_uri())
        with module.Image.open(icon) as image:
            image.verify()

    def test_legacy_broken_png_is_repaired_without_changing_folder_metadata(self):
        with patch.object(module, 'ART_VERSION', 'art-v1'):
            self.folder.apply(dict(color='#ff453a', symbol='cake'))
        state = module.read_state(self.path)
        icon = Path(state['icon'])
        icon.write_bytes(b'broken image')
        self.meta.fail = True
        self.assertTrue(self.folder.refresh_legacy_cache())
        with module.Image.open(icon) as image:
            self.assertEqual(image.size, (256, 256))
            image.verify()
        self.assertEqual(module.read_state(self.path), state)
        self.assertEqual(self.meta.value, icon.as_uri())
        self.assertFalse(self.folder.refresh_legacy_cache())


if __name__ == '__main__':
    unittest.main()
