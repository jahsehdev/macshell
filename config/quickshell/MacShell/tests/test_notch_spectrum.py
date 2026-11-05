import importlib.util
import math
from array import array
from pathlib import Path
import subprocess
import sys
import json
import unittest

SCRIPT=Path(__file__).resolve().parents[1]/'bin/notch_spectrum.py'
spec=importlib.util.spec_from_file_location('notch_spectrum',SCRIPT)
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)


def tone(hz,amplitude=0.5):
    samples=array('h',(round(amplitude*32767*math.sin(2*math.pi*hz*i/module.RATE)) for i in range(module.SIZE)))
    if sys.byteorder!='little':samples.byteswap()
    return samples.tobytes()


class SpectrumTests(unittest.TestCase):
    def test_silence_is_flat_and_values_are_bounded(self):
        self.assertEqual(module.spectrum(bytes(module.SIZE*2)),[0]*24)
        self.assertTrue(all(0<=x<=1 for x in module.spectrum(tone(440,1))))

    def test_peaks_follow_frequency(self):
        for frequency in [220,880,3500]:
            bands=module.spectrum(tone(frequency))
            peak=max(range(24),key=bands.__getitem__)
            expected=24*math.log(frequency/50)/math.log(9000/50)
            self.assertLess(abs(peak-expected),1.5)
            self.assertGreater(bands[peak],0.7)

    def test_quieter_signal_produces_lower_peak(self):
        self.assertGreater(max(module.spectrum(tone(880,0.5))),max(module.spectrum(tone(880,0.02))))

    def test_stream_handles_partial_pcm_and_emits_complete_windows(self):
        result=subprocess.run([sys.executable,str(SCRIPT),'--stdin'],input=tone(880)*2+b'\0',capture_output=True,timeout=5,check=True)
        events=[json.loads(line) for line in result.stdout.splitlines()]
        self.assertEqual(len(events),2)
        self.assertTrue(all(len(event['bands'])==24 for event in events))


if __name__=='__main__':unittest.main()
