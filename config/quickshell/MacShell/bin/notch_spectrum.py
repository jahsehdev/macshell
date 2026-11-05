#!/usr/bin/env python3
"""Read only the system-output monitor; emit a spectrum, never store audio."""
from array import array
import argparse
import cmath
import json
import math
import os
import selectors
import signal
import subprocess
import sys

RATE = 22050
SIZE = 1024
BANDS = 24


def spectrum(pcm, rate=RATE):
    samples = array('h')
    samples.frombytes(pcm)
    if sys.byteorder != 'little':
        samples.byteswap()
    size = len(samples)
    if size < 2 or size & (size - 1):
        raise ValueError('PCM window must contain a power of two samples')
    values = [complex(s / 32768 * (0.5 - 0.5 * math.cos(2 * math.pi * i / (size - 1)))) for i, s in enumerate(samples)]
    j = 0
    for i in range(1, size):
        bit = size >> 1
        while j & bit:
            j ^= bit
            bit >>= 1
        j ^= bit
        if i < j:
            values[i], values[j] = values[j], values[i]
    step = 2
    while step <= size:
        root = cmath.exp(-2j * math.pi / step)
        for start in range(0, size, step):
            w = 1
            for k in range(start, start + step // 2):
                a, b = values[k], w * values[k + step // 2]
                values[k], values[k + step // 2] = a + b, a - b
                w *= root
        step *= 2
    bins = [abs(x) * 4 / size for x in values[:size // 2]]
    result = []
    for band in range(BANDS):
        low = 50 * (9000 / 50) ** (band / BANDS)
        high = 50 * (9000 / 50) ** ((band + 1) / BANDS)
        first = max(1, int(low * size / rate))
        last = max(first + 1, math.ceil(high * size / rate))
        peak = max(bins[first:min(last, len(bins))], default=0)
        result.append(round(max(0, min(1, (20 * math.log10(max(peak, 1e-9)) + 65) / 65)), 4))
    return result


def emit(**event):
    print(json.dumps(event, separators=(',', ':')), flush=True)


def stream(stream_in):
    pending = bytearray()
    levels = [0.0] * BANDS
    with selectors.DefaultSelector() as selector:
        selector.register(stream_in, selectors.EVENT_READ)
        while True:
            if not selector.select(timeout=3):
                raise RuntimeError('Audio output monitor did not deliver samples')
            chunk = os.read(stream_in.fileno(), SIZE * 2 - len(pending))
            if not chunk:
                return
            pending.extend(chunk)
            if len(pending) == SIZE * 2:
                current = spectrum(pending)
                levels = [max(now, old * 0.82) for now, old in zip(current, levels)]
                emit(bands=levels)
                pending.clear()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--monitor', default='')
    parser.add_argument('--stdin', action='store_true')
    args = parser.parse_args()
    child = None
    def stop(signum, frame):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, stop)
    try:
        if args.stdin:
            stream(sys.stdin.buffer)
        else:
            sink = args.monitor
            if not sink:
                sink = subprocess.check_output(['pactl', 'get-default-sink'], text=True, timeout=3).strip()
            if not sink or sink.startswith('-'):
                raise RuntimeError('No audio output available')
            child = subprocess.Popen(['parec', '--raw', '--format=s16le', f'--rate={RATE}', '--channels=1',
                '--latency-msec=45', '--client-name=MacShell Media', '--stream-name=Output visualizer',
                f'--device={sink}.monitor'], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            stream(child.stdout)
            raise RuntimeError("Audio output monitor disconnected")
    except (KeyboardInterrupt, BrokenPipeError):
        pass
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        emit(error=str(error), bands=[0] * BANDS)
        return 1
    finally:
        if child is not None:
            child.terminate()
            try:
                child.wait(timeout=1)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
