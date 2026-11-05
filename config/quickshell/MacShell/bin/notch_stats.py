#!/usr/bin/env python3
"""Read-only, demand-started system telemetry. One JSON snapshot per second.

CPU/memory/net: docs.kernel.org/filesystems/proc.html
GPU: kernel.org/doc/html/latest/gpu/amdgpu/thermal.html
Temperature: docs.kernel.org/hwmon/sysfs-interface.html
"""
import argparse
import csv
import json
import math
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import time


def number(text):
    try:
        value = float(text)
        return value if math.isfinite(value) else None
    except (ValueError, TypeError):
        return None


class Sampler:
    def __init__(self, root="/", clock=time.monotonic):
        self.root = Path(root)
        self.clock = clock
        self.previous_cpu = None
        self.previous_net = None
        self.slow_at = -float("inf")
        self.slow = {}

    def path(self, name):
        return self.root / name.lstrip("/")

    def read(self, name):
        try:
            return self.path(name).read_text().strip()
        except (OSError, UnicodeError):
            return ""

    def value(self, name):
        return number(self.read(name))

    def cpu(self):
        fields = self.read("/proc/stat").splitlines()
        if not fields or not fields[0].startswith("cpu "):
            self.previous_cpu = None
            return {"cpu": None, "cpuStatus": "CPU unavailable"}
        try:
            # guest/guest_nice are already included in user/nice.
            ticks = [int(n) for n in fields[0].split()[1:9]]
            if len(ticks) < 5 or min(ticks) < 0:
                raise ValueError
        except ValueError:
            self.previous_cpu = None
            return {"cpu": None, "cpuStatus": "CPU unavailable"}
        current = (sum(ticks), ticks[3] + ticks[4])
        previous, self.previous_cpu = self.previous_cpu, current
        value = None
        if previous and current[0] > previous[0] and current[1] >= previous[1]:
            total, idle = current[0] - previous[0], current[1] - previous[1]
            if idle <= total:
                value = round(100 * (total - idle) / total, 2)
        return {"cpu": value, "cpuStatus": "Live" if value is not None else "Sampling…"}

    def memory(self):
        fields = {}
        for line in self.read("/proc/meminfo").splitlines():
            match = re.match(r"(\w+):\s+(\d+)", line)
            if match:
                fields[match[1]] = int(match[2]) * 1024
        total = fields.get("MemTotal", 0)
        if not total:
            return {"ram": None}
        available = fields.get("MemAvailable")
        if available is None:
            available = sum(fields.get(k, 0) for k in ["MemFree", "Buffers", "Cached", "SReclaimable"]) - fields.get("Shmem", 0)
        used = max(0, min(total, total - available))
        return {"ram": round(used / total * 100, 2), "ramUsed": used, "ramTotal": total}

    def storage(self):
        try:
            stat = os.statvfs(self.root)
            total = stat.f_blocks * stat.f_frsize
            used = (stat.f_blocks - stat.f_bfree) * stat.f_frsize
            if total > 0:
                return {"disk": round(max(0, min(1, used / total)) * 100, 2), "diskUsed": used, "diskTotal": total}
        except OSError:
            pass
        return {"disk": None}

    def battery(self):
        values = []
        statuses = []
        for directory in self.path("/sys/class/power_supply").glob("*"):
            base = "/sys/class/power_supply/" + directory.name
            if self.read(base + "/type") != "Battery" or self.read(base + "/present") == "0":
                continue
            capacity = self.value(base + "/capacity")
            energy, full = self.value(base + "/energy_now"), self.value(base + "/energy_full")
            if full is None:
                charge, charge_full = self.value(base + "/charge_now"), self.value(base + "/charge_full")
                voltage = self.value(base + "/voltage_min_design") or self.value(base + "/voltage_now")
                if charge is not None and charge_full and voltage:
                    energy, full = charge * voltage / 1e6, charge_full * voltage / 1e6
            if energy is not None and full and full > 0:
                capacity = max(0, min(100, energy / full * 100))
            if capacity is not None and 0 <= capacity <= 100:
                values.append((capacity, full if full and full > 0 else None))
                statuses.append(self.read(base + "/status"))
        if not values:
            return {"battery": None, "batteryStatus": "No battery detected"}
        weighted = all(weight is not None for _, weight in values)
        percent = sum(value * weight for value, weight in values) / sum(weight for _, weight in values) if weighted else sum(value for value, _ in values) / len(values)
        status = "Charging" if "Charging" in statuses else "Discharging" if "Discharging" in statuses else "Full" if all(s == "Full" for s in statuses) else "Connected"
        return {"battery": round(percent, 2), "batteryStatus": status}

    def network(self, now):
        text = self.read("/proc/net/dev")
        if not text:
            self.previous_net = None
            return {"network": None, "upload": None, "interfaces": []}
        counters = {}
        for line in text.splitlines():
            if ":" not in line:
                continue
            name, data = line.split(":", 1)
            name, fields = name.strip(), data.split()
            if name == "lo" or len(fields) < 16:
                continue
            try:
                rx, tx = int(fields[0]), int(fields[8])
                if rx >= 0 and tx >= 0:
                    counters[name] = (rx, tx)
            except ValueError:
                continue
        # Count physical links once, so VPNs/bridges do not duplicate traffic.
        physical = [name for name in counters if self.path("/sys/class/net/" + name + "/device").exists() and self.read("/sys/class/net/" + name + "/operstate") not in ("down", "notpresent")]
        selected = physical or [name for name in counters if not re.match(r"^(lo|veth|docker|virbr|br-|tun|tap|wg)", name)]
        if not selected:
            selected = [name for name in counters if not re.match(r"^(veth|docker|virbr|br-)", name)]
        current = {name: counters[name] for name in selected}
        previous, self.previous_net = self.previous_net, (now, current)
        rx_rate = tx_rate = None
        if not current:
            rx_rate = tx_rate = 0
        elif previous and now > previous[0]:
            dt = now - previous[0]
            deltas = [(rx - previous[1][name][0], tx - previous[1][name][1]) for name, (rx, tx) in current.items() if name in previous[1] and rx >= previous[1][name][0] and tx >= previous[1][name][1]]
            if deltas:
                rx_rate = sum(d[0] for d in deltas) / dt
                tx_rate = sum(d[1] for d in deltas) / dt
        return {"network": rx_rate, "upload": tx_rate, "interfaces": selected[:16]}

    def temperature(self):
        candidates = []
        for directory in self.path("/sys/class/hwmon").glob("hwmon*"):
            base = "/sys/class/hwmon/" + directory.name
            name = self.read(base + "/name").lower()
            cpu = name in ("coretemp", "k10temp", "zenpower", "cpu_thermal", "x86_pkg_temp")
            for sensor in directory.glob("temp*_input"):
                prefix = base + "/" + sensor.name.removesuffix("_input")
                label = self.read(prefix + "_label")
                cpu_label = bool(re.search(r"package|tctl|tdie|\bcpu\b", label, re.I))
                if not cpu and not cpu_label:
                    continue
                value = self.value(prefix + "_input")
                if value is None or not -50000 <= value <= 200000:
                    continue
                critical = self.value(prefix + "_crit")
                high = self.value(prefix + "_max")
                candidates.append((0 if cpu_label else 1, -value, {"temperature": value / 1000, "temperatureLabel": label or name, "temperatureCritical": critical / 1000 if critical else None, "temperatureMax": high / 1000 if high else None}))
        if candidates:
            return min(candidates, key=lambda c: (c[0], c[1]))[2]
        for directory in self.path("/sys/class/thermal").glob("thermal_zone*"):
            base = "/sys/class/thermal/" + directory.name
            label = self.read(base + "/type")
            if not re.search(r"cpu|package|x86_pkg|soc_thermal", label, re.I):
                continue
            value = self.value(base + "/temp")
            if value is not None and -50000 <= value <= 200000:
                return {"temperature": value / 1000, "temperatureLabel": label}
        return {"temperature": None, "temperatureLabel": "CPU sensor unavailable"}

    def gpu(self):
        choices = []
        nvidia_active = False
        found = []
        for card in self.path("/sys/class/drm").glob("card*"):
            if not re.fullmatch(r"card\d+", card.name):
                continue
            base = "/sys/class/drm/" + card.name + "/device"
            vendor = self.read(base + "/vendor").lower()
            label = {"0x1002": "AMD GPU", "0x10de": "NVIDIA GPU", "0x8086": "Intel GPU"}.get(vendor, "GPU")
            sleeping = self.read(base + "/power/runtime_status") == "suspended"
            found.append((label, sleeping))
            try:
                driver = self.path(base + "/driver").resolve().name
            except OSError:
                driver = ""
            nvidia_active |= vendor == "0x10de" and driver == "nvidia" and not sleeping
            if sleeping:
                continue
            busy = self.value(base + "/gpu_busy_percent")
            if busy is not None and 0 <= busy <= 100:
                choices.append({"gpu": busy, "gpuName": label, "gpuStatus": "Live"})
        binary = shutil.which("nvidia-smi") if nvidia_active and self.root == Path("/") else None
        if binary:
            process = None
            try:
                process = subprocess.Popen([binary, "--query-gpu=utilization.gpu,name", "--format=csv,noheader,nounits"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
                output, _ = process.communicate(timeout=0.7)
                if process.returncode == 0:
                    for row in csv.reader(output.splitlines()):
                        value = number(row[0]) if row else None
                        if value is not None and 0 <= value <= 100:
                            choices.append({"gpu": value, "gpuName": row[1].strip()[:120] if len(row) > 1 else "NVIDIA GPU", "gpuStatus": "Live"})
            except (OSError, subprocess.TimeoutExpired):
                pass
            finally:
                if process is not None:
                    if process.poll() is None:
                        process.kill()
                    process.wait()
        if choices:
            return max(choices, key=lambda c: c["gpu"])
        return {"gpu": None, "gpuName": found[0][0] if found else "GPU", "gpuStatus": "Sleeping GPU" if found and all(s for _, s in found) else "Usage not exposed by driver"}

    def snapshot(self):
        now = self.clock()
        if now - self.slow_at >= 15:
            self.slow = {**self.storage()}
            self.slow_at = now
        return {"at": round(time.time() * 1000), **self.cpu(), **self.memory(), **self.network(now), **self.battery(), **self.temperature(), **self.gpu(), **self.slow}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default="/", help="alternate proc/sys tree for tests")
    parser.add_argument("--samples", type=int, default=0, help="stop after N snapshots; 0 streams")
    parser.add_argument("--interval", type=float, default=1)
    args = parser.parse_args()
    if not math.isfinite(args.interval) or not 0.2 <= args.interval <= 10 or args.samples < 0:
        parser.error("interval must be 0.2–10 seconds and samples must be nonnegative")
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    sampler = Sampler(args.root)
    deadline, count = time.monotonic(), 0
    try:
        while True:
            print(json.dumps(sampler.snapshot(), allow_nan=False, separators=(",", ":")), flush=True)
            count += 1
            if args.samples and count >= args.samples:
                break
            deadline = max(deadline + args.interval, time.monotonic())
            time.sleep(max(0, deadline - time.monotonic()))
    except (BrokenPipeError, KeyboardInterrupt):
        pass


if __name__ == "__main__":
    main()
