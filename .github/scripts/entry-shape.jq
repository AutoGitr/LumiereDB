# Reports every way one dataset entry fails to match schema/entry.schema.json,
# one problem per line, and nothing at all when the entry is good.
#
# Which fields exist and which are required is read from the schema itself, so
# a field added, renamed or removed there is picked up here without this file
# being touched. Only the per-field types are restated below.

def is_int: type == "number" and floor == .;
def optional_id: . == null or (is_int and . >= 1);
def optional_url: . == null or (type == "string" and length >= 1);
def optional_match($pattern): . == null or (type == "string" and test($pattern));

($schema[0].properties | keys) as $known
| $schema[0].required as $required
| (
  (keys - $known | select(length > 0) | "unknown field(s): \(join(", "))"),
  ($required - keys | select(length > 0) | "missing field(s): \(join(", "))"),

  (select(.media_type != "movie" and .media_type != "show")
    | "media_type must be movie or show"),
  (select(.title | (type == "string" and length >= 1 and length <= 200) | not)
    | "title must be a string of 1 to 200 characters"),
  (select(.year != null and ((.year | is_int | not) or .year < 1000 or .year > 9999))
    | "year must be a four-digit integer or null"),
  (select(.tmdb_id | optional_id | not) | "tmdb_id must be a positive integer or null"),
  (select(.tvdb_id | optional_id | not) | "tvdb_id must be a positive integer or null"),
  (select(.imdb_id | optional_match("^tt[0-9]+$") | not)
    | "imdb_id must look like tt1234567, or be null"),
  (select(.poster_url | optional_url | not)
    | "poster_url must be a non-empty string or null"),
  (select(.background_url | optional_url | not)
    | "background_url must be a non-empty string or null"),
  (select(.youtube_id | optional_match("^[A-Za-z0-9_-]{11}$") | not)
    | "youtube_id must be an 11-character video ID, or null"),

  (select(.media_type == "show" and (has("seasons") | not))
    | "a show entry must carry seasons"),
  (select(.media_type == "movie" and has("seasons"))
    | "a movie entry must not carry seasons"),
  (.seasons // [] | to_entries[] | "seasons[\(.key)]" as $at | .value
    | if type != "object" or ((keys_unsorted | sort) != ["poster_url", "season_num"])
      then "\($at) must carry exactly season_num and poster_url"
      elif (.season_num | is_int | not) or .season_num < 0
      then "\($at).season_num must be a non-negative integer"
      elif (.poster_url | type != "string") or (.poster_url | length < 1)
      then "\($at).poster_url must be a non-empty string"
      else empty
      end)
)
