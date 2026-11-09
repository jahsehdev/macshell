"""Exercise portable Folderify-style masks, engraving and iconset exports."""
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('folderify_features', ROOT / 'bin/folder_customizer.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class Metadata:
    value = 'file:///original.png'
    def get(self, path):
        return self.value
    def set(self, path, value):
        self.value = value


class FolderifyFeatures(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='macshell-folderify-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        env = patch.dict(os.environ, XDG_DATA_HOME=str(self.root / 'data'), XDG_CONFIG_HOME=str(self.root / 'config'))
        env.start(); self.addCleanup(env.stop)
        self.folder = self.root / 'Recipes & 家族 $(literal)'
        self.folder.mkdir()
        self.mask = self.root / 'mask with spaces.png'
        image = Image.new('RGBA', (384, 384))
        draw = ImageDraw.Draw(image)
        draw.rounded_rectangle((80, 80, 304, 304), radius=24, fill='black')
        draw.rectangle((160, 125, 224, 260), fill=(0, 0, 0, 0))
        image.save(self.mask)
        self.meta = Metadata()
        self.editor = module.Folder(self.folder, self.meta)

    def test_mask_is_cached_by_content_and_survives_source_deletion(self):
        first = module.import_mask(self.mask)
        self.assertEqual(module.import_mask(self.mask), first)
        self.mask.unlink()
        value = dict(mask=first, style='engraved', color='#ffd43b')
        state = self.editor.apply(value)
        self.assertEqual(state['settings']['mask'], first)
        icon = Path(module.read_state(self.folder)['icon'])
        with Image.open(icon) as image:
            self.assertEqual(image.size, (256, 256))
            self.assertEqual(image.getpixel((0, 0))[3], 0)
        self.assertEqual(list(self.folder.iterdir()), [])
        moved = self.folder.with_name('Moved')
        self.folder.rename(moved)
        self.assertEqual(module.Folder(moved, self.meta).status()['settings']['mask'], first)
        module.Folder(moved, self.meta).apply(clear=True)
        self.assertEqual(self.meta.value, 'file:///original.png')

    def test_import_rejects_opaque_empty_non_png_and_oversized_images(self):
        for name, mode, fill, extension in [('opaque', 'RGB', 'black', 'png'),
                                             ('empty', 'RGBA', (0, 0, 0, 0), 'png'),
                                             ('jpeg', 'RGB', 'black', 'jpg')]:
            with self.subTest(name=name):
                path = self.root / (name + '.' + extension)
                Image.new(mode, (32, 32), fill).save(path)
                with self.assertRaises(ValueError):
                    module.import_mask(path)
        huge = self.root / 'huge.png'
        Image.new('RGBA', (4097, 1)).save(huge)
        with self.assertRaises(ValueError):
            module.import_mask(huge)
        invalid = self.root / 'invalid.png'
        invalid.write_bytes(b'not an image')
        with self.assertRaises(ValueError):
            module.import_mask(invalid)
        self.assertEqual(module.read_state(self.folder), {})

    def test_settings_validate_masks_and_alternative_emblems(self):
        mask = module.import_mask(self.mask)
        for value in [dict(mask='../outside'), dict(mask=mask, symbol='cutlery'),
                      dict(mask=mask, emoji='🎮'), dict(style='unknown')]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                self.editor.apply(value)
        self.assertEqual(module.normalize(dict(color='#0a84ff')), dict(color='#0a84ff', symbol='', emoji=''))

    def test_engraving_changes_pixels_and_style_changes_cache_identity(self):
        flat = dict(color='#ffd43b', symbol='cutlery')
        engraved = dict(flat, style='engraved')
        self.assertNotEqual(module.render(flat).tobytes(), module.render(engraved).tobytes())
        self.assertNotEqual(module.artwork_path(flat), module.artwork_path(engraved))
        mask = module.import_mask(self.mask)
        self.assertNotEqual(module.render(dict(mask=mask)).tobytes(), module.render(dict(mask=mask, style='engraved')).tobytes())

    def test_exports_all_ten_sizes_without_folder_side_effects_or_overwrites(self):
        mask = module.import_mask(self.mask)
        value = dict(mask=mask, style='engraved', color='#ff453a')
        before = self.meta.value
        exported = module.export_iconset(value, self.root)
        expected = {}
        for base, retina in module.ICON_SIZES:
            name = f'icon_{base}x{base}' + ('@2x' if retina == 2 else '') + '.png'
            expected[name] = (base * retina, base * retina)
        self.assertEqual({path.name for path in exported.iterdir()}, set(expected))
        for name, size in expected.items():
            with Image.open(exported / name) as image:
                self.assertEqual(image.size, size)
                self.assertEqual(image.mode, 'RGBA')
                image.verify()
        again = module.export_iconset(value, self.root)
        self.assertNotEqual(exported, again)
        self.assertEqual(module.read_state(self.folder), {})
        self.assertEqual(self.meta.value, before)

    def test_export_failure_removes_partial_iconset_and_preserves_existing_files(self):
        existing = self.root / 'important.txt'
        existing.write_text('keep')
        before = set(self.root.iterdir())
        with patch.object(module, 'render', side_effect=OSError('renderer failed')):
            with self.assertRaises(OSError):
                module.export_iconset(dict(symbol='cutlery'), self.root)
        self.assertEqual(set(self.root.iterdir()), before)
        self.assertEqual(existing.read_text(), 'keep')
        link = self.root / 'export-link'
        link.symlink_to(self.root, target_is_directory=True)
        with self.assertRaises(ValueError):
            module.export_iconset({}, link)

    def test_worker_import_and_export_protocol(self):
        import io
        requests = [dict(action='import-mask', path=str(self.mask), settings=dict(color='#ffd43b')),
                    dict(action='export-iconset', directory=str(self.root), settings=dict(symbol='cutlery', style='engraved')),
                    dict(action='clear')]
        output = io.StringIO()
        with patch.object(module.sys, 'stdin', io.StringIO('\n'.join(map(json.dumps, requests)))), \
                patch.object(module.sys, 'stdout', output):
            module.serve(self.editor)
        messages = [json.loads(line) for line in output.getvalue().splitlines()]
        self.assertEqual([message['event'] for message in messages], ['state', 'state', 'exported', 'state'])
        self.assertEqual(messages[1]['settings']['style'], 'engraved')
        self.assertTrue(Path(messages[2]['path']).is_dir())
        self.assertFalse(messages[3]['customized'])
        self.assertEqual(self.meta.value, 'file:///original.png')

    def test_missing_mask_and_artwork_still_allow_reimport_or_clear(self):
        identity = module.import_mask(self.mask)
        self.editor.apply(dict(mask=identity, style='engraved'))
        Path(module.read_state(self.folder)['icon']).unlink()
        module.mask_path(identity).unlink()
        self.assertEqual(module.custom_icon(self.folder), '')
        state = self.editor.status()
        self.assertIn('Import the mask again', state['warning'])
        self.assertEqual(state['settings']['mask'], identity)
        self.editor.apply(clear=True)
        self.assertEqual(self.meta.value, 'file:///original.png')


if __name__ == '__main__':
    unittest.main()
