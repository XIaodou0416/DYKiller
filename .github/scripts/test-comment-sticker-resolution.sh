#!/usr/bin/env bash

set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
output="$(mktemp -d)"
trap 'rm -rf "$output"' EXIT

xcrun --sdk macosx clang \
  -fobjc-arc -fobjc-runtime=macosx-10.13 \
  -Isrc/Features/MediaSave \
  tests/DKCommentStickerResolutionTests.m \
  src/Features/MediaSave/DKMediaResolver.m \
  src/Features/MediaSave/DKMediaSelect.m \
  src/Features/MediaSave/DKMediaSaveItem.m \
  -framework Foundation \
  -o "$output/comment-sticker-tests"

"$output/comment-sticker-tests"
