# TV collection pack

`app/assets/collections/tv-pack.json` holds Liquiflux's TV networks and programming blocks
(the TV Networks page, and the "Networks & Blocks" channel source). It's the same file for
everyone. Each install matches its show ids against its own Plex library.

## How it's built

`build_pack.py` uses only the Python standard library and needs no API keys.

- **Blocks** (Toonami, Nick at Nite...) come from the Wikipedia pages named in
  `sources.json`. For each table row, and each bullet at the top level, the builder takes
  the first linked title. Wikidata gives that title's TVDB, TMDB and IMDb ids. TVmaze
  confirms it's a series and adds a rating, a popularity score and a poster.
  - When Wikipedia links to a manga rather than the anime, the builder searches TVmaze by
    name instead, using the years the show aired on the block.
- **Networks** come from TVmaze's show index: the network or streaming service each show
  premiered on. Each network keeps its 400 best-known shows.

The **Collection pack** workflow (`.github/workflows/collection-pack.yml`) runs the
builder and commits the pack and `report.md` back to the branch it ran on. It runs:

- when `build_pack.py`, `sources.json` or the workflow file changes;
- on Run workflow;
- on the 1st of every month.

Wikipedia, Wikidata and TVmaze can't be reached from the Claude cloud container. Build the
pack in Actions or on a machine that has internet access:

    python3 tools/collection-pack/build_pack.py              # everything
    python3 tools/collection-pack/build_pack.py --only toonami,snick --no-networks

## Adding a block

Add an entry to `blocks` in `sources.json`. These are the fields an entry can have:

- `pages`: the Wikipedia pages to read.
- `sections`: a regex. Only rows under a heading that matches it are read.
- `skip`: a regex. Rows under a heading that matches it are skipped.
- `animated: true`: name searches accept only animated shows.
- `filter: "anime"`: keeps only Japanese-language or anime shows.

Push the change and the workflow rebuilds the pack. Then check `report.md`: it lists each
page's headings and the rows that didn't match. Lists of shows are facts; credit Wikipedia,
TVmaze (both CC BY-SA 4.0) and Wikidata (CC0), as the pack's `credits` field does.
