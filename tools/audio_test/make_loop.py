#!/usr/bin/env python3
"""Concatenate a corpus WAV with itself N times.

Audio In's File mode plays a WAV once and then reports Inactive; there is no
loop parameter. A 20-second corpus file therefore freezes any downstream node
twenty seconds after it is wired, which is indistinguishable from a stalled
consumer until you read the status message.

The Data Scope station needs a signal that keeps arriving so the strip charts
stay live for review, so it plays a repeated build of a real corpus file rather
than the 20-second original. The repeat is honest material, not a synthesized
test signal: every sample is the corpus recording.

The output is generated, not committed. Regenerate with:

    python tools/audio_test/make_loop.py quiet_intro_drop_128 --repeats 9
"""

import argparse
import wave
from pathlib import Path

HERE = Path(__file__).resolve().parent
CORPUS = HERE / "corpus"
OUT_DIR = HERE / "loops"


def build(name: str, repeats: int) -> Path:
    src = CORPUS / f"{name}.wav"
    if not src.exists():
        raise SystemExit(f"no such corpus file: {src}")

    with wave.open(str(src), "rb") as w:
        params = w.getparams()
        frames = w.readframes(w.getnframes())

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    dst = OUT_DIR / f"{name}_x{repeats}.wav"
    with wave.open(str(dst), "wb") as w:
        w.setparams(params)
        for _ in range(repeats):
            w.writeframes(frames)

    seconds = params.nframes * repeats / params.framerate
    print(f"{dst}")
    print(f"  {params.nchannels}ch {params.framerate} Hz "
          f"{params.sampwidth * 8}-bit, {seconds:.1f} s, "
          f"{dst.stat().st_size / 1e6:.1f} MB")
    return dst


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("name", help="corpus file stem, e.g. quiet_intro_drop_128")
    ap.add_argument("--repeats", type=int, default=9)
    args = ap.parse_args()
    if args.repeats < 1:
        raise SystemExit("--repeats must be at least 1")
    build(args.name, args.repeats)


if __name__ == "__main__":
    main()
