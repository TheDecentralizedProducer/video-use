#!/usr/bin/env python3
"""
pip-composite.py — Extract Ian from a video segment, composite him over an
article or image background, and produce a ready-to-splice MP4 clip.

Usage:
  uv run python scripts/pip-composite.py \
    --base   projects/<slug>/renders/base_cut.mp4 \
    --start  5.0 \
    --end    9.0 \
    --bg     projects/<slug>/edit/verify/article_hl_m1.png \
    --out    projects/<slug>/edit/pip_m1.mp4

Then splice into the final with -itsoffset (NOT overlay+enable):

  ffmpeg -y \
    -i base_cut.mp4 \
    -itsoffset 5.0 -i pip_m1.mp4 \
    -itsoffset 14.0 -i pip_m2.mp4 \
    -filter_complex "
      [0:v]trim=0:5.0,setpts=PTS-STARTPTS[s0];
      [0:v]trim=9.0:14.0,setpts=PTS-STARTPTS[s2];
      [0:v]trim=20.2,setpts=PTS-STARTPTS[s4];
      [s0][1:v][s2][2:v][s4]concat=n=5:v=1:a=0[vout]
    " \
    -map "[vout]" -map "0:a" \
    -c:v libx264 -crf 18 -preset slow -pix_fmt yuv420p \
    -c:a aac -b:a 192k \
    output.mp4

Rules:
  - ALWAYS extract frames from the base cut video (no overlays, no subtitles).
    Never use final.mp4, preview.mp4, or any file with overlays/subs baked in.
  - ALWAYS use rembg birefnet-general model (not default u2net — bad on white walls).
  - NEVER use overlay=enable= for segment replacement. Use trim+concat.
  - Ian: 640px wide, horizontally centered, 60px from bottom.
  - Audio: always map from original base video (0:a), not from pip clips.
"""

import argparse, io, shutil, subprocess, sys, pathlib, tempfile
import numpy as np
from PIL import Image
from rembg import remove, new_session

FFMPEG = (
    "/opt/homebrew/opt/ffmpeg-full/bin/ffmpeg"
    if shutil.which("/opt/homebrew/opt/ffmpeg-full/bin/ffmpeg")
    else "ffmpeg"
)

CANVAS_W, CANVAS_H = 1080, 1920
IAN_W = 640  # Ian width — centered horizontally


def extract_frames(video: str, start: float, end: float, frames_dir: pathlib.Path, fps: int = 30):
    duration = end - start
    frames_dir.mkdir(parents=True, exist_ok=True)
    subprocess.run([
        FFMPEG, "-y",
        "-ss", str(start), "-t", str(duration),
        "-i", video,
        "-vf", f"fps={fps}",
        str(frames_dir / "frame%04d.png"),
    ], check=True, capture_output=True)
    return sorted(frames_dir.glob("frame*.png"))


def remove_bg(frame_path: pathlib.Path, session) -> Image.Image:
    raw = frame_path.read_bytes()
    result = remove(raw, session=session)
    return Image.open(io.BytesIO(result)).convert("RGBA")


def crop_to_subject(img: Image.Image) -> Image.Image:
    arr = np.array(img)
    alpha = arr[:, :, 3]
    rows = np.any(alpha > 10, axis=1)
    cols = np.any(alpha > 10, axis=0)
    if not rows.any():
        return img
    rmin, rmax = np.where(rows)[0][[0, -1]]
    cmin, cmax = np.where(cols)[0][[0, -1]]
    return img.crop((cmin, rmin, cmax, rmax))


def composite_frame(cutout: Image.Image, background: Image.Image) -> Image.Image:
    canvas = background.copy().convert("RGBA")
    new_h = int(cutout.height * (IAN_W / cutout.width))
    subject = cutout.resize((IAN_W, new_h), Image.LANCZOS)
    x = (CANVAS_W - IAN_W) // 2
    y = CANVAS_H - new_h - 60
    canvas.paste(subject, (x, y), subject)
    return canvas.convert("RGB")


def encode_frames(frames_dir: pathlib.Path, out_path: pathlib.Path, fps: int = 30):
    subprocess.run([
        FFMPEG, "-y",
        "-framerate", str(fps),
        "-i", str(frames_dir / "frame%04d.png"),
        "-c:v", "libx264", "-crf", "18", "-preset", "slow", "-pix_fmt", "yuv420p",
        str(out_path),
    ], check=True, capture_output=True)


def main():
    p = argparse.ArgumentParser(description="PiP composite: cut Ian out, place over background")
    p.add_argument("--base",  required=True, help="Base cut video (NO overlays, NO subtitles)")
    p.add_argument("--start", required=True, type=float, help="Start time in seconds (output timeline)")
    p.add_argument("--end",   required=True, type=float, help="End time in seconds (output timeline)")
    p.add_argument("--bg",    required=True, help="Background image path (article screenshot etc)")
    p.add_argument("--out",   required=True, help="Output MP4 path for the composited clip")
    p.add_argument("--fps",   default=30, type=int)
    args = p.parse_args()

    out_path = pathlib.Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    print(f"[pip] loading birefnet-general model…")
    session = new_session("birefnet-general")

    background = Image.open(args.bg).convert("RGBA").resize((CANVAS_W, CANVAS_H), Image.LANCZOS)

    with tempfile.TemporaryDirectory() as tmp:
        frames_dir = pathlib.Path(tmp) / "raw"
        comp_dir   = pathlib.Path(tmp) / "comp"
        comp_dir.mkdir()

        print(f"[pip] extracting frames {args.start}–{args.end}s from {args.base}…")
        frames = extract_frames(args.base, args.start, args.end, frames_dir, args.fps)
        total = len(frames)
        print(f"[pip] {total} frames extracted")

        for i, fp in enumerate(frames):
            if i % 15 == 0:
                print(f"[pip] rembg {i}/{total}", flush=True)
            cutout  = remove_bg(fp, session)
            subject = crop_to_subject(cutout)
            comp    = composite_frame(subject, background)
            comp.save(comp_dir / fp.name)

        print(f"[pip] encoding → {out_path}…")
        encode_frames(comp_dir, out_path, args.fps)

    print(f"[pip] done: {out_path}  ({out_path.stat().st_size // 1024}KB)")
    print(f"\nSplice into final with:")
    print(f"  -itsoffset {args.start} -i {out_path}")


if __name__ == "__main__":
    main()
