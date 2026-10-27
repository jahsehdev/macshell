import importlib.util
from pathlib import Path
import tempfile
import unittest

from PIL import Image, ImageChops

SOURCE = Path(__file__).resolve().parents[1] / "render_launchpad_background.py"
spec = importlib.util.spec_from_file_location("launchpad_background_renderer", SOURCE)
renderer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(renderer)


class LaunchpadBackgroundTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.wallpaper = self.root / "wallpaper with spaces.png"
        image = Image.new("RGB", (240, 160))
        image.paste("white", (0, 0, 120, 160))
        image.save(self.wallpaper)

    def render(self, radius=12, size=(240, 160)):
        return renderer.render(self.wallpaper.as_uri(), *size, radius, self.root / "cache")

    def test_full_resolution_and_smooth_edges(self):
        path = self.render()
        with Image.open(path) as image:
            self.assertEqual(image.size, (240, 160))
            values = [image.getpixel((x, 80))[0] for x in range(240)]
        self.assertGreater(len(set(values)), 40)
        self.assertLess(max(abs(a - b) for a, b in zip(values, values[1:])), 12)
        self.assertEqual(values, sorted(values, reverse=True))

    def test_cache_reused_without_rewrite(self):
        first = self.render()
        modified = first.stat().st_mtime_ns
        self.assertEqual(first, self.render())
        self.assertEqual(first.stat().st_mtime_ns, modified)

    def test_blur_size_and_wallpaper_invalidate_cache(self):
        first = self.render()
        second = self.render(4)
        third = self.render(12, (480, 320))
        self.assertEqual(len({first, second, third}), 3)
        with Image.open(third) as image:
            self.assertEqual(image.size, (480, 320))
        Image.new("RGB", (240, 160), "red").save(self.wallpaper)
        self.assertNotEqual(first, self.render())

    def test_zero_blur_is_lossless_at_native_size(self):
        with Image.open(self.wallpaper) as original, Image.open(self.render(0)) as output:
            self.assertIsNone(ImageChops.difference(original, output).getbbox())

    def test_reject_invalid_inputs(self):
        for radius in (-1, float("nan"), 513):
            with self.assertRaises(ValueError):
                self.render(radius)
        with self.assertRaises(ValueError):
            self.render(4, (0, 160))
        with self.assertRaises(ValueError):
            renderer.render("https://example.com/wallpaper.jpg", 240, 160, 10, self.root)


if __name__ == "__main__":
    unittest.main()
