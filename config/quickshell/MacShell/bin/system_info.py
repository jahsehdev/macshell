#!/usr/bin/env python3
"""Read local system information for About This Linux; no elevated access."""
import json
import os
from pathlib import Path
import platform
import re
import shlex
import shutil
import subprocess


def read(path):
    try:
        return Path(path).read_text(errors="replace").strip()
    except OSError:
        return ""


def clean(value):
    value = value.strip()
    placeholder = re.sub(r"[^a-z0-9]", "", value.lower())
    if placeholder in {"", "0", "none", "unknown", "notapplicable", "notavailable",
                       "tobefilledbyoem", "defaultstring", "systemproductname",
                       "systemmanufacturer", "systemversion", "123456789"}:
        return ""
    return value


def os_release(text):
    result = {}
    for line in text.splitlines():
        key, sep, value = line.partition("=")
        if sep and re.fullmatch(r"[A-Z_]+", key):
            try:
                words = shlex.split(value)
                result[key] = " ".join(words)
            except ValueError:
                pass
    return result


def command(args):
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=2,
                              check=False).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""


def collect():
    release = os_release(read("/etc/os-release") or read("/usr/lib/os-release"))
    dmi = Path("/sys/class/dmi/id")
    vendor = clean(read(dmi / "sys_vendor"))
    model = clean(read(dmi / "product_name"))
    chassis = read(dmi / "chassis_type")
    portable = chassis in {"8", "9", "10", "11", "14", "30", "31", "32"}
    form = "Laptop" if portable else "Desktop"
    brand = vendor.split()[0] if vendor else ""
    name = model or (f"{brand} {form}" if brand else f"Linux {form}")
    if model and brand and brand.lower() not in model.lower():
        name = f"{brand} {model}"
    if name.isupper():
        name = name.title()
    cpu_info = read("/proc/cpuinfo")
    cpu = re.search(r"^(?:model name|Hardware)\s*:\s*(.+)$", cpu_info, re.M)
    full_cpu = cpu.group(1).strip() if cpu else platform.processor() or platform.machine()
    short_cpu = re.sub(r"\(R\)|\(TM\)|®|™", "", full_cpu, flags=re.I)
    short_cpu = re.sub(r"\s+(?:CPU|Processor)\b", "", short_cpu, flags=re.I)
    short_cpu = re.sub(r"\s*@.*$", "", short_cpu).strip()
    mem = re.search(r"^MemTotal:\s*(\d+)", read("/proc/meminfo"), re.M)
    memory = f"{int(mem.group(1)) / 1024**2:.1f} GiB" if mem else "Not available"
    distro = release.get("NAME") or "Linux"
    version = release.get("VERSION_ID") or release.get("BUILD_ID") or ""
    desktop_version = command(["pacman", "-Q", "hyprland"]).split()
    desktop = "Hyprland" + (" " + desktop_version[1] if len(desktop_version) == 2 else "")
    graphics = []
    for line in command(["lspci", "-mm"]).splitlines():
        try:
            fields = shlex.split(line)
        except ValueError:
            continue
        if len(fields) >= 4 and any(kind in fields[1] for kind in ("VGA", "3D controller", "Display controller")):
            graphics.append(" ".join(fields[2:4]))
    try:
        disk = shutil.disk_usage("/")
        storage = f"{disk.total / 10**9:.0f} GB · {disk.free / 10**9:.0f} GB available"
    except OSError:
        storage = "Not available"
    return {
        "deviceName": name, "vendor": vendor or "Not available", "model": model or form,
        "formFactor": form, "portable": portable, "processor": short_cpu,
        "processorFull": full_cpu, "cpuThreads": os.cpu_count() or 1,
        "memory": memory, "serial": clean(read(dmi / "product_serial")) or "Not available",
        "distro": distro, "version": version, "kernel": platform.release(),
        "architecture": platform.machine(), "desktop": desktop,
        "graphics": ", ".join(graphics) or "Not available", "storage": storage,
        "firmware": " ".join(filter(None, [clean(read(dmi / "bios_vendor")), clean(read(dmi / "bios_version"))])) or "Not available",
    }


if __name__ == "__main__":
    print(json.dumps(collect(), ensure_ascii=False))
