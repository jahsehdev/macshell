from pathlib import Path
import runpy
from types import SimpleNamespace
from unittest import TestCase, main
from unittest.mock import Mock

m=runpy.run_path(str(Path.home()/'.config/kitty/tab_bar.py'))
mouse=m['_mouse'];g=mouse.__globals__
boss=SimpleNamespace(confirm_os_window_close=Mock(),toggle_maximized=Mock())
g['get_boss']=lambda:boss
g['subprocess']=SimpleNamespace(Popen=Mock(),DEVNULL=-3)
g['_original_mouse']=Mock()
manager=SimpleNamespace(os_window_id=42,tab_bar=SimpleNamespace(laid_out_once=True,
    window_geometry=SimpleNamespace(top=5,bottom=25,left=0,right=800),cell_width=10),
    mark_tab_bar_dirty=Mock())
LEFT=m['GLFW_MOUSE_BUTTON_LEFT'];PRESS=m['GLFW_PRESS'];RELEASE=m['GLFW_RELEASE']

class Clicks(TestCase):
    def setUp(self):
        g['_pressed'].clear();g['_hover'].clear()
        boss.confirm_os_window_close.reset_mock();boss.toggle_maximized.reset_mock()
        g['subprocess'].Popen.reset_mock();g['_original_mouse'].reset_mock()
    def click(self,x):
        mouse(manager,x,12,LEFT,0,PRESS);mouse(manager,x,12,LEFT,0,RELEASE)
    def test_close_preserves_running_job_confirmation(self):
        self.click(15);boss.confirm_os_window_close.assert_called_once_with(42)
    def test_minimize_uses_dock_bridge(self):
        self.click(45)
        args=g['subprocess'].Popen.call_args.args[0]
        self.assertEqual(args[2:4],['minimize','kitty'])
    def test_maximize_targets_this_os_window(self):
        self.click(75);boss.toggle_maximized.assert_called_once_with(42)
    def test_dragging_between_buttons_does_not_close(self):
        mouse(manager,15,12,LEFT,0,PRESS);mouse(manager,75,12,LEFT,0,RELEASE)
        boss.confirm_os_window_close.assert_not_called();boss.toggle_maximized.assert_not_called()
    def test_release_without_press_does_not_close(self):
        mouse(manager,15,12,LEFT,0,RELEASE);boss.confirm_os_window_close.assert_not_called()
    def test_tabs_keep_original_mouse_behavior(self):
        mouse(manager,160,12,LEFT,0,PRESS)
        g['_original_mouse'].assert_called_once_with(manager,160,12,LEFT,0,PRESS)
    def test_terminal_area_is_not_a_button(self):
        mouse(manager,15,100,LEFT,0,PRESS)
        g['_original_mouse'].assert_called_once();boss.confirm_os_window_close.assert_not_called()
    def test_release_outside_cancels_button(self):
        mouse(manager,15,12,LEFT,0,PRESS);mouse(manager,200,12,LEFT,0,RELEASE)
        boss.confirm_os_window_close.assert_not_called()

main(argv=['kitty-controls-tests'])
