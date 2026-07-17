---
name: video-studio
description: Personal AI video-editing conductor for Ian Grant. Orchestrates transcript-based cutting (video-use) and motion graphics (hyperframes) for 9:16 vertical content. Invoke when Ian drops footage into a project's raw/ and says "edit this" or anything about editing a video.
---

# video-studio

This is the conductor skill. Read CLAUDE.md in the repo root for house rules before doing anything.

## Roles

- **video-use** (`tools/video-use/`) handles: transcription, filler/silence/retake detection, EDL generation, ffmpeg cuts.
- **hyperframes** (`tools/hyperframes/`) handles: HTML → MP4 motion graphics, overlays, lower-thirds, kinetic titles.

Never blur the boundary: don't write raw ffmpeg cut commands when video-use helpers exist; don't reach for hyperframes for plain subtitles.

## Trigger phrases

Any of these puts you into the conductor loop:
- "edit this", "edit these", "cut this"
- "transcribe and cut", "clean up this video"
- "make a launch video", "build a social clip"
- A video file dropped in a `raw/` folder with no further instruction

---

## Conductor loop (run every session in order — no skipping steps)

### Step 0: Project bootstrap

If no project folder exists for this footage, create one:

```
projects/YYYY-MM-DD-slug/
  raw/          ← source footage lives here
  edit/         ← transcripts, EDL, cut video
  compositions/ ← hyperframes HTML
  renders/      ← final MP4s
```

Infer the date from today. Infer the slug from the filename or Ian's description.
Move or copy source files to `raw/` if they aren't already there.

### Step 1: Transcribe

```bash
# Load API key
export ELEVENLABS_API_KEY=$(grep '^ELEVENLABS_API_KEY=' tools/video-use/.env | cut -d= -f2-)

# Transcribe — outputs JSON to edit/
uv run python tools/video-use/helpers/transcribe.py \
  projects/<slug>/raw/<file>.mp4 \
  --output projects/<slug>/edit/<file>.transcript.json
```

If `ELEVENLABS_API_KEY` is missing, stop and say:
> "Transcription needs your ElevenLabs key. Either export it in your shell or add it to tools/video-use/.env — then retry."

Do not proceed without a transcript. Never guess timecodes.

### Step 2: Analyze and propose cuts (plain English, no rendering)

Read the transcript JSON. Identify:
- **Fillers:** "um", "uh", "like", "you know", repeated false starts
- **Silence gaps:** > 0.8 s of no speech (unless dramatic pause)
- **Retakes:** speaker says essentially the same sentence twice in a row

Present the proposed cut list like this — no timecode jargon, no EDL syntax:

```
Here's what I'd cut:

1. Remove 0:03–0:07 — filler ("um, so, like") before the main point.
2. Remove 0:22–0:28 — false start, speaker restates the same sentence immediately after.
3. Remove 1:14–1:19 — 5-second silence while speaker checks notes.
4. Remove 2:05–2:09 — duplicate retake of the previous sentence.

Estimated runtime after cuts: 2:41 → 2:22 (saves 19 seconds).
Shall I proceed?
```

**STOP HERE.** Do not render anything. Wait for Ian to say "go", "ok", "do it", or similar.

If Ian asks to adjust the proposal, revise and show the updated list. Wait again.

### Step 3: Execute the cut (after approval only)

```bash
# Generate the cut via render helper
uv run python tools/video-use/helpers/render.py \
  projects/<slug>/raw/<file>.mp4 \
  projects/<slug>/edit/<file>.transcript.json \
  --cuts "0:03-0:07,0:22-0:28,1:14-1:19,2:05-2:09" \
  --output projects/<slug>/edit/<file>.cut.mp4

# If render.py doesn't accept --cuts directly, write an EDL file first:
# projects/<slug>/edit/cut.edl
# then pass --edl cut.edl
```

The output always goes to `edit/`, never back into `raw/`.
Never downscale. Pass source resolution through; if ffmpeg needs explicit size, use `-vf scale=trunc(iw/2)*2:trunc(ih/2)*2` to fix odd dimensions only.

### Step 3b: Load pillar edit style (if brief has a `style` field)

When a project brief or approved script JSON contains a `"style"` field, load the matching edit template from the DPC command center before proposing cuts.

**Important:** The style guides describe the reference creator's exact setup. Ian records differently. Apply the **structural principle and cadence**, not the literal setup. The tools to build each mode are already in this repo — see the "Adapted for Ian" section at the bottom of each style guide file.

| `style` value | Edit template file | Key rules |
|--------------|-------------------|-----------|
| `atlas-berry` | `~/dpc-command-center/styles/atlas-berry.md` | 6 visual modes cycling at ~3.7s avg. Mode 1 (clean talking head) = section break. Mode 2 (talking head + floating card) = when naming a source/article. Mode 4 (PiP + B-roll) = analytical core, B-roll matches words literally. Mode 5 (PiP + article screenshot) = citing a specific source. Mode 6 (PiP + custom diagram) = mechanism explanation. Kinetic subtitles always on; stacked text for lists. Topic tag pill at top during all PiP modes. Card/tweet bars persist 2–4 sentences. |
| `lex-nova` | `~/dpc-command-center/styles/lex-nova.md` | Left-side evidence panel (~40% of frame) updates as story progresses. She holds right ~60%. Every named entity gets a panel card: headshot · poster · year label · cast photo · article headline · document icon · org logo. Panel swaps when story pivots to new film/org. Panel CLEARS when lesson section begins. Kinetic subtitles: green=names, purple=industry terms. CTA = brand logo top-right on empty panel. |
| `kristen-pepper` | `~/dpc-command-center/styles/kristen-pepper.md` | 4 states: (1) Dual poster open with pre-roll topic card → (2) Poster zoom full-bleed 2–3s transition → (3) Split screen: clip top 40% / her bottom 60%, clips hold 15–30s each → (4) Clean full face for conclusion. Zero text overlays added in post. Each clip runs continuously while she talks over it — do not cut rapidly. |

Apply the matching template when building the EDL and proposing motion graphics in Step 4. If no `style` field is present, proceed with default editorial judgment.

### Step 4: Suggest motion graphics (2–3 spots)

After the cut is done, scan the transcript for strong candidates:

- A stat or number that could be a count-up overlay
- A key quote worth a pull-quote card
- A topic change that wants a kinetic title card
- A moment that would benefit from a lower-third name/title

Present as brief suggestions:

```
I see 3 spots that could use a graphic:

A) 0:08 — "We closed $2M in 90 days" → stat count-up overlay (5s)
B) 0:47 — Topic shift to product demo → kinetic title card "The Product"
C) 1:33 — First time Ian's on screen → lower-third: Ian Grant / CEO, Greenlit

Want me to build any of these in hyperframes?
```

Wait for Ian to pick which ones (if any). He can say "all", "just A and C", or "skip".

### Step 5: Build hyperframes compositions (if approved)

For each approved graphic, create an HTML composition in `compositions/`:

```bash
# Each composition is a self-contained HTML file
# Path: projects/<slug>/compositions/<name>.html
```

Follow hyperframes CLAUDE.md for timing attributes and composition contracts.
Use `data-duration`, `data-t`, `class="clip"` per the hyperframes spec.

After building, render a preview clip:
```bash
cd tools/hyperframes
bunx hyperframes render \
  ../../projects/<slug>/compositions/<name>.html \
  --output ../../projects/<slug>/edit/<name>.preview.mp4 \
  --width 1080 --height 1920
```

Show the preview path. Ask Ian to confirm before compositing.

### Step 6: Composite and final render (after confirmation)

Composite approved graphics onto the cut:

```bash
ffmpeg -i projects/<slug>/edit/<file>.cut.mp4 \
       -i projects/<slug>/edit/<name>.preview.mp4 \
       -filter_complex "[0:v][1:v]overlay=0:0:enable='between(t,START,END)'" \
       -c:v libx264 -preset slow -crf 18 \
       projects/<slug>/renders/<file>.composited.mp4
```

Subtitles (if requested) always burn in last:

```bash
ffmpeg -i projects/<slug>/renders/<file>.composited.mp4 \
       -vf "subtitles=projects/<slug>/edit/subtitles.srt:force_style='FontSize=18,Alignment=2'" \
       -c:v libx264 -preset slow -crf 18 \
       projects/<slug>/renders/<file>.final.mp4
```

Final output: `projects/<slug>/renders/<file>.final.mp4`.

---

## Delegation cheat sheet

| Task | Delegate to |
|------|------------|
| Transcription | `tools/video-use/helpers/transcribe.py` |
| Filler / silence detection | `tools/video-use/helpers/transcribe.py` output → read tags |
| Timeline visualization | `tools/video-use/helpers/timeline_view.py` |
| Cut execution | `tools/video-use/helpers/render.py` |
| HTML motion graphic | hyperframes (`tools/hyperframes/`) |
| Subtitle burn-in | ffmpeg, always last in filter chain |
| Source download from URL | `yt-dlp` (install if needed: `brew install yt-dlp`) |

## Hard rules (from CLAUDE.md)

- Never render before Ian approves the proposed cut list.
- Never downscale source footage.
- Subtitles always burn in last.
- Every project output lives under `projects/<slug>/` — never in `tools/` or `raw/`.
- If `ELEVENLABS_API_KEY` is missing, stop and say so — do not proceed.
