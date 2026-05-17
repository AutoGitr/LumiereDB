#!/usr/bin/env bash
set -euo pipefail

root="${1:-data}"

fail() {
  echo "Dataset identity validation failed: $*" >&2
  exit 1
}

[ -d "$root" ] || exit 0

mapfile -t files < <(find "$root" -type f -name '*.json' | sort)
[ "${#files[@]}" -gt 0 ] || exit 0

identities="$(mktemp)"
trap 'rm -f "$identities"' EXIT

for file in "${files[@]}"; do
  media_type="$(jq -r '.media_type // ""' "$file")"
  name="$(basename "$file")"
  stem="${name%.json}"
  id_kind=""
  id_value=""

  case "${file}:${media_type}" in
    data/movies/*.json:movie|./data/movies/*.json:movie|data/tv/*.json:tv|./data/tv/*.json:tv) ;;
    *) fail "${file} path does not match media_type" ;;
  esac

  if [[ "$stem" =~ ^tmdb-[0-9]+$ ]]; then
    id_kind="tmdb"
    id_value="${stem#tmdb-}"
  elif [[ "$stem" =~ ^tvdb-[0-9]+$ ]]; then
    id_kind="tvdb"
    id_value="${stem#tvdb-}"
  elif [[ "$stem" =~ ^imdb-tt[0-9]+$ ]]; then
    id_kind="imdb"
    id_value="${stem#imdb-}"
  else
    fail "${file} filename must be tmdb-<digits>.json, tvdb-<digits>.json, or imdb-tt<digits>.json"
  fi

  json_id_value="$(jq -r --arg kind "$id_kind" '.external_ids[$kind] // ""' "$file")"
  if [ "$json_id_value" != "$id_value" ]; then
    fail "${file} filename identifier ${id_kind}-${id_value} must match external_ids.${id_kind}"
  fi

  for kind in tmdb tvdb imdb; do
    value="$(jq -r --arg kind "$kind" '.external_ids[$kind] // ""' "$file")"
    [ -n "$value" ] || continue
    printf '%s\t%s:%s\t%s\n' "$media_type" "$kind" "$value" "$file" >> "$identities"
  done
done

duplicate_keys="$(cut -f1,2 "$identities" | sort | uniq -d)"
[ -n "$duplicate_keys" ] || exit 0

echo "Duplicate dataset identities:"
while IFS=$'\t' read -r media_type identity; do
  [ -n "$media_type" ] || continue
  printf '%s %s appears in multiple files:\n' "$media_type" "$identity"
  awk -F '\t' -v media_type="$media_type" -v identity="$identity" '
    $1 == media_type && $2 == identity { print "  - " $3 }
  ' "$identities"
done <<< "$duplicate_keys"

exit 1
