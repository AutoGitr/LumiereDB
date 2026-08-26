#!/usr/bin/env bash
set -euo pipefail

# Validates one dataset entry: its shape against the published JSON Schema, its
# placement in the tree, and that every art URL it carries is a reachable image
# from an allowlisted host. Duplicate identities across the whole dataset are
# validate-dataset-identities.sh's job.

file="${1:?usage: validate-entry.sh data/path.json}"
schema="${2:-schema/entry.schema.json}"

fail() {
  echo "Validation failed for ${file}: $*" >&2
  exit 1
}

validate_art_url() {
  local url="$1"
  local host
  local path
  local lower_path
  local extension
  local headers
  local body
  local content_type
  local magic

  [ -z "$url" ] && return 0

  case "$url" in
    https://*) ;;
    *) fail "art URL must use https: ${url}" ;;
  esac

  host="$(printf '%s' "$url" | sed -E 's#^https://([^/:?#]+).*$#\1#' | tr '[:upper:]' '[:lower:]')"
  path="$(printf '%s' "$url" | sed -E 's#^https://[^/?#]+([^?#]*).*$#\1#')"
  lower_path="$(printf '%s' "$path" | tr '[:upper:]' '[:lower:]')"

  case "$host" in
    localhost|*.localhost|127.*|0.0.0.0|10.*|192.168.*|172.16.*|172.17.*|172.18.*|172.19.*|172.20.*|172.21.*|172.22.*|172.23.*|172.24.*|172.25.*|172.26.*|172.27.*|172.28.*|172.29.*|172.30.*|172.31.*|*.githubusercontent.com|githubusercontent.com|discordapp.com|*.discordapp.com|discord.com|*.discord.com)
      fail "blocked art URL host: ${host}"
      ;;
  esac

  if printf '%s' "$host" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$|:|\\[|\\]'; then
    fail "direct IP art URLs are not allowed: ${url}"
  fi

  case "$host" in
    image.tmdb.org|assets.fanart.tv|theposterdb.com|www.theposterdb.com|artworks.thetvdb.com|metadata-static.plex.tv)
      ;;
    *)
      fail "art URL host is not allowlisted: ${host}"
      ;;
  esac

  case "$host" in
    theposterdb.com|www.theposterdb.com)
      case "$path" in
        /api/*) ;;
        *) fail "theposterdb art URLs must use the /api/ path: ${url}" ;;
      esac
      ;;
  esac

  if [[ "$lower_path" =~ \.([a-z0-9]+)$ ]]; then
    extension="${BASH_REMATCH[1]}"
    case "$extension" in
      jpg|jpeg|png) ;;
      *) fail "art URL file extension must be jpg, jpeg, or png: ${url}" ;;
    esac
  fi

  headers="$(mktemp)"
  body="$(mktemp)"
  trap 'rm -f "$headers" "$body"' RETURN

  if ! curl --fail --silent --show-error --location --max-time 20 --retry 2 --range 0-15 --dump-header "$headers" --output "$body" "$url"; then
    fail "art URL is not reachable: ${url}"
  fi

  content_type="$(
    tr -d '\r' < "$headers" | awk '
      { line = tolower($0) }
      line ~ /^content-type:/ {
        sub(/^content-type:[[:space:]]*/, "", line)
        sub(/[;[:space:]].*$/, "", line)
        content_type = line
      }
      END { print content_type }
    '
  )"

  case "$content_type" in
    image/jpeg|image/jpg|image/png) ;;
    *) fail "art URL must resolve to a JPG/JPEG or PNG image: ${url} (got ${content_type:-unknown})" ;;
  esac

  magic="$(od -An -tx1 -N8 "$body" | tr -d '[:space:]')"
  case "$content_type:$magic" in
    image/jpeg:ffd8ff*|image/jpg:ffd8ff*|image/png:89504e470d0a1a0a*) ;;
    *) fail "art URL response body is not a valid JPG/JPEG or PNG image: ${url}" ;;
  esac

  rm -f "$headers" "$body"
  trap - RETURN
}

[ -f "$file" ] || fail "file does not exist"
[ -f "$schema" ] || fail "schema file does not exist: ${schema}"

check-jsonschema --schemafile "$schema" "$file" || fail "entry does not match ${schema}"

relative="${file#./}"
media_type="$(jq -r '.media_type' "$file")"

case "$media_type" in
  movie) folder="data/movies" ;;
  show) folder="data/shows" ;;
  *) fail "unknown media_type: ${media_type}" ;;
esac

[ "$(dirname "$relative")" = "$folder" ] || fail "a ${media_type} entry belongs in ${folder}/"

stem="$(basename "$relative" .json)"
case "$stem" in
  tmdb-*) id_field="tmdb_id" ;;
  tvdb-*) id_field="tvdb_id" ;;
  imdb-*) id_field="imdb_id" ;;
  *) fail "filename must be tmdb-<digits>.json, tvdb-<digits>.json, or imdb-tt<digits>.json" ;;
esac

[[ "$stem" =~ ^(tmdb-[0-9]+|tvdb-[0-9]+|imdb-tt[0-9]+)$ ]] ||
  fail "filename must be tmdb-<digits>.json, tvdb-<digits>.json, or imdb-tt<digits>.json"

entry_id="$(jq -r --arg field "$id_field" '.[$field] | if . == null then "" else tostring end' "$file")"
[ "$entry_id" = "${stem#*-}" ] || fail "filename says ${stem} but ${id_field} is ${entry_id:-null}"

jq -r '[.poster_url, .background_url, (.seasons[]?.poster_url)] | .[] | select(. != null)' "$file" |
  while IFS= read -r url; do
    validate_art_url "$url"
  done
