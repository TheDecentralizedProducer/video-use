#!/usr/bin/env bash
# video-bg-composite.sh — remove background from a talking head, composite over a video.
#
# Usage:
#   ./scripts/video-bg-composite.sh <subject.mp4> <background.mp4> [project-slug]
#
# Options:
#   --audio both     Mix subject + background audio (default)
#   --audio subject  Keep only subject audio (drop background sound)
#   --audio bg       Keep only background audio (drop subject voice — for pure overlay)
#
# Example:
#   ./scripts/video-bg-composite.sh \
#     projects/2026-07-14-clip/raw/take.mp4 \
#     projects/2026-07-14-clip/raw/broll.mp4

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HF="$REPO_ROOT/tools/hyperframes"

SUBJECT="${1:-}"
BACKGROUND="${2:-}"
AUDIO_MODE="both"
SLUG=""

shift 2 2>/dev/null || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --audio) AUDIO_MODE="$2"; shift 2 ;;
    --audio=*) AUDIO_MODE="${1#--audio=}"; shift ;;
    *) SLUG="$1"; shift ;;
  esac
done

if [ -z "$SUBJECT" ] || [ -z "$BACKGROUND" ]; then
  echo "Usage: $0 <subject.mp4> <background.mp4> [--audio both|subject|bg] [slug]"
  exit 1
fi

if [[ "$AUDIO_MODE" != "both" && "$AUDIO_MODE" != "subject" && "$AUDIO_MODE" != "bg" ]]; then
  echo "ERROR: --audio must be 'both', 'subject', or 'bg'"
  exit 1
fi

# Resolve slug
if [ -z "$SLUG" ]; then
  SLUG=$(echo "$SUBJECT" | sed -n 's|.*projects/\([^/]*\)/.*|\1|p')
  [ -z "$SLUG" ] && SLUG="$(date +%Y-%m-%d)-video-composite"
fi

PROJECT="$REPO_ROOT/projects/$SLUG"
mkdir -p "$PROJECT/edit" "$PROJECT/renders"

SUBJECT_ABS="$(cd "$(dirname "$SUBJECT")" && pwd)/$(basename "$SUBJECT")"
BG_ABS="$(cd "$(dirname "$BACKGROUND")" && pwd)/$(basename "$BACKGROUND")"
BASENAME="$(basename "$SUBJECT" | sed 's/\.[^.]*$//')"
TRANSPARENT="$PROJECT/edit/${BASENAME}.transparent.webm"
OUTPUT="$PROJECT/renders/video-bg-composite.mp4"

echo ""
echo "=== video-bg-composite ==="
echo "  subject:    $SUBJECT_ABS"
echo "  background: $BG_ABS"
echo "  audio:      $AUDIO_MODE"
echo "  slug:       $SLUG"
echo ""

# ── Step 1: Remove background ─────────────────────────────────────────────────
if [ -f "$TRANSPARENT" ]; then
  echo "[1/2] Transparent video exists, skipping removal."
  echo "      Delete $TRANSPARENT to force re-run."
else
  echo "[1/2] Removing background…"
  echo "      (first run downloads ~168 MB u2net model)"
  (cd "$HF" && node packages/cli/dist/cli.js remove-background "$SUBJECT_ABS" \
    --output "$TRANSPARENT" 2>&1) || \
  (cd "$HF" && npx hyperframes remove-background "$SUBJECT_ABS" \
    --output "$TRANSPARENT" 2>&1)
  echo "      → $TRANSPARENT"
fi

# ── Step 2: Composite over video ─────────────────────────────────────────────
echo ""
echo "[2/2] Compositing over video background…"

case "$AUDIO_MODE" in
  subject)
    # Only subject audio
    ffmpeg -y \
      -i "$BG_ABS" \
      -i "$TRANSPARENT" \
      -filter_complex \
        "[0:v]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920[bg];
         [bg][1:v]overlay=0:0[out]" \
      -map "[out]" -map "1:a?" \
      -c:v libx264 -preset slow -crf 18 \
      -shortest \
      "$OUTPUT" 2>&1
    ;;
  bg)
    # Only background audio
    ffmpeg -y \
      -i "$BG_ABS" \
      -i "$TRANSPARENT" \
      -filter_complex \
        "[0:v]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920[bg];
         [bg][1:v]overlay=0:0[out]" \
      -map "[out]" -map "0:a?" \
      -c:v libx264 -preset slow -crf 18 \
      -shortest \
      "$OUTPUT" 2>&1
    ;;
  both)
    # Mix both — background audio ducked to 30%
    ffmpeg -y \
      -i "$BG_ABS" \
      -i "$TRANSPARENT" \
      -filter_complex \
        "[0:v]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920[bg];
         [bg][1:v]overlay=0:0[out];
         [0:a]volume=0.3[bg_a];
         [bg_a][1:a]amix=inputs=2:duration=shortest[a]" \
      -map "[out]" -map "[a]" \
      -c:v libx264 -preset slow -crf 18 \
      -shortest \
      "$OUTPUT" 2>&1
    ;;
esac

echo ""
echo "Done. → $OUTPUT"
echo ""
echo "To adjust audio levels, re-run with --audio subject|bg|both"
echo "To re-composite without re-removing bg, delete renders/ output and re-run step 2 manually:"
echo "  (the transparent webm is cached at $TRANSPARENT)"
