#!/usr/bin/env bash
set -euo pipefail

# Fails when two entries of the same media type claim the same external ID.
# Every other per-entry rule is validate-entry.sh's job.

root="${1:-data}"

[ -d "$root" ] || exit 0

mapfile -t files < <(find "$root" -type f -name '*.json' | sort)
[ "${#files[@]}" -gt 0 ] || exit 0

identities="$(mktemp)"
trap 'rm -f "$identities"' EXIT

for file in "${files[@]}"; do
  media_type="$(jq -r '.media_type' "$file")"
  for field in tmdb_id tvdb_id imdb_id; do
    value="$(jq -r --arg field "$field" '.[$field] | if . == null then "" else tostring end' "$file")"
    [ -n "$value" ] || continue
    printf '%s\t%s:%s\t%s\n' "$media_type" "$field" "$value" "$file" >> "$identities"
  done
done

duplicate_keys="$(cut -f1,2 "$identities" | sort | uniq -d)"
[ -n "$duplicate_keys" ] || exit 0

echo "Duplicate dataset identities:" >&2
while IFS=$'\t' read -r media_type identity; do
  [ -n "$media_type" ] || continue
  printf '%s %s appears in multiple files:\n' "$media_type" "$identity" >&2
  awk -F '\t' -v media_type="$media_type" -v identity="$identity" '
    $1 == media_type && $2 == identity { print "  - " $3 }
  ' "$identities" >&2
done <<< "$duplicate_keys"

exit 1
