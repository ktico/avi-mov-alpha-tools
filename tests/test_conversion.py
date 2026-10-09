"""Integration checks, run with system FFmpeg on native Windows and macOS."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
WINDOWS = sys.platform == 'win32'

def call(args, expected=0):
    result = subprocess.run([str(a) for a in args], capture_output=True)
    if result.returncode != expected:
        raise AssertionError(f'Exit {result.returncode}, expected {expected}: {args}\n' + result.stdout.decode('utf-8', 'replace') + result.stderr.decode('utf-8', 'replace'))
    return result

def encode(*args):
    return call(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-nostdin', '-y', *args])

def avi(path, output=None, allow=False, expected=0):
    if WINDOWS:
        args = ['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ROOT / 'windows/AVI_MOV変換/Convert-Avi.ps1', '-NoGui', '-InputPath', path]
        if output: args += ['-OutputPath', output]
        if allow: args += ['-AllowNoAlpha']
    else:
        args = ['/bin/bash', ROOT / 'mac/avi-to-mov.command', path]
        if output: args += ['--output', output]
        if allow: args += ['--allow-no-alpha']
    return call(args, expected)

def split(path, expected=0):
    if WINDOWS:
        args = ['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ROOT / 'windows/MOV_Alpha_RGB変換/Split-Mov.ps1', '-NoGui', '-InputPath', path]
    else:
        args = ['/bin/bash', ROOT / 'mac/mov-to-alpha-rgb.command', path]
    return call(args, expected)

def probe(path):
    return json.loads(call(['ffprobe', '-v', 'error', '-count_frames', '-show_entries', 'stream=codec_name,codec_type,pix_fmt,width,height,nb_read_frames:format=duration', '-of', 'json', '-i', path]).stdout)

def pixels(path, alpha=False):
    filters = 'alphaextract,format=gray' if alpha else 'format=gray'
    return call(['ffmpeg', '-v', 'error', '-i', path, '-frames:v', '1', '-vf', filters, '-f', 'rawvideo', '-']).stdout

def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()

if not WINDOWS:
    for script in (ROOT / 'mac').rglob('*.command'): call(['/bin/bash', '-n', script])
    call(['/bin/bash', '-n', ROOT / 'mac/lib/convert-common.sh'])
    if sys.platform == 'darwin':
        with tempfile.TemporaryDirectory() as directory:
            for script in (ROOT / 'mac/lib').glob('*.applescript'):
                call(['osacompile', '-o', Path(directory) / (script.stem + '.scpt'), script])

with tempfile.TemporaryDirectory(prefix='alpha tools ', dir=ROOT) as directory:
    work = Path(directory)
    assert work.resolve().parent == ROOT.resolve(), 'Test cleanup must stay inside the checkout'
    source = work / "透過 test's.avi"
    encode('-f', 'lavfi', '-i', 'color=red:s=64x48:d=2:r=10,format=rgba,geq=r=255:g=0:b=0:a=255*X/(W-1),format=bgra', '-f', 'lavfi', '-i', 'sine=frequency=440:duration=2', '-c:v', 'rawvideo', '-c:a', 'pcm_s16le', '-shortest', source)
    original_hash = digest(source)
    mov = source.with_suffix('.mov')
    result = avi(source, mov)
    assert b'99 %' in result.stdout, 'Progress percentages are missing'
    assert probe(mov)['streams'][0]['pix_fmt'].startswith('yuva')
    # Existing explicit output must not change.
    mov_hash = digest(mov)
    avi(source, mov, expected=1)
    assert digest(mov) == mov_hash
    # Default output collision must choose a new name.
    avi(source)
    assert (work / (source.stem + '_変換1.mov')).exists()
    split(mov)
    alpha = work / (mov.stem + '_Alpha.mp4')
    rgb = work / (mov.stem + '_RGB.mp4')
    expected_mask, actual_mask = pixels(mov, True), pixels(alpha)
    assert len(expected_mask) == len(actual_mask) == 64 * 48
    assert max(abs(a - b) for a, b in zip(expected_mask, actual_mask)) <= 1
    assert actual_mask[0] <= 1 and actual_mask[63] >= 254
    for path in (alpha, rgb):
        info = probe(path)
        video = next(s for s in info['streams'] if s['codec_type'] == 'video')
        assert video['codec_name'] == 'h264'
        assert video['nb_read_frames'] == '20'
        assert abs(float(info['format']['duration']) - 2) < .05
    assert all(s['codec_type'] != 'audio' for s in probe(alpha)['streams'])
    assert any(s['codec_type'] == 'audio' for s in probe(rgb)['streams'])
    # RGB must preserve color even at a completely transparent input pixel.
    rgb_frame = call(['ffmpeg', '-v', 'error', '-i', rgb, '-frames:v', '1', '-pix_fmt', 'rgb24', '-f', 'rawvideo', '-']).stdout
    assert rgb_frame[0] > 240 and rgb_frame[1] < 10 and rgb_frame[2] < 10
    pair_hashes = digest(alpha), digest(rgb)
    split(mov, expected=1)
    assert pair_hashes == (digest(alpha), digest(rgb))
    opaque = work / 'opaque.avi'
    encode('-f', 'lavfi', '-i', 'color=blue:s=32x32:d=1', '-c:v', 'rawvideo', opaque)
    opaque_hash = digest(opaque)
    avi(opaque, expected=1)
    assert not opaque.with_suffix('.mov').exists()
    avi(opaque, allow=True)
    noalpha_mov = work / 'no-alpha.mov'
    encode('-i', opaque, '-c:v', 'libx264', noalpha_mov)
    split(noalpha_mov, expected=1)
    assert not (work / 'no-alpha_Alpha.mp4').exists()
    # An odd-sized alpha MOV must produce the same padded size in both outputs.
    odd = work / 'odd.mov'
    encode('-f', 'lavfi', '-i', 'color=red:s=64x48:d=1,format=rgba,pad=65:49:color=black@0', '-c:v', 'qtrle', odd)
    split(odd)
    for suffix in ('Alpha', 'RGB'):
        video = next(s for s in probe(work / f'odd_{suffix}.mp4')['streams'] if s['codec_type'] == 'video')
        assert (video['width'], video['height']) == (66, 50)
    assert digest(source) == original_hash and digest(opaque) == opaque_hash
    assert not list(work.glob('.alpha-tools.*'))
    assert not list(work.glob('.mov-split-*'))
    print('PASS: conversion, alpha pixels, matching frames/duration, audio, odd sizes, warning branches, existing-output safety, Unicode paths and progress.')
