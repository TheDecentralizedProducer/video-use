# Video Studio — House Rules

Personal AI video-editing studio for Ian Grant. All editing is orchestrated by
Claude Code using two vendored tools: **video-use** (transcript-based cutting)
and **hyperframes** (HTML → MP4 motion graphics).

## Tools

| Tool | Path | Role |
|------|------|------|
| video-use | `tools/video-use/` | Transcription, filler/silence/retake detection, EDL generation, ffmpeg cuts |
| hyperframes | `tools/hyperframes/` | HTML → MP4 motion graphics and overlays |

Run `./setup.sh` to clone and build both tools. They are gitignored — tracked
via setup.sh, not committed to this repo.

Run Python helpers via `uv run python tools/video-use/helpers/<name>.py`.
Run hyperframes via `bunx hyperframes` or `bun run` inside `tools/hyperframes/`.

## Output format

- **Aspect ratio:** 9:16 vertical (portrait).
- **Resolution:** PRESERVE the source resolution — never downscale. 1080×1920 is
  the minimum floor and is used only for fast preview passes. Native resolution
  is always used for final renders.
- **Codec:** H.264 (mp4) for drafts; H.265 or ProRes for finals if asked.
- **Frame rate:** match source; never retime unless explicitly asked.

## Editing workflow (strictly enforced)

1. **Transcribe first.** Always use video-use to transcribe before proposing
   any edit. Never cut on instinct or timing alone.
2. **Propose in plain English.** Present the proposed cut as a human-readable
   list of ranges to remove (e.g. "Remove 0:12–0:18: filler word 'um'; remove
   0:34–0:41: repeated retake"). No timecode jargon.
3. **Wait for approval.** Do NOT render anything until Ian says "go," "ok,"
   "do it," or an equivalent green light. One confirmation per session is
   enough unless the plan changes significantly.
4. **Execute the cut.** Apply the EDL via video-use render helpers + ffmpeg.
5. **Subtitles burn last.** If subtitles are requested, they are always the
   final step in the ffmpeg filter chain — applied after all cuts and overlays
   are in place. Short chunks (≤6 words per line).

## Motion graphics (hyperframes)

- Suggest 2–3 graphic opportunities after every approved cut (stat callouts,
  lower-thirds, kinetic titles, transitions).
- Build in `projects/<slug>/compositions/` as standalone HTML files.
- Always preview (screenshot or short clip) before asking to composite.
- Composite with ffmpeg overlay; subtitles still burn last.

## Project layout

Every project lives under `projects/`:

```
projects/
  YYYY-MM-DD-slug/
    raw/                        ← source footage (gitignored)
    raw-test/                   ← test clips (gitignored)
    edit/                       ← transcripts, EDL, cut video, fonts
      clips_preview/            ← low-res segment previews (gitignored)
      clips_graded/             ← graded segments (gitignored)
      pip_frames/               ← frame sequences for PiP work (gitignored)
      verify/                   ← visual QC screenshots (gitignored PNGs, scripts tracked)
        captions/               ← subtitle rendering, font, position checks
        grade/                  ← color grade comparisons
        frames/                 ← frame extractions from cuts/base videos
        hook/                   ← hook graphic overlay tests
        article/                ← article background and PiP tests
        overlays/               ← generic overlay mockups and composites
        alpha/                  ← transparency / alpha channel checks
        subject/                ← cutout and background-removal checks
        scripts/                ← .mjs helpers that generate verify assets (tracked)
    compositions/               ← hyperframes HTML + meta (tracked); renders gitignored
    renders/                    ← final MP4s (gitignored)
```

Create the folder structure when starting a new project. The `scripts/new-project.sh`
helper does this automatically (see Scripts table above). Never write output
files back into `raw/`.

**verify/ discipline:** every visual decision that required a check gets a PNG in the
right subfolder before moving on. Name files descriptively (`hook_over_source_v2.png`,
not `test3.png`). Scripts that generate verify assets live in `verify/scripts/` and are
tracked in git so they can be re-run.

## Environment

- `ELEVENLABS_API_KEY` must be set in `tools/video-use/.env` or the shell
  environment. Without it, transcription will fail.
- Run `./setup.sh` to verify or repair the full toolchain.

## Scripts

| Script | What it does |
|--------|-------------|
| `./scripts/new-project.sh <slug>` | Scaffold the full project folder structure (including all `verify/` subfolders) for a new clip. Date-prefixes the slug automatically. |
| `./scripts/video-bg-composite.sh <subject.mp4> <background.mp4> [--audio both\|subject\|bg]` | Remove background from subject, composite over a video background. Audio modes: `both` mixes tracks (bg ducked to 30%), `subject` keeps only voice, `bg` keeps only background sound. |
| `./scripts/voiceover.sh <background.mp4> <voice.mp4> [--audio replace\|mix] [--bg-vol 0.2]` | Lay a talking track over a video. `replace` drops background audio (default); `mix` blends both with bg ducked to `--bg-vol`. No background removal needed. |
| `./scripts/bg-composite.sh <video.mp4> <url-or-image>` | Remove background from video, screenshot a URL (or use a local image), composite subject over it, render 9:16 MP4. Output: `projects/<slug>/renders/composite.mp4`. |
| `./scripts/article-composite.sh <video.mp4> <url> "<phrase>" [--mode background\|overlay]` | Screenshot a news article with a yellow marker highlight on a specific phrase, then composite your video over it. `background` mode (default): article fills top of frame, you appear below. `overlay` mode: your footage plays full-frame, article slides in as a PiP panel. Output: `projects/<slug>/renders/article-composite.mp4`. |
| `./scripts/render.py` | Patched render helper — use this instead of `tools/video-use/helpers/render.py`. Uses `ffmpeg-full` for ProRes 4444 alpha support and `format=auto` overlay compositing. After `./setup.sh`, copy: `cp scripts/render.py tools/video-use/helpers/render.py` |
| `uv run python scripts/pip-composite.py --base <base_cut.mp4> --start <t> --end <t> --bg <image.png> --out <pip_clip.mp4>` | Cut Ian out of a video segment (birefnet-general model) and composite him over an article screenshot or any image background. Output is a ready-to-splice MP4. Splice into final with `-itsoffset` + trim/concat (never overlay+enable). See script header for full splice command. |

## What NOT to do

- Do not render before Ian approves the proposed cut.
- Do not downscale source footage.
- Do not add background music, color grading, or effects unless asked.
- Do not commit `.env`, raw footage, or final renders to git.
- Do not skip the transcript step even for "simple" cuts.
