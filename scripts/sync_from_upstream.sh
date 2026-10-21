#!/bin/bash
set -euo pipefail

UPSTREAM_REMOTE="${UPSTREAM_REMOTE:-upstream}"
UPSTREAM_URL="${UPSTREAM_URL:-https://github.com/throwaway31265/free-sleep.git}"
UPSTREAM_BRANCH="${UPSTREAM_BRANCH:-main}"
TARGET_BRANCH="${TARGET_BRANCH:-$(git --no-pager branch --show-current)}"

if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  echo "ERROR: This script must be run inside a git repository."
  exit 1
fi

if [ -z "$TARGET_BRANCH" ]; then
  echo "ERROR: Could not detect current branch. Set TARGET_BRANCH and retry."
  exit 1
fi

if [ -n "$(git --no-pager status --porcelain)" ]; then
  echo "ERROR: Working tree is not clean. Commit or stash your changes first."
  exit 1
fi

if git remote get-url "$UPSTREAM_REMOTE" > /dev/null 2>&1; then
  EXISTING_URL="$(git remote get-url "$UPSTREAM_REMOTE")"
  if [ "$EXISTING_URL" != "$UPSTREAM_URL" ]; then
    echo "WARNING: Remote '$UPSTREAM_REMOTE' points to $EXISTING_URL"
    echo "Using existing remote URL. Override with:"
    echo "UPSTREAM_REMOTE=<name> UPSTREAM_URL=<url> sh scripts/sync_from_upstream.sh"
  fi
else
  echo "Adding remote '$UPSTREAM_REMOTE' -> $UPSTREAM_URL"
  git remote add "$UPSTREAM_REMOTE" "$UPSTREAM_URL"
fi

CURRENT_BRANCH="$(git --no-pager branch --show-current)"
if [ "$CURRENT_BRANCH" != "$TARGET_BRANCH" ]; then
  echo "Checking out target branch '$TARGET_BRANCH'..."
  git checkout "$TARGET_BRANCH"
fi

echo "Fetching '$UPSTREAM_REMOTE'..."
git fetch "$UPSTREAM_REMOTE" --prune

echo "Fast-forwarding '$TARGET_BRANCH' from '$UPSTREAM_REMOTE/$UPSTREAM_BRANCH'..."
if git merge --ff-only "$UPSTREAM_REMOTE/$UPSTREAM_BRANCH"; then
  echo "Sync complete."
else
  echo "ERROR: Fast-forward failed. Your branch has diverged from upstream."
  echo "Merge manually with: git merge $UPSTREAM_REMOTE/$UPSTREAM_BRANCH"
  exit 1
fi

