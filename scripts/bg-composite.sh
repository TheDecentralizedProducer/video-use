#!/usr/bin/env bash
# bg-composite.sh — remove background from a video, screenshot a URL, composite them.
#
# Usage:
#   ./scripts/bg-composite.sh <video.mp4> <url-or-image.png> [project-slug]
#
# Examples:
#   ./scripts/bg-composite.sh projects/2026-07-14-clip/raw/take.mp4 https://example.com/article
#   ./scripts/bg-composite.sh raw/take.mp4 background.png my-project
#
# Output lands in projects/<slug>/renders/composite.mp4

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HF="$REPO_ROOT/tools/hyperframes"
HF_CLI="$HF/node_modules/.bin/hyperframes"

# ── Args ──────────────────────────────────────────────────────────────────────
VIDEO="${1:-}"
SOURCE="${2:-}"   # URL or local image path

if [ -z "$VIDEO" ] || [ -z "$SOURCE" ]; then
  echo "Usage: $0 <video.mp4> <url-or-image.png> [project-slug]"
  exit 1
fi

# Resolve project slug from arg or video path
if [ -n "${3:-}" ]; then
  SLUG="$3"
else
  # Infer from video path: projects/<slug>/raw/file.mp4 → slug
  SLUG=$(echo "$VIDEO" | sed -n 's|.*projects/\([^/]*\)/.*|\1|p')
  if [ -z "$SLUG" ]; then
    SLUG="$(date +%Y-%m-%d)-composite"
  fi
fi

PROJECT="$REPO_ROOT/projects/$SLUG"
mkdir -p "$PROJECT/edit" "$PROJECT/compositions" "$PROJECT/renders"

VIDEO_ABS="$(cd "$(dirname "$VIDEO")" && pwd)/$(basename "$VIDEO")"
BASENAME="$(basename "$VIDEO" | sed 's/\.[^.]*$//')"

echo ""
echo "=== bg-composite: $BASENAME ==="
echo "  project: $PROJECT"
echo ""

# ── Step 1: Background image ───────────────────────────────────────────────────
BG="$PROJECT/edit/background.png"

if [[ "$SOURCE" == http* ]]; then
  echo "[1/4] Screenshotting $SOURCE …"
  (cd "$HF" && node dist/cli.js screenshot "$SOURCE" \
    --output "$BG" \
    --width 1080 --height 1920 2>&1) || \
  (cd "$HF" && npx hyperframes screenshot "$SOURCE" \
    --output "$BG" \
    --width 1080 --height 1920 2>&1)
  echo "      → $BG"
else
  echo "[1/4] Using local image: $SOURCE"
  cp "$SOURCE" "$BG"
fi

# ── Step 2: Remove background ─────────────────────────────────────────────────
TRANSPARENT="$PROJECT/edit/${BASENAME}.transparent.webm"
echo ""
echo "[2/4] Removing background from video …"
echo "      (first run downloads ~168 MB u2net model)"
(cd "$HF" && node dist/cli.js remove-background "$VIDEO_ABS" \
  --output "$TRANSPARENT" 2>&1) || \
(cd "$HF" && npx hyperframes remove-background "$VIDEO_ABS" \
  --output "$TRANSPARENT" 2>&1)
echo "      → $TRANSPARENT"

# ── Step 3: Build HTML composition ────────────────────────────────────────────
COMP="$PROJECT/compositions/bg-composite.html"
echo ""
echo "[3/4] Writing composition …"

# Get video duration via ffprobe for data-duration
DURATION=$(ffprobe -v error -show_entries format=duration \
  -of default=noprint_wrappers=1:nokey=1 "$VIDEO_ABS" 2>/dev/null | cut -d. -f1)
DURATION="${DURATION:-30}"

# Relative paths from compositions/ to edit/
REL_BG="../edit/background.png"
REL_VID="../edit/${BASENAME}.transparent.webm"

cat > "$COMP" <<HTML
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { width: 1080px; height: 1920px; overflow: hidden; background: #000; }
  .frame { position: relative; width: 1080px; height: 1920px; }
  .bg {
    position: absolute; inset: 0;
    width: 100%; height: 100%;
    object-fit: cover;
    object-position: center top;
  }
  /* Slight darken so subject pops */
  .bg-overlay {
    position: absolute; inset: 0;
    background: rgba(0,0,0,0.35);
  }
  .subject {
    position: absolute;
    bottom: 0;
    left: 50%;
    transform: translateX(-50%);
    width: 100%;
    height: auto;
  }
</style>
</head>
<body>
<div class="clip frame" data-duration="${DURATION}">
  <img class="bg" src="${REL_BG}" />
  <div class="bg-overlay"></div>
  <video class="subject" src="${REL_VID}" autoplay muted playsinline></video>
</div>
</body>
</html>
HTML

echo "      → $COMP"

# ── Step 4: Render to MP4 ─────────────────────────────────────────────────────
OUTPUT="$PROJECT/renders/composite.mp4"
echo ""
echo "[4/4] Rendering to MP4 …"
(cd "$HF" && node dist/cli.js render "$COMP" \
  --output "$OUTPUT" \
  --width 1080 --height 1920 2>&1) || \
(cd "$HF" && npx hyperframes render "$COMP" \
  --output "$OUTPUT" \
  --width 1080 --height 1920 2>&1)

echo ""
echo "Done. → $OUTPUT"
echo ""
echo "To adjust subject position or size, edit:"
echo "  $COMP"
echo "Then re-run step 4:"
echo "  cd tools/hyperframes && npx hyperframes render $COMP --output $OUTPUT --width 1080 --height 1920"
