import importlib.util
from pathlib import Path
import tempfile
import unittest

from PIL import Image, ImageDraw

spec = importlib.util.spec_from_file_location("icon_geometry", Path(__file__).parents[1] / "icon_geometry.py")
metrics = importlib.util.module_from_spec(spec)
spec.loader.exec_module(metrics)


class IconGeometry(unittest.TestCase):
    def test_padding_and_soft_shadow_do_not_change_normalized_artwork_size(self):
        with tempfile.TemporaryDirectory() as tmp:
            for padding in (0, 10, 25):
                with self.subTest(padding=padding):
                    image = Image.new("RGBA", (100, 100))
                    draw = ImageDraw.Draw(image)
                    draw.rectangle((0, 0, 99, 99), fill=(0, 0, 0, 32))
                    draw.rectangle((padding, padding, 99 - padding, 99 - padding), fill="white")
                    path = Path(tmp) / "icon.png"
                    image.save(path)
                    original = path.read_bytes()
                    ratio = metrics.visible_ratio(path)
                    self.assertAlmostEqual(ratio, (100 - 2 * padding) / 100)
                    scale = 0.875 / ratio
                    self.assertAlmostEqual((100 - 2 * padding) * scale, 87.5)
                    self.assertEqual(path.read_bytes(), original)

    def test_non_square_and_transparent_icons_have_safe_bounds(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "icon.png"
            Image.new("RGBA", (100, 50), "white").save(path)
            self.assertEqual(metrics.visible_ratio(path), 1)
            Image.new("RGBA", (100, 50)).save(path)
            self.assertEqual(metrics.visible_ratio(path), 1)

    def test_local_hicolor_icons_work_without_a_local_theme_index(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            config, data = home / ".config", home / ".local/share"
            app = data / "applications/balance-test.desktop"
            app.parent.mkdir(parents=True)
            app.write_text("[Desktop Entry]\nIcon=balance-test\n")
            index = home / ".icons/hicolor/index.theme"
            index.parent.mkdir(parents=True)
            index.write_text("[Icon Theme]\nDirectories=128x128/apps\n[128x128/apps]\nSize=128\n")
            icon = data / "icons/hicolor/128x128/apps/balance-test.png"
            icon.parent.mkdir(parents=True)
            Image.new("RGBA", (128, 128), "white").save(icon)
            result = metrics.geometry(home, config, data, "hicolor", {})
            self.assertEqual(result["balance-test"], 1)
            self.assertEqual(result[str(icon)], 1)


if __name__ == "__main__":
    unittest.main()
