#!/usr/bin/env python3
"""Verify loop seam energy for a video.

Reads a small grayscale stream via ffmpeg and compares seam frame differences
against ordinary adjacent-frame differences. A loop passes when every detected
seam is no larger than the mean non-seam adjacent-frame difference.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path


def run(cmd: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, check=True, capture_output=True)


def read_frames(path: Path, width: int, height: int) -> list[bytes]:
    cmd = [
        "ffmpeg",
        "-v",
        "error",
        "-i",
        str(path),
        "-vsync",
        "0",
        "-vf",
        f"scale={width}:{height},format=gray",
        "-f",
        "rawvideo",
        "-",
    ]
    proc = run(cmd)
    frame_bytes = width * height
    data = proc.stdout
    if len(data) % frame_bytes != 0:
        raise RuntimeError(f"raw frame byte count {len(data)} is not divisible by {frame_bytes}")
    return [data[i : i + frame_bytes] for i in range(0, len(data), frame_bytes)]


def mad(a: bytes, b: bytes) -> float:
    total = 0
    for x, y in zip(a, b):
        total += abs(x - y)
    return total / max(1, len(a)) / 255.0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("video", type=Path)
    ap.add_argument("--loop-frames", type=int, required=True)
    ap.add_argument("--width", type=int, default=160)
    ap.add_argument("--height", type=int, default=200)
    ap.add_argument("--threshold", type=float, default=1.0)
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    frames = read_frames(args.video, args.width, args.height)
    if len(frames) < 3:
        raise RuntimeError("video produced fewer than 3 frames")
    if args.loop_frames <= 1 or args.loop_frames > len(frames):
        raise RuntimeError("--loop-frames must be in 2..frame_count")

    adjacent = [mad(frames[i], frames[i + 1]) for i in range(len(frames) - 1)]
    seam_indices = []
    k = args.loop_frames
    while k < len(frames):
        seam_indices.append(k - 1)
        k += args.loop_frames
    seam_indices.append(len(frames) - 1)  # final frame wraps to first

    seam_diffs = []
    for idx in seam_indices:
        a = frames[idx]
        b = frames[(idx + 1) % len(frames)]
        seam_diffs.append(mad(a, b))

    non_seam_adjacent = [d for i, d in enumerate(adjacent) if i not in set(seam_indices)]
    mean_adjacent = sum(non_seam_adjacent) / max(1, len(non_seam_adjacent))
    max_seam = max(seam_diffs)
    passed = max_seam <= mean_adjacent * args.threshold

    result = {
        "video": str(args.video),
        "frame_count": len(frames),
        "loop_frames": args.loop_frames,
        "mean_adjacent_diff": mean_adjacent,
        "max_seam_diff": max_seam,
        "seam_diffs": seam_diffs,
        "threshold": args.threshold,
        "pass": passed,
    }
    if args.json:
        print(json.dumps(result, indent=2))
    else:
        print(
            f"frames={len(frames)} loop_frames={args.loop_frames} "
            f"mean_adjacent={mean_adjacent:.6f} max_seam={max_seam:.6f} pass={passed}"
        )
    return 0 if passed else 2


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except subprocess.CalledProcessError as exc:
        sys.stderr.write(exc.stderr.decode("utf-8", errors="replace"))
        raise SystemExit(exc.returncode)
