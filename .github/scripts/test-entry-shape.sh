#!/usr/bin/env bash
set -euo pipefail

# Checks the check: entry-shape.jq must accept every entry in the dataset,
# reject each way an entry can be wrong, and follow schema/entry.schema.json
# when the schema's own field list changes.

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
schema="${root}/schema/entry.schema.json"
program="${root}/.github/scripts/entry-shape.jq"
failures=0

problems() {
  local entry="$1"
  local against="${2:-$schema}"
  jq -r --slurpfile schema "$against" -f "$program" "$entry"
}

note() {
  printf '  %s\n' "$1"
}

report() {
  printf '  FAILED: %s\n' "$1" >&2
  failures=$((failures + 1))
}

sample() {
  local media_type="$1"
  find "${root}/data" -name '*.json' -exec grep -l "\"media_type\": \"${media_type}\"" {} + | sort | head -n1
}

show="$(sample show)"
movie="$(sample movie)"
[ -n "$show" ] && [ -n "$movie" ] || {
  echo "No sample entries found under ${root}/data" >&2
  exit 1
}

accepts() {
  local entry="$1"
  local found
  found="$(problems "$entry")"
  if [ -n "$found" ]; then
    report "rejected a live entry: ${entry#"${root}/"} -> ${found}"
  fi
}

rejects() {
  local label="$1" filter="$2" entry="${3:-$show}"
  local mutated found
  mutated="$(mktemp)"
  jq "$filter" "$entry" > "$mutated"
  found="$(problems "$mutated")"
  rm -f "$mutated"
  if [ -z "$found" ]; then
    report "accepted ${label}"
  else
    note "rejects ${label} -> $(printf '%s' "$found" | head -n1)"
  fi
}

follows_schema() {
  local label="$1" filter="$2" expected="$3"
  local altered found
  altered="$(mktemp)"
  jq "$filter" "$schema" > "$altered"
  found="$(problems "$show" "$altered")"
  rm -f "$altered"
  case "$found" in
    *"$expected"*) note "follows the schema when ${label}" ;;
    *) report "did not follow the schema when ${label}: ${found:-no problems reported}" ;;
  esac
}

echo "Every entry in the dataset is accepted:"
while IFS= read -r entry; do
  accepts "$entry"
done < <(find "${root}/data" -name '*.json' | sort)
note "checked $(find "${root}/data" -name '*.json' | wc -l | tr -d ' ') entries"

echo "Malformed entries are rejected:"
rejects "the media type the dataset used to publish" '.media_type = "tv"'
rejects "the nesting the dataset used to publish" '.external_ids = {"tmdb": 1}'
rejects "the season key the dataset used to publish" \
  '.seasons = [{"season_number": 1, "poster_url": "https://image.tmdb.org/a.jpg"}]'
rejects "an ID sent as a string" '.tmdb_id = "1396"'
rejects "a year sent as a string" '.year = "2008"'
rejects "a zero ID" '.tvdb_id = 0'
rejects "an IMDb ID without its tt prefix" '.imdb_id = "0903747"'
rejects "a YouTube ID of the wrong length" '.youtube_id = "abcdefghij"'
rejects "an empty title" '.title = ""'
rejects "a title over 200 characters" '.title = ("x" * 201)'
rejects "a null title" '.title = null'
rejects "a missing field" 'del(.youtube_id)'
rejects "an unknown field" '.tagline = "Say my name"'
rejects "a show without seasons" 'del(.seasons)'
rejects "a negative season number" \
  '.seasons = [{"season_num": -1, "poster_url": "https://image.tmdb.org/a.jpg"}]'
rejects "a season poster with no URL" '.seasons = [{"season_num": 1}]'
rejects "a movie carrying seasons" '.seasons = []' "$movie"

echo "The schema stays the single source of truth:"
follows_schema "a field is added" \
  '.properties.tagline = {"type": ["string", "null"]} | .required += ["tagline"]' \
  "missing field(s): tagline"
follows_schema "a field is renamed" \
  '.properties.background_image_url = .properties.background_url
   | del(.properties.background_url)
   | .required = [.required[] | if . == "background_url" then "background_image_url" else . end]' \
  "unknown field(s): background_url"

if [ "$failures" -gt 0 ]; then
  echo "${failures} check(s) failed" >&2
  exit 1
fi

echo "entry-shape.jq is sound"
