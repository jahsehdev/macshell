"""Regression checks for native theme contour generation (isolated from HOME)."""
import importlib.util
import math
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET

spec=importlib.util.spec_from_file_location("sync_apps",Path(__file__).parents[1]/"sync_apps.py")
bridge=importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


class NativeCornerTests(unittest.TestCase):
    def test_lame_equation_and_endpoints(self):
        for exponent in (2,3,4):
            points=bridge.quarter(3,5,20,10,-math.pi/2,0,exponent)
            self.assertEqual(len(points),40)
            for x,y in points:
                self.assertAlmostEqual(abs((x-3)/20)**exponent+abs((y-5)/10)**exponent,1)
            self.assertAlmostEqual(points[-1][0],23)
            self.assertAlmostEqual(points[-1][1],5)

    def test_only_canonical_cubic_corners_change(self):
        original="M0 0 c5.52 0 10 4.48 10 10 s5 4 10 4"
        converted,count=bridge.path_corners(original,4)
        self.assertEqual(count,1)
        self.assertTrue(converted.endswith("C10,15.52,15,14,20,14"))
        freehand="M0 0 C3 1 7 6 10 10"
        self.assertEqual(bridge.path_corners(freehand,4),(freehand,0))

    def test_svg_identifiers_and_references_survive(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/"theme.svg"
            path.write_text('<svg xmlns="http://www.w3.org/2000/svg"><rect id="panel" x="5" y="7" width="40" height="30" rx="10" transform="translate(2 3)" fill="red"/><use href="#panel"/></svg>')
            data,count=bridge.convert_svg(path,4)
            self.assertEqual(count,1)
            root=ET.fromstring(data)
            self.assertTrue(root[0].tag.endswith("path"))
            self.assertEqual(root[0].get("id"),"panel")
            self.assertEqual(root[0].get("transform"),"translate(2 3)")
            self.assertEqual(root[1].get("href"),"#panel")

    def test_native_controls_and_shared_references_keep_original_geometry(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/"theme.svg"
            path.write_text('<svg xmlns="http://www.w3.org/2000/svg"><defs><circle id="disc" r="6"/></defs><g id="radio-normal"><use href="#disc"/></g><g id="button-normal"><rect width="40" height="24" rx="12"/></g><rect id="panel" width="80" height="60" rx="16"/></svg>')
            original=ET.parse(path).getroot()
            data,count=bridge.convert_svg(path,4)
            result=ET.fromstring(data)
            self.assertEqual(count,1)
            for index in (0,1,2):
                self.assertEqual(ET.tostring(result[index]),ET.tostring(original[index]))
            self.assertTrue(result[3].tag.endswith("path"))

    def test_alpha_colors_use_portable_svg_attributes(self):
        root=ET.fromstring(bridge.asset(4,10,"#d0c7ff12"))
        stops=root.findall(".//{http://www.w3.org/2000/svg}stop")
        self.assertEqual(stops[0].get("stop-color"),"#d0c7ff")
        self.assertEqual(stops[0].get("stop-opacity"),stops[1].get("stop-opacity"))
        self.assertAlmostEqual(float(stops[0].get("stop-opacity")),18/255,places=6)

    def test_zero_restores_original_theme_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            svg=root/".config/Kvantum/Example/Example.svg"
            svg.parent.mkdir(parents=True)
            original='<svg xmlns="http://www.w3.org/2000/svg"><rect width="80" height="60" rx="16"/></svg>'
            svg.write_text(original)
            bridge.baseline(root,svg)
            svg.write_text("generated squircle asset")
            for relative in (".config/gtk-3.0/gtk.css", ".config/gtk-4.0/gtk.css", ".config/macshell/dolphin/sidebar.qss"):
                path=root/relative;path.parent.mkdir(parents=True,exist_ok=True)
                path.write_text("/* original native theme */")
                bridge.baseline(root,path)
                path.write_text("/* generated squircle overrides */")
            for amount in (0,):
                result=bridge.restore_round(root,ipc=False)
                self.assertEqual(svg.read_text(),original)
                self.assertEqual(result["exponent"],2)
                self.assertEqual(result["amount"],0)
                self.assertEqual((root/".config/gtk-3.0/gtk.css").read_text(),"/* original native theme */")
                self.assertEqual((root/".config/macshell/dolphin/sidebar.qss").read_text(),"/* original native theme */")
                self.assertIn("power = 2",(root/".config/macshell/corners/hypr.lua").read_text())

    def test_nautilus_theme_survives_corner_sync_and_restore(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            integration=root/".config/macshell/nautilus"
            integration.mkdir(parents=True)
            (integration/"theme-import.css").write_text('@import url("file:///theme/gtk.css");')
            (integration/"corners.css").write_text('.nautilus-window .sidebar-pane { border-radius:18px; }')
            (integration/"compat.css").write_text('.nautilus-window { --window-bg-color:@window_bg_color; }')
            css=root/".config/gtk-4.0/gtk.css"
            css.parent.mkdir(parents=True)
            original="/* unrelated user style */"
            css.write_text(original)
            baseline=bridge.baseline(root,css)
            for operation in (bridge.apply_defaults,bridge.apply_defaults,bridge.restore_round):
                operation(root,ipc=False)
                actual=css.read_text()
                self.assertEqual(actual.count((integration/"theme-import.css").as_uri()),1)
                self.assertEqual(actual.count((integration/"compat.css").as_uri()),1)
                self.assertNotIn((integration/"corners.css").as_uri(),actual)
                self.assertNotIn('MacShell continuous corners:',actual)
                self.assertIn(original,actual)
                self.assertEqual(baseline.read_text(),original)

    def test_dock_slider_never_changes_fixed_native_defaults(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            svg=root/".config/Kvantum/Example/Example.svg"
            svg.parent.mkdir(parents=True)
            original='<svg xmlns="http://www.w3.org/2000/svg"><g id="button-normal"><rect width="40" height="24" rx="12"/></g><rect id="panel" width="80" height="60" rx="16"/></svg>'
            svg.write_text(original)
            css=root/".config/gtk-3.0/gtk.css";css.parent.mkdir(parents=True)
            css.write_text("/* custom user style */")
            first=None
            for amount in (0,0.63,1,0):
                result=bridge.synchronize(root,amount,ipc=False)
                self.assertAlmostEqual(result["exponent"],2.7)
                self.assertEqual(result["amount"],0.35)
                current=svg.read_bytes()
                if first is None:first=current
                self.assertEqual(current,first)
                nodes=ET.fromstring(current)
                self.assertTrue(nodes[0][0].tag.endswith("rect"))
                self.assertTrue(nodes[1].tag.endswith("path"))
                self.assertTrue(css.read_text().startswith("/* custom user style */"))
                self.assertEqual(css.read_text().count("MacShell continuous corners:"),1)



if __name__=="__main__":
    unittest.main()
