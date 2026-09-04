# LumiereDB

Public dataset of images and theme music used by Lumiere.

## Contract

`schema/entry.schema.json`, `schema/catalog.schema.json`, and `schema/contract.py`
are the canonical version 2 contract, shared with Lumiere through its
`scripts/dataset_contract.py` generator. Change this source first, regenerate the
app's bundled copy, and land both changes together. No legacy catalog format is
supported.

Entries have a nonblank title of at most 200 characters, a nullable four-digit
year, and at least one external ID. Numeric IDs are positive signed 64-bit
integers; IMDb IDs use `tt` followed by digits. IDs are unique within each media
type, so a movie and show can legitimately share a numeric ID. Shows require a
season list with unique nonnegative season numbers; movies cannot have seasons.
Optional source attribution must include a name, URL, and license. Unknown
properties, wrong scalar types, and duplicate identities reject the entire
catalog, not just the offending entry.

Files live directly in `data/movies` or `data/shows`, named for one of their IDs
(`tmdb-123.json`, `tvdb-123.json`, or `imdb-tt123.json`). Artwork uses public HTTPS
destinations on the allowlist in `.github/scripts/catalog.py`. Live checks validate
every redirect and inspect only the first 16 bytes to verify JPEG/PNG content.

## Validation and publishing

Use Python 3.14.7:

```sh
python -m pip install -r .github/scripts/requirements.txt
python -m unittest discover -s .github/scripts -p 'test_*.py'
python .github/scripts/catalog.py validate
python .github/scripts/catalog.py validate --check-urls
python .github/scripts/catalog.py build
```

Every contribution validates the complete dataset's structure and identities;
`--entry data/movies/tmdb-123.json` limits only the live URL checks. Publication
validates all entries and all artwork URLs before uploading any Pages artifact.
Pushes to `main`, the daily schedule, and manual runs publish the current `main`.
Build jobs have read-only repository permissions; only the deployment job gets
Pages and identity-token write permissions.

The build writes `public/catalog.json`, reproducible `catalog.json.gz`,
`SHA256SUMS`, the JSON schemas, and the required notices/licenses. Entry order,
JSON encoding, and gzip timestamps are deterministic. `source_revision` identifies
the Git commit, and `generated_at` is that commit's UTC timestamp, not build time.
The build command requires a clean checkout so this provenance is accurate.
Identical source and toolchain inputs produce identical artifact bytes. Digests
detect byte differences; they are not signatures or proof of authenticity.
