#!/usr/bin/env bash
set -euo pipefail

file="${1:?usage: validate-entry.sh data/path.json}"
schema="${2:-schema/entry.schema.json}"

fail() {
  echo "Validation failed for ${file}: $*" >&2
  exit 1
}

validate_art_url() {
  local url="$1"
  local host

  [ -z "$url" ] && return 0

  case "$url" in
    https://*) ;;
    *) fail "art URL must use https: ${url}" ;;
  esac

  host="$(printf '%s' "$url" | sed -E 's#^https://([^/:?#]+).*$#\1#' | tr '[:upper:]' '[:lower:]')"

  case "$host" in
    localhost|*.localhost|127.*|0.0.0.0|10.*|192.168.*|172.16.*|172.17.*|172.18.*|172.19.*|172.20.*|172.21.*|172.22.*|172.23.*|172.24.*|172.25.*|172.26.*|172.27.*|172.28.*|172.29.*|172.30.*|172.31.*|*.githubusercontent.com|githubusercontent.com|discordapp.com|*.discordapp.com|discord.com|*.discord.com)
      fail "blocked art URL host: ${host}"
      ;;
  esac

  if printf '%s' "$host" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$|:|\[|\]'; then
    fail "direct IP art URLs are not allowed: ${url}"
  fi

  case "$host" in
    image.tmdb.org|assets.fanart.tv|theposterdb.com|www.theposterdb.com|artworks.thetvdb.com)
      ;;
    *)
      fail "art URL host is not allowlisted: ${host}"
      ;;
  esac
}

[ -f "$file" ] || fail "file does not exist"
[ -f "$schema" ] || fail "schema file does not exist: ${schema}"

jq empty "$schema" >/dev/null || fail "schema is not valid JSON"
jq empty "$file" >/dev/null || fail "entry is not valid JSON"

jq -e '
  def optional_string: . == null or type == "string";
  def optional_digits: . == null or (type == "string" and test("^[0-9]+$"));
  def optional_imdb: . == null or (type == "string" and test("^tt[0-9]+$"));
  def optional_youtube: . == null or (type == "string" and test("^[A-Za-z0-9_-]{11}$"));
  def integer: type == "number" and . == floor;
  def nonnegative_integer: integer and . >= 0;
  def year_value: . == null or (integer and . >= 1000 and . <= 9999);

  (keys_unsorted | sort) == ["art","episodes","external_ids","media_type","seasons","theme","title","year"] and
  (.media_type == "movie" or .media_type == "tv") and
  (.title | type == "string" and length > 0 and length <= 200) and
  (.year | year_value) and
  (.external_ids | type == "object") and
  (.external_ids | (keys_unsorted | sort) == ["imdb","tmdb","tvdb"]) and
  (.external_ids.tmdb | optional_digits) and
  (.external_ids.tvdb | optional_digits) and
  (.external_ids.imdb | optional_imdb) and
  (.art | type == "object") and
  (.art | (keys_unsorted | sort) == ["background_url","logo_url","poster_url"]) and
  (.art.poster_url | optional_string) and
  (.art.background_url | optional_string) and
  (.art.logo_url | optional_string) and
  (.theme | type == "object") and
  (.theme | (keys_unsorted | sort) == ["youtube_id"]) and
  (.theme.youtube_id | optional_youtube) and
  (.seasons | type == "array") and
  all(.seasons[]; type == "object" and (keys_unsorted | sort) == ["poster_url","season_number"] and (.season_number | nonnegative_integer) and (.poster_url | type == "string" and length > 0)) and
  (.episodes | type == "array") and
  all(.episodes[]; type == "object" and (keys_unsorted | sort) == ["episode_number","season_number","thumb_url"] and (.season_number | nonnegative_integer) and (.episode_number | nonnegative_integer) and (.thumb_url | type == "string" and length > 0))
' "$file" >/dev/null || fail "entry does not match schema shape"

media_type="$(jq -r '.media_type' "$file")"
tmdb_id="$(jq -r '.external_ids.tmdb // ""' "$file")"
tvdb_id="$(jq -r '.external_ids.tvdb // ""' "$file")"
imdb_id="$(jq -r '.external_ids.imdb // ""' "$file")"

case "${file}:${media_type}" in
  data/movies/*.json:movie|data/tv/*.json:tv) ;;
  *) fail "file path does not match media_type" ;;
esac

if [ "$media_type" = "movie" ] && [ -z "$tmdb_id" ] && [ -z "$imdb_id" ]; then
  fail "movie entries need a TMDB ID or IMDb ID"
fi

if [ "$media_type" = "tv" ] && [ -z "$tvdb_id" ] && [ -z "$tmdb_id" ] && [ -z "$imdb_id" ]; then
  fail "TV entries need a TVDB, TMDB, or IMDb ID"
fi

jq -r '
  [
    .art.poster_url,
    .art.background_url,
    .art.logo_url,
    (.seasons[]?.poster_url),
    (.episodes[]?.thumb_url)
  ] | .[] | select(. != null and . != "")
' "$file" | while IFS= read -r url; do
  validate_art_url "$url"
done
