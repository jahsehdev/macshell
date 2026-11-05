import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

HELPER = Path(__file__).resolve().parents[1] / "bin/notch_stats.py"
spec = importlib.util.spec_from_file_location("notch_stats", HELPER)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class StatsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.s = module.Sampler(self.root)

    def tearDown(self):
        self.temp.cleanup()

    def put(self, path, value):
        p = self.root / path.lstrip("/")
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(str(value))

    def net(self, entries):
        self.put("/proc/net/dev", "Inter-| Receive | Transmit\n" + "\n".join(name + ": " + " ".join(map(str, [rx] + [0] * 7 + [tx] + [0] * 7)) for name, rx, tx in entries))

    def test_cpu_uses_deltas_and_excludes_double_counted_guest_ticks(self):
        self.put("/proc/stat", "cpu 100 0 50 800 50 0 0 0 10 0\n")
        self.assertIsNone(self.s.cpu()["cpu"])
        self.put("/proc/stat", "cpu 120 0 60 870 50 0 0 0 25 0\n")
        self.assertEqual(self.s.cpu()["cpu"], 30)
        self.put("/proc/stat", "cpu 1 0 1 10 0 0 0 0 0 0\n")
        self.assertIsNone(self.s.cpu()["cpu"])

    def test_unreadable_cpu_is_unknown(self):
        self.assertIsNone(self.s.cpu()["cpu"])
        self.put("/proc/stat", "cpu corrupt\n")
        self.assertEqual(self.s.cpu()["cpuStatus"], "CPU unavailable")

    def test_memory_uses_available_including_reclaimable_cache(self):
        self.put("/proc/meminfo", "MemTotal: 1000 kB\nMemAvailable: 400 kB\nMemFree: 10 kB\n")
        self.assertEqual(self.s.memory()["ram"], 60)
        self.assertEqual(self.s.memory()["ramUsed"], 600 * 1024)
        self.put("/proc/meminfo", "MemTotal: 1000 kB\nMemFree: 100 kB\nBuffers: 50 kB\nCached: 300 kB\nSReclaimable: 50 kB\nShmem: 20 kB\n")
        self.assertEqual(self.s.memory()["ram"], 52)

    def test_storage_is_capacity_of_root_volume(self):
        fake = SimpleNamespace(f_blocks=100, f_bfree=25, f_frsize=4096)
        with patch.object(module.os, "statvfs", return_value=fake):
            self.assertEqual(self.s.storage()["disk"], 75)
            self.assertEqual(self.s.storage()["diskUsed"], 75 * 4096)

    def test_network_ignores_loopback_and_duplicate_tunnel_traffic(self):
        self.put("/sys/class/net/eth0/device/present", 1)
        self.put("/sys/class/net/eth0/operstate", "up")
        self.net([("eth0", 1000, 1000), ("wg0", 1000, 1000), ("lo", 100000, 100000)])
        self.assertIsNone(self.s.network(10)["network"])
        self.net([("eth0", 5000, 3000), ("wg0", 5000, 3000), ("lo", 500000, 500000)])
        reading = self.s.network(12)
        self.assertEqual(reading["network"], 2000)
        self.assertEqual(reading["upload"], 1000)
        self.assertEqual(reading["interfaces"], ["eth0"])

    def test_network_resets_and_hotplug_do_not_invent_negative_or_zero_rates(self):
        self.net([("eth0", 1000, 1000)])
        self.s.network(1)
        self.net([("eth0", 100, 100)])
        self.assertIsNone(self.s.network(2)["network"])
        self.net([("eth1", 1000, 1000)])
        self.assertIsNone(self.s.network(3)["network"])
        self.net([("eth1", 1200, 1100)])
        self.assertEqual(self.s.network(4)["network"], 200)

    def test_missing_network_differs_from_offline(self):
        self.assertIsNone(self.s.network(1)["network"])
        self.net([("lo", 500, 500)])
        self.assertEqual(self.s.network(2)["network"], 0)

    def test_batteries_are_weighted_by_energy(self):
        for name, full, now, status in [("BAT0", 100, 50, "Charging"), ("BAT1", 300, 300, "Full")]:
            for key, value in [("type", "Battery"), ("energy_full", full), ("energy_now", now), ("status", status)]:
                self.put("/sys/class/power_supply/" + name + "/" + key, value)
        value = self.s.battery()
        self.assertEqual(value["battery"], 87.5)
        self.assertEqual(value["batteryStatus"], "Charging")

    def test_no_battery_is_unknown_not_zero(self):
        self.assertIsNone(self.s.battery()["battery"])

    def test_cpu_temperature_precedes_gpu_and_keeps_firmware_thresholds(self):
        base = "/sys/class/hwmon/hwmon0/"
        for name, value in [("name", "coretemp"), ("temp1_label", "Package id 0"), ("temp1_input", 54000), ("temp1_max", 80000), ("temp1_crit", 100000), ("temp2_label", "Core 0"), ("temp2_input", 59000)]:
            self.put(base + name, value)
        self.put("/sys/class/hwmon/hwmon1/name", "amdgpu")
        self.put("/sys/class/hwmon/hwmon1/temp1_input", 95000)
        value = self.s.temperature()
        self.assertEqual(value["temperature"], 54)
        self.assertEqual(value["temperatureCritical"], 100)
        self.assertEqual(value["temperatureMax"], 80)

    def test_invalid_temperature_is_unavailable(self):
        self.put("/sys/class/hwmon/hwmon0/name", "coretemp")
        self.put("/sys/class/hwmon/hwmon0/temp1_input", 999999)
        self.assertIsNone(self.s.temperature()["temperature"])

    def test_gpu_selects_exposed_busy_gpu_and_leaves_sleeping_gpu_alone(self):
        for name, busy in [("card0", 37), ("card1", 87), ("card0-HDMI-A-1", 100)]:
            self.put("/sys/class/drm/" + name + "/device/vendor", "0x1002")
            self.put("/sys/class/drm/" + name + "/device/gpu_busy_percent", busy)
        self.assertEqual(self.s.gpu()["gpu"], 87)
        self.put("/sys/class/drm/card1/device/power/runtime_status", "suspended")
        self.assertEqual(self.s.gpu()["gpu"], 37)
        self.put("/sys/class/drm/card0/device/power/runtime_status", "suspended")
        self.assertIsNone(self.s.gpu()["gpu"])
        self.assertEqual(self.s.gpu()["gpuStatus"], "Sleeping GPU")

    def test_cli_streams_bounded_valid_json_without_hardware(self):
        self.put("/proc/stat", "cpu 1 0 1 10 0 0 0 0\n")
        result = subprocess.run([sys.executable, "-B", str(HELPER), "--root", str(self.root), "--samples", "2", "--interval", ".2"], capture_output=True, text=True, timeout=4)
        self.assertEqual(result.returncode, 0, result.stderr)
        values = [json.loads(line) for line in result.stdout.splitlines()]
        self.assertEqual(len(values), 2)
        self.assertGreater(values[1]["at"], values[0]["at"])
        self.assertIsNone(values[0]["cpu"])
        self.assertIsNone(values[0]["gpu"])


if __name__ == "__main__":
    unittest.main()
