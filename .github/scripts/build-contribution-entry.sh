#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: build-contribution-entry.sh <issue-body-file> <issue-title> <labels-file> <output-root>" >&2
}

[ "$#" -eq 4 ] || {
  usage
  exit 2
}

body_file="$1"
issue_title="$2"
labels_file="$3"
output_root="$4"

fail() {
  echo "$1" >&2
  exit 1
}

[ -f "$body_file" ] || fail "Issue body file does not exist: ${body_file}"
[ -f "$labels_file" ] || fail "Labels file does not exist: ${labels_file}"

field() {
  awk -v heading="$1" '
    $0 == "### " heading { capture = 1; next }
    /^### / && capture { exit }
    capture { print }
  ' "$body_file" \
    | sed '/^[[:space:]]*$/d' \
    | sed 's/^_No response_$//'
}

clean_single_line() {
  printf '%s' "$1" | tr -d '\r' | head -n1
}

if grep -qx "movie" "$labels_file"; then
  media_type="movie"
elif grep -qx "show" "$labels_file"; then
  media_type="tv"
elif printf '%s' "$issue_title" | grep -q '^\[Movie\]:'; then
  media_type="movie"
elif printf '%s' "$issue_title" | grep -q '^\[Show\]:'; then
  media_type="tv"
else
  fail "Issue must use the movie or show contribution form."
fi

title="$(clean_single_line "$(field "Title")")"
year="$(clean_single_line "$(field "Year")")"
tmdb_id="$(clean_single_line "$(field "TMDB ID")")"
tvdb_id="$(clean_single_line "$(field "TVDB ID")")"
imdb_id="$(clean_single_line "$(field "IMDb ID")")"
poster_url="$(clean_single_line "$(field "Poster URL")")"
background_url="$(clean_single_line "$(field "Background URL")")"
youtube_id="$(clean_single_line "$(field "YouTube theme video ID")")"
season_posters="$(field "Season posters")"

[ -n "$title" ] || fail "Missing Title field."

if [ -n "$tmdb_id" ] && ! printf '%s' "$tmdb_id" | grep -Eq '^[0-9]+$'; then
  fail "TMDB ID must contain digits only."
fi

if [ -n "$tvdb_id" ] && ! printf '%s' "$tvdb_id" | grep -Eq '^[0-9]+$'; then
  fail "TVDB ID must contain digits only."
fi

if [ -n "$imdb_id" ] && ! printf '%s' "$imdb_id" | grep -Eq '^tt[0-9]+$'; then
  fail "IMDb ID must use the format tt followed by digits."
fi

if [ "$media_type" = "movie" ]; then
  mkdir -p "${output_root}/data/movies"

  if [ -n "$tmdb_id" ]; then
    target="data/movies/tmdb-${tmdb_id}.json"
  elif [ -n "$tvdb_id" ]; then
    target="data/movies/tvdb-${tvdb_id}.json"
  elif [ -n "$imdb_id" ]; then
    target="data/movies/imdb-${imdb_id}.json"
  else
    fail "Movie contributions need a TMDB, TVDB, or IMDb ID."
  fi
else
  mkdir -p "${output_root}/data/tv"

  if [ -n "$tvdb_id" ]; then
    target="data/tv/tvdb-${tvdb_id}.json"
  elif [ -n "$tmdb_id" ]; then
    target="data/tv/tmdb-${tmdb_id}.json"
  elif [ -n "$imdb_id" ]; then
    target="data/tv/imdb-${imdb_id}.json"
  else
    fail "Show contributions need a TVDB, TMDB, or IMDb ID."
  fi
fi

if [ -e "${output_root}/${target}" ]; then
  fail "Dataset file already exists on main: \`${target}\`. Please update it manually."
fi

seasons_json="$(
  printf '%s\n' "$season_posters" | jq -R -s '
    split("\n")
    | map(select(length > 0 and contains("=")))
    | map(
        capture("^(?<season_number>[0-9]+)=(?<poster_url>.+)$")
        | {
            season_number: (.season_number | tonumber),
            poster_url
          }
      )
  '
)" || fail "Season posters must use season_number=url lines."

if ! jq -n \
    --arg media_type "$media_type" \
    --arg title "$title" \
    --arg year "$year" \
    --arg tmdb "$tmdb_id" \
    --arg tvdb "$tvdb_id" \
    --arg imdb "$imdb_id" \
    --arg poster "$poster_url" \
    --arg background "$background_url" \
    --arg youtube "$youtube_id" \
    --argjson seasons "$seasons_json" \
    '{
      media_type: $media_type,
      title: $title,
      year: (if $year == "" then null else ($year | tonumber) end),
      external_ids: {
        tmdb: (if $tmdb == "" then null else $tmdb end),
        tvdb: (if $tvdb == "" then null else $tvdb end),
        imdb: (if $imdb == "" then null else $imdb end)
      },
      art: {
        poster_url: (if $poster == "" then null else $poster end),
        background_url: (if $background == "" then null else $background end)
      },
      theme: {
        youtube_id: (if $youtube == "" then null else $youtube end)
      },
      seasons: $seasons
    }' > "${output_root}/${target}"; then
  rm -f "${output_root}/${target}"
  fail "Submitted fields could not be converted into dataset JSON. Check numeric year and mapping fields."
fi

printf '%s\n' "$target"
