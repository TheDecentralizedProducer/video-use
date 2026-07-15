#!/usr/bin/env bash
# voiceover.sh — lay a talking track over a video, no background removal needed.
#
# The video plays as-is; your voice replaces or mixes with its audio.
#
# Usage:
#   ./scripts/voiceover.sh <background.mp4> <voice.mp4|voice.mp3> [project-slug]
#
# Options:
#   --audio replace  Drop background audio entirely, use only voice (default)
#   --audio mix      Mix voice + background audio (background ducked to 20%)
#   --bg-vol 0.2     Background audio volume when mixing (0.0–1.0, default 0.2)
#
# Examples:
#   ./scripts/voiceover.sh projects/2026-07-14-clip/raw/broll.mp4 raw/take.mp4
#   ./scripts/voiceover.sh broll.mp4 take.mp4 --audio mix --bg-vol 0.1

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

BG="${1:-}"
VOICE="${2:-}"
AUDIO_MODE="replace"
BG_VOL="0.2"
SLUG=""

shift 2 2>/dev/null || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --audio) AUDIO_MODE="$2"; shift 2 ;;
    --audio=*) AUDIO_MODE="${1#--audio=}"; shift ;;
    --bg-vol) BG_VOL="$2"; shift 2 ;;
    --bg-vol=*) BG_VOL="${1#--bg-vol=}"; shift ;;
    *) SLUG="$1"; shift ;;
  esac
done

if [ -z "$BG" ] || [ -z "$VOICE" ]; then
  echo "Usage: $0 <background.mp4> <voice.mp4|mp3> [--audio replace|mix] [--bg-vol 0.2] [slug]"
  exit 1
fi

# Resolve slug
if [ -z "$SLUG" ]; then
  SLUG=$(echo "$BG" | sed -n 's|.*projects/\([^/]*\)/.*|\1|p')
  [ -z "$SLUG" ] && SLUG="$(date +%Y-%m-%d)-voiceover"
fi

PROJECT="$REPO_ROOT/projects/$SLUG"
mkdir -p "$PROJECT/renders"

BG_ABS="$(cd "$(dirname "$BG")" && pwd)/$(basename "$BG")"
VOICE_ABS="$(cd "$(dirname "$VOICE")" && pwd)/$(basename "$VOICE")"
OUTPUT="$PROJECT/renders/voiceover.mp4"

echo ""
echo "=== voiceover ==="
echo "  background: $BG_ABS"
echo "  voice:      $VOICE_ABS"
echo "  audio:      $AUDIO_MODE"
echo "  slug:       $SLUG"
echo ""

case "$AUDIO_MODE" in
  replace)
    echo "[1/1] Replacing background audio with voice track…"
    ffmpeg -y \
      -i "$BG_ABS" \
      -i "$VOICE_ABS" \
      -map 0:v -map 1:a \
      -c:v copy \
      -shortest \
      "$OUTPUT" 2>&1
    ;;
  mix)
    echo "[1/1] Mixing voice over background audio (bg at ${BG_VOL})…"
    ffmpeg -y \
      -i "$BG_ABS" \
      -i "$VOICE_ABS" \
      -filter_complex \
        "[0:a]volume=${BG_VOL}[bg_a];
         [bg_a][1:a]amix=inputs=2:duration=shortest[a]" \
      -map 0:v -map "[a]" \
      -c:v copy \
      -shortest \
      "$OUTPUT" 2>&1
    ;;
  *)
    echo "ERROR: --audio must be 'replace' or 'mix'"
    exit 1
    ;;
esac

echo ""
echo "Done. → $OUTPUT"
