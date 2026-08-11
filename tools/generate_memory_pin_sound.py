#!/usr/bin/env python3
"""Generate the placeholder sound for retaining or releasing a touch memory point.

The script uses only the Python standard library and always writes the same
two 16-bit mono WAV files to assets/audio/sfx/:
    memory_pin.wav
    memory_unpin.wav (an exact frame reversal of memory_pin.wav)

Run from the repository root:
    python tools/generate_memory_pin_sound.py
"""

from __future__ import annotations

import math
import struct
import wave
from pathlib import Path


SAMPLE_RATE = 44_100
OUTPUT_DIR = Path(__file__).resolve().parents[1] / "assets" / "audio" / "sfx"
PIN_OUTPUT_PATH = OUTPUT_DIR / "memory_pin.wav"
UNPIN_OUTPUT_PATH = OUTPUT_DIR / "memory_unpin.wav"


def _envelope(time_seconds: float, duration: float) -> float:
	attack = min(1.0, time_seconds / 0.008)
	decay = math.exp(-time_seconds / 0.13)
	release_start = duration - 0.05
	release = 1.0 if time_seconds <= release_start else max(0.0, (duration - time_seconds) / 0.05)
	return attack * decay * release


def _sample(time_seconds: float, duration: float) -> float:
	# A short rising chirp followed by a stable confirmation tone.
	chirp_duration = 0.07
	if time_seconds < chirp_duration:
		progress = time_seconds / chirp_duration
		frequency = 620.0 + 260.0 * progress
	else:
		frequency = 880.0
	main_tone = math.sin(2.0 * math.pi * frequency * time_seconds)
	harmonic = math.sin(2.0 * math.pi * frequency * 2.0 * time_seconds) * 0.16
	return (main_tone + harmonic) * 0.55 * _envelope(time_seconds, duration)


def _write_wav(path: Path, samples: list[float]) -> None:
	frames = bytearray()
	for sample in samples:
		value = max(-1.0, min(1.0, sample))
		frames.extend(struct.pack("<h", round(value * 32_767)))
	with wave.open(str(path), "wb") as output:
		output.setnchannels(1)
		output.setsampwidth(2)
		output.setframerate(SAMPLE_RATE)
		output.writeframes(frames)


def main() -> None:
	duration = 0.22
	samples = [_sample(index / SAMPLE_RATE, duration) for index in range(int(SAMPLE_RATE * duration))]

	OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
	_write_wav(PIN_OUTPUT_PATH, samples)
	_write_wav(UNPIN_OUTPUT_PATH, list(reversed(samples)))
	print("Generated", PIN_OUTPUT_PATH.relative_to(Path.cwd()))
	print("Generated", UNPIN_OUTPUT_PATH.relative_to(Path.cwd()))


if __name__ == "__main__":
	main()
