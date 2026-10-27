from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "bin"))
import system_info


class SystemInfoTests(unittest.TestCase):
    def test_placeholder_firmware_values_are_not_shown_as_real_hardware(self):
        for value in ["To be filled by O.E.M.", "Default string", "System Product Name", "None", ""]:
            self.assertEqual(system_info.clean(value), "")
        self.assertEqual(system_info.clean(" TACTICAL "), "TACTICAL")

    def test_release_parser_handles_quotes_and_never_evaluates_shell(self):
        result = system_info.os_release('NAME="Example Linux"\nVERSION_ID=42\nHOME_URL="$(touch /tmp/example)"\n')
        self.assertEqual(result["NAME"], "Example Linux")
        self.assertEqual(result["VERSION_ID"], "42")
        self.assertEqual(result["HOME_URL"], "$(touch /tmp/example)")

    def test_missing_or_unreadable_hardware_still_produces_a_complete_summary(self):
        with patch.object(system_info, "read", return_value=""), patch.object(system_info, "command", return_value=""):
            info = system_info.collect()
        self.assertEqual(info["deviceName"], "Linux Desktop")
        self.assertEqual(info["serial"], "Not available")
        self.assertEqual(info["memory"], "Not available")
        self.assertEqual(info["distro"], "Linux")
        self.assertTrue(info["processor"])

    def test_device_type_cpu_and_memory_come_from_the_machine(self):
        files = {
            "/etc/os-release": 'NAME="Example Linux"\nVERSION_ID="42"',
            "/sys/class/dmi/id/sys_vendor": "ACME Computers",
            "/sys/class/dmi/id/product_name": "TravelBook",
            "/sys/class/dmi/id/chassis_type": "10",
            "/proc/cpuinfo": "model name : Intel(R) Core(TM) i5-3330 CPU @ 3.00GHz\n",
            "/proc/meminfo": "MemTotal:        8388608 kB\n",
        }
        with patch.object(system_info, "read", side_effect=lambda path: files.get(str(path), "")), patch.object(system_info, "command", return_value=""):
            info = system_info.collect()
        self.assertTrue(info["portable"])
        self.assertEqual(info["deviceName"], "ACME TravelBook")
        self.assertEqual(info["processor"], "Intel Core i5-3330")
        self.assertEqual(info["memory"], "8.0 GiB")
        self.assertEqual(info["version"], "42")

    def test_unavailable_optional_programs_return_no_output(self):
        with patch.object(system_info.subprocess, "run", side_effect=FileNotFoundError):
            self.assertEqual(system_info.command(["missing-program"]), "")


if __name__ == "__main__":
    unittest.main()
