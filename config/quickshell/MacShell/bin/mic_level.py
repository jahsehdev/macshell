#!/usr/bin/env python3
"""Stream microphone RMS as JSON lines. Audio stays in memory and is discarded."""
import argparse
from array import array
import ctypes
import json
import math
import os
import selectors
import shutil
import signal
import subprocess
import sys


class CaptureStopped(Exception):
    pass


def emit(**event):
    print(json.dumps(event, separators=(",", ":")), flush=True)


def stop_capture(signum, frame):
    raise CaptureStopped()


class Envelope:
    """dBFS mapping with a fast attack and slower, frame-rate-independent release."""
    def __init__(self, floor_db=-58.0, ceiling_db=-12.0, attack=0.035, release=0.22):
        self.floor_db = floor_db
        self.ceiling_db = ceiling_db
        self.attack = attack
        self.release = release
        self.volume = 0.0

    def update(self, pcm, rate):
        samples = array("h")
        samples.frombytes(pcm)
        if not samples:
            return 0.0
        rms = math.sqrt(sum(float(x) * x for x in samples) / len(samples)) / 32768.0
        db = 20.0 * math.log10(max(rms, 1e-9))
        target = min(1.0, max(0.0, (db - self.floor_db) / (self.ceiling_db - self.floor_db)))
        tau = self.attack if target > self.volume else self.release
        self.volume += (target - self.volume) * (1.0 - math.exp(-len(samples) / (rate * tau)))
        return min(1.0, max(0.0, self.volume))


def recorder_commands(backend, source, rate):
    commands = []
    if backend in ("auto", "pipewire") and shutil.which("pw-cat"):
        commands.append(("pipewire", ["pw-cat", "--record", "--raw", "--format=s16",
            f"--rate={rate}", "--channels=1", "--latency=30ms", "--media-role=Communication",
            f"--target={source or 'auto'}", "-"]))
    if backend in ("auto", "pulse") and shutil.which("parec"):
        commands.append(("pulse", ["parec", "--raw", "--format=s16ne", f"--rate={rate}",
            "--channels=1", "--latency-msec=30", "--process-time-msec=15",
            "--client-name=Luma Microphone", "--stream-name=Luma volume visualizer",
            f"--device={source or '@DEFAULT_SOURCE@'}"]))
    return commands


def stream_levels(stream, rate, fps, envelope):
    # Read exact PCM windows; a pipe read can contain a fraction of one sample.
    window = max(1, round(rate / fps)) * 2
    pending = bytearray()
    with selectors.DefaultSelector() as selector:
        selector.register(stream, selectors.EVENT_READ)
        while True:
            if not selector.select(timeout=2):
                raise RuntimeError("Microphone did not deliver audio. Check the selected input device.")
            chunk = os.read(stream.fileno(), window - len(pending))
            if not chunk:
                return
            pending.extend(chunk)
            if len(pending) == window:
                emit(event="level", volume=round(envelope.update(pending, rate), 5))
                pending.clear()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--backend", choices=("auto", "pipewire", "pulse"), default="auto")
    parser.add_argument("--source", default="", help="Node name/serial (PipeWire) or source name (PulseAudio)")
    parser.add_argument("--rate", type=int, default=16000)
    parser.add_argument("--fps", type=int, default=30)
    parser.add_argument("--floor-db", type=float, default=-58.0)
    parser.add_argument("--ceiling-db", type=float, default=-12.0)
    parser.add_argument("--stdin", action="store_true", help="Read native-endian mono signed 16-bit PCM from stdin")
    args = parser.parse_args(argv)
    if not 8000 <= args.rate <= 48000 or not 10 <= args.fps <= 60:
        parser.error("rate must be 8000..48000 and fps must be 10..60")
    if not math.isfinite(args.floor_db) or not math.isfinite(args.ceiling_db) or args.floor_db >= args.ceiling_db:
        parser.error("floor-db must be below ceiling-db and both must be finite")
    signal.signal(signal.SIGTERM, stop_capture)
    signal.signal(signal.SIGINT, stop_capture)
    # Also release the recorder if Quickshell is killed unexpectedly (Linux).
    parent = os.getppid()
    if sys.platform == "linux":
        ctypes.CDLL(None).prctl(1, signal.SIGTERM, 0, 0, 0)
        if os.getppid() != parent:
            return 0
    recorder = None
    try:
        if args.stdin:
            stream_levels(sys.stdin.buffer, args.rate, args.fps, Envelope(args.floor_db, args.ceiling_db))
            return 0
        commands = recorder_commands(args.backend, args.source, args.rate)
        if not commands:
            raise RuntimeError("Install PipeWire's pw-cat or PulseAudio's parec to use the microphone.")
        failure = "Could not open the microphone. Check audio service and input device."
        for backend, command in commands:
            recorder = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                        stdin=subprocess.DEVNULL, bufsize=0)
            emit(event="status", backend=backend, status="connecting")
            try:
                stream_levels(recorder.stdout, args.rate, args.fps, Envelope(args.floor_db, args.ceiling_db))
            except RuntimeError as exc:
                failure = str(exc)
            finally:
                if recorder.poll() is None:
                    recorder.terminate()
                try:
                    recorder.wait(timeout=1)
                except subprocess.TimeoutExpired:
                    recorder.kill()
                    recorder.wait()
                recorder.stdout.close()
                recorder = None
        raise RuntimeError(failure)
    except (CaptureStopped, BrokenPipeError):
        return 0
    except (OSError, RuntimeError) as exc:
        emit(event="error", message=str(exc))
        return 1
    finally:
        if recorder is not None:
            if recorder.poll() is None:
                recorder.terminate()
            try:
                recorder.wait(timeout=1)
            except subprocess.TimeoutExpired:
                recorder.kill()
                recorder.wait()


if __name__ == "__main__":
    raise SystemExit(main())
