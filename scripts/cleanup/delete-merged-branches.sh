#!/usr/bin/env bash
# Delete local and remote branches that have been merged into main

set -euo pipefail

base=${1:-main}

# delete local merged branches
for b in $(git branch --merged "$base" | grep -vE "\*|$base"); do
  git branch -d "$b" || git branch -D "$b" || true
done

# delete remote merged branches (origin)
for b in $(git branch -r --merged "origin/$base" | grep -vE "origin/$base" | sed 's|origin/||'); do
  git push origin --delete "$b" || true
done
