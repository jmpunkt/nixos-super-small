#!/bin/sh
# Strip ELF files while preserving their metadata.
#
# Usage: strip-elf <strip> <file>...
#
# Ensures that the final binaries are smaller than before. If stripping
# increases the size, the original binary is used.
set -u

strip=${1:?usage: strip-elf <strip> <file>...}
shift

for file in "$@"; do
  case "$file" in
    *.ko) strip_flags=--strip-debug ;;
    *) strip_flags=--strip-all ;;
  esac

  tmp=$(mktemp) || continue

  if "$strip" -p "$strip_flags" \
      --remove-section=.comment --remove-section=.note \
      -o "$tmp" "$file" 2>/dev/null; then
    # Only replace the original when stripping actually saved space.
    if [ "$(stat -c %s "$tmp")" -lt "$(stat -c %s "$file")" ]; then
      cp --preserve=timestamps "$tmp" "$file"
    fi
  fi

  rm -f "$tmp"
done
