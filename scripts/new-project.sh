#!/usr/bin/env bash
# new-project.sh — scaffold the canonical folder structure for a new project.
#
# Usage:
#   ./scripts/new-project.sh <slug>
#   ./scripts/new-project.sh 2026-07-14-greenlit-launch
#
# The date prefix is added automatically if you omit it:
#   ./scripts/new-project.sh greenlit-launch
#   → projects/2026-07-14-greenlit-launch/

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

SLUG="${1:-}"
if [ -z "$SLUG" ]; then
  echo "Usage: $0 <slug>"
  echo "  e.g. $0 greenlit-launch"
  exit 1
fi

# Prepend date if slug doesn't already start with YYYY-MM-DD
if ! echo "$SLUG" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}'; then
  SLUG="$(date +%Y-%m-%d)-${SLUG}"
fi

PROJECT="$REPO_ROOT/projects/$SLUG"

if [ -d "$PROJECT" ]; then
  echo "Project already exists: $PROJECT"
  exit 0
fi

mkdir -p \
  "$PROJECT/raw" \
  "$PROJECT/raw-test" \
  "$PROJECT/edit/verify/captions" \
  "$PROJECT/edit/verify/grade" \
  "$PROJECT/edit/verify/frames" \
  "$PROJECT/edit/verify/hook" \
  "$PROJECT/edit/verify/article" \
  "$PROJECT/edit/verify/overlays" \
  "$PROJECT/edit/verify/alpha" \
  "$PROJECT/edit/verify/subject" \
  "$PROJECT/edit/verify/scripts" \
  "$PROJECT/compositions" \
  "$PROJECT/renders"

# .gitkeep files so the tracked folder structure lands in git
# (PNGs are gitignored; empty dirs need a placeholder)
touch \
  "$PROJECT/edit/verify/captions/.gitkeep" \
  "$PROJECT/edit/verify/grade/.gitkeep" \
  "$PROJECT/edit/verify/frames/.gitkeep" \
  "$PROJECT/edit/verify/hook/.gitkeep" \
  "$PROJECT/edit/verify/article/.gitkeep" \
  "$PROJECT/edit/verify/overlays/.gitkeep" \
  "$PROJECT/edit/verify/alpha/.gitkeep" \
  "$PROJECT/edit/verify/subject/.gitkeep" \
  "$PROJECT/compositions/.gitkeep" \
  "$PROJECT/renders/.gitkeep"

echo "Created: $PROJECT"
echo ""
echo "Drop footage into:  $PROJECT/raw/"
echo "Then run:           claude"
echo "And say:            edit this"
