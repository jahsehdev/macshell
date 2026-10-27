import copy
from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'bin'))
from window_corners import expanded, dock_rounded, sync, SQUARE_TAG, DOCK_ROUNDED_TAG

class Backend:
    def __init__(self): self.calls=[]
    def tag(self, address, tag): self.calls.append((address,tag))

class CornerTests(unittest.TestCase):
    def setUp(self):
        self.monitor=dict(id=0,x=0,y=0,width=1280,height=800,scale=1,reserved=[0,28,0,0])
        self.window=dict(address='0xaa',monitor=0,pid=123,title='Example',mapped=True,hidden=False,
            fullscreen=0,fullscreenClient=0,at=[100,100],size=[800,500],tags=[])
    def test_normal_window_retains_rounded_corners(self):
        self.assertFalse(expanded(self.window,self.monitor))
    def test_client_fullscreen_flags_on_small_window_keep_rounded_corners(self):
        for key in ['fullscreen','fullscreenClient','fullscreen_client']:
            for mode in [1,2,3]:
                self.assertFalse(expanded({**self.window,key:mode},self.monitor))
    def test_fullscreen_and_zoom_geometry_use_square_corners(self):
        self.assertTrue(expanded({**self.window,'fullscreen':2,'at':[0,0],'size':[1280,800]},self.monitor))
        self.assertTrue(expanded({**self.window,'fullscreenClient':1,'at':[0,28],'size':[1280,772]},self.monitor))
    def test_exit_f11_restores_corners_even_if_client_flag_lingers(self):
        backend=Backend()
        window={**self.window,'fullscreenClient':2,'tags':[SQUARE_TAG]}
        self.assertEqual(sync(backend,[window],[self.monitor]),[])
        self.assertEqual(backend.calls,[('0xaa','-'+SQUARE_TAG)])
    def test_floating_fill_without_flags_uses_square_corners(self):
        self.assertTrue(expanded({**self.window,'at':[0,28],'size':[1280,772]},self.monitor))
    def test_restore_removes_only_the_square_corner_tag(self):
        backend=Backend();window={**self.window,'fullscreenClient':1,'at':[0,28],'size':[1280,772]}
        result=sync(backend,[window],[self.monitor])
        self.assertEqual(backend.calls,[('0xaa','+'+SQUARE_TAG)])
        self.assertEqual(result,[dict(pid=123,title='Example',address='0xaa')])
        backend.calls=[]
        window={**self.window,'tags':[SQUARE_TAG,'macshell-native-controls']}
        self.assertEqual(sync(backend,[window],[self.monitor]),[])
        self.assertEqual(backend.calls,[('0xaa','-'+SQUARE_TAG)])
    def test_existing_state_does_not_retag_every_poll(self):
        backend=Backend();window={**self.window,'fullscreen':2,'at':[0,0],'size':[1280,800],'tags':[SQUARE_TAG]}
        sync(backend,[window],[self.monitor]);self.assertEqual(backend.calls,[])
    def test_scaled_rotated_workarea_and_other_monitor(self):
        monitor={**self.monitor,'id':1,'x':1280,'width':1600,'height':2560,'scale':2,'transform':1}
        window={**self.window,'monitor':1,'at':[1280,28],'size':[1280,772]}
        self.assertTrue(expanded(window,monitor))
        backend=Backend();self.assertEqual(len(sync(backend,[window],[self.monitor,monitor])),1)
    def test_hidden_or_pinned_window_is_not_geometry_tagged(self):
        self.assertFalse(expanded({**self.window,'hidden':True,'fullscreen':2},self.monitor))
        self.assertFalse(expanded({**self.window,'pinned':True,'fullscreen':2},self.monitor))

class NeverHideCornerTests(unittest.TestCase):
    def setUp(self):
        self.monitor=dict(id=0,name='VGA-1',x=0,y=0,width=1280,height=800,
                          scale=1,reserved=[0,28,0,64])
        self.window=dict(address='0xaa',monitor=0,pid=123,title='Settings',mapped=True,
                         floating=True,at=[0,28],size=[1280,708],tags=[])
        self.settings=dict(hideMode='never',dockEnabled=True,monitor='')
    def test_fill_and_zoom_beside_dock_keep_rounded_corners(self):
        for state in ({},{'fullscreenClient':1},{'fullscreen_client':1},{'fullscreen':1}):
            with self.subTest(state=state):
                backend=Backend()
                window={**self.window,**state}
                self.assertTrue(dock_rounded(window,self.monitor,self.settings))
                self.assertEqual(sync(backend,[window],[self.monitor],self.settings),[])
                self.assertEqual(backend.calls,[('0xaa','+'+DOCK_ROUNDED_TAG)])
    def test_existing_square_window_becomes_rounded(self):
        backend=Backend()
        window={**self.window,'tags':[SQUARE_TAG,'macshell-zoomed']}
        sync(backend,[window],[self.monitor],self.settings)
        self.assertEqual(backend.calls,[('0xaa','-'+SQUARE_TAG),('0xaa','+'+DOCK_ROUNDED_TAG)])
    def test_desktop_covering_fullscreen_stays_square(self):
        backend=Backend()
        window={**self.window,'at':[0,0],'size':[1280,800],'fullscreen':2}
        self.assertFalse(dock_rounded(window,self.monitor,self.settings))
        self.assertEqual(len(sync(backend,[window],[self.monitor],self.settings)),1)
        self.assertEqual(backend.calls,[('0xaa','+'+SQUARE_TAG)])
    def test_stale_fullscreen_flag_does_not_override_workarea_geometry(self):
        self.assertTrue(dock_rounded({**self.window,'fullscreenClient':2},self.monitor,self.settings))
    def test_smart_always_and_disabled_dock_do_not_force_32px(self):
        for settings in ({**self.settings,'hideMode':'smart'},
                         {**self.settings,'hideMode':'always'},
                         {**self.settings,'dockEnabled':False}):
            self.assertFalse(dock_rounded(self.window,self.monitor,settings))
    def test_only_the_selected_display_rounds(self):
        self.assertFalse(dock_rounded(self.window,self.monitor,{**self.settings,'monitor':'HDMI-A-1'}))
        self.assertTrue(dock_rounded(self.window,self.monitor,{**self.settings,'monitor':'VGA-1'}))
    def test_dock_must_actually_reserve_space(self):
        monitor={**self.monitor,'reserved':[0,28,0,0]}
        window={**self.window,'size':[1280,772]}
        self.assertFalse(dock_rounded(window,monitor,self.settings))
    def test_side_docks_and_scaled_rotated_display(self):
        for reserved,at,size in (([64,28,0,0],[64,28],[1216,772]),
                                 ([0,28,64,0],[0,28],[1216,772])):
            monitor={**self.monitor,'x':1280,'y':200,'width':1600,'height':2560,
                     'scale':2,'transform':1,'reserved':reserved}
            window={**self.window,'at':[1280+at[0],200+at[1]],'size':size}
            self.assertTrue(dock_rounded(window,monitor,self.settings))
    def test_restore_removes_32px_override_and_keeps_other_tags(self):
        backend=Backend()
        window={**self.window,'at':[100,100],'size':[800,500],
                'tags':[DOCK_ROUNDED_TAG,'macshell-native-controls']}
        sync(backend,[window],[self.monitor],self.settings)
        self.assertEqual(backend.calls,[('0xaa','-'+DOCK_ROUNDED_TAG)])
    def test_stable_rounded_window_is_not_retagged(self):
        backend=Backend()
        sync(backend,[{**self.window,'tags':[DOCK_ROUNDED_TAG]}],[self.monitor],self.settings)
        self.assertEqual(backend.calls,[])

if __name__=='__main__': unittest.main()
