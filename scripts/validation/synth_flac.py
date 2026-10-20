#!/usr/bin/env python3
"""Wrap a 16-bit PCM WAV file of synthetic audio in a minimal FLAC file with Vorbis comments.

The output uses verbatim subframes and a single frame, so it is large but trivially correct. It exists only
so that the M11 qualification bundle can carry original synthetic tags through `ilibrary import`, which
reads tags from FLAC files and from no other source. Nothing here addresses Music.

Usage: synth_flac.py IN.wav OUT.flac KEY=VALUE...
"""

import hashlib
import struct
import sys
import wave
from pathlib import Path


def crc8(data):
    crc = 0
    for byte in data:
        crc ^= byte
        for _ in range(8):
            crc = ((crc << 1) ^ 0x07) & 0xFF if crc & 0x80 else (crc << 1) & 0xFF
    return crc


def crc16(data):
    crc = 0
    for byte in data:
        crc ^= byte << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x8005) & 0xFFFF if crc & 0x8000 else (crc << 1) & 0xFFFF
    return crc


def vorbis_comment(tags):
    vendor = b"ilibrary synthetic fixture"
    block = struct.pack("<I", len(vendor)) + vendor + struct.pack("<I", len(tags))
    for tag in tags:
        encoded = tag.encode("utf-8")
        block += struct.pack("<I", len(encoded)) + encoded
    return block


def metadata_block(kind, payload, last):
    return bytes([(0x80 if last else 0) | kind]) + len(payload).to_bytes(3, "big") + payload


def encode(wav_path, tags):
    with wave.open(str(wav_path), "rb") as source:
        channels, width, rate, frames = (
            source.getnchannels(), source.getsampwidth(), source.getframerate(), source.getnframes())
        pcm = source.readframes(frames)
    if (channels, width, rate) != (2, 2, 44100) or not 0 < frames <= 65536:
        raise SystemExit("synth_flac: only 16-bit stereo 44100 Hz audio of at most 65536 frames is supported")
    samples = struct.unpack("<%dh" % (frames * channels), pcm)
    streaminfo = struct.pack(">HH", frames, frames) + (0).to_bytes(3, "big") * 2
    streaminfo += ((rate << 44) | ((channels - 1) << 41) | ((16 - 1) << 36) | frames).to_bytes(8, "big")
    streaminfo += hashlib.md5(pcm).digest()
    header = bytes([0xFF, 0xF8, 0x79, 0x18, 0x00]) + struct.pack(">H", frames - 1)
    header += bytes([crc8(header)])
    body = b""
    for channel in range(channels):
        body += b"\x02" + b"".join(struct.pack(">h", samples[index * channels + channel]) for index in range(frames))
    frame = header + body
    frame += struct.pack(">H", crc16(frame))
    return (b"fLaC" + metadata_block(0, streaminfo, False) + metadata_block(4, vorbis_comment(tags), True) + frame)


def main(arguments):
    if len(arguments) < 2 or any("=" not in tag for tag in arguments[2:]):
        raise SystemExit("usage: synth_flac.py IN.wav OUT.flac KEY=VALUE...")
    output = Path(arguments[1])
    data = encode(Path(arguments[0]), arguments[2:])
    with open(output, "xb") as handle:
        handle.write(data)


if __name__ == "__main__":
    main(sys.argv[1:])
