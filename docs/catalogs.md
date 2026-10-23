# Catalogs

## Format

A catalog is a UTF-8 JSON document that states the intended metadata of a set of albums. It is identified by `"format": "ilibrary-catalog-1"`; the numeric suffix changes only for an incompatible change, and documents of other formats are refused. `ilibrary schema` prints the JSON Schema, which is also published as [ilibrary-catalog-1.schema.json](schema/ilibrary-catalog-1.schema.json).

The document holds `albums` and, optionally, `titleRules` and `artists`. Each album holds `discs`, each disc holds `tracks`, and discs and tracks are numbered by their position. Album-level values apply to every track and may be overridden by the same field on a track. An empty string means that a value is unknown and leaves the file's value unchanged; a value is never invented to fill the field.

```json
{
  "format": "ilibrary-catalog-1",
  "titleRules": { "case": "keep", "removeQualifiers": ["Remaster"], "bracketNested": true },
  "albums": [
    {
      "album": "Bad",
      "aliases": ["Bad (Remastered)"],
      "albumArtist": "Michael Jackson",
      "copyright": "℗ 1987 MJJ Productions, Inc.",
      "releaseDate": "1987-08-31",
      "discs": [{ "tracks": [{ "title": "Bad", "composer": "Michael Jackson" }] }]
    }
  ]
}
```

## Fields

| Level | Field | Meaning |
| --- | --- | --- |
| Album | `album` (required) | The album name written to every track |
| Album | `aliases` | Other names under which the album's files may be tagged, such as a remastered edition |
| Album | `albumArtist`, `artist` | The album artist, and the default track artist |
| Album | `genre`, `composer`, `copyright` | Defaults for every track |
| Album | `releaseDate` | `YYYY-MM-DD`, written to the files and used for ordering and timestamps |
| Album | `compilation` | Whether the album is a compilation |
| Album | `artwork` | A PNG or JPEG file, relative to the catalog, embedded as the cover |
| Album | `discs` (required) | The discs, each with its `tracks` |
| Track | `title` (required) | The track title |
| Track | `artist`, `composer`, `genre`, `copyright`, `releaseDate` | Per-track values that override the album's |
| Album, Track | `notes`, `sources` | Evidence for the values; never written to files |
| Document | `artists` | Per-artist settings keyed by artist name; `folderDate` sets the date of the artist's folder |

Validation reports unknown fields, wrong types, missing titles, invalid dates, and duplicate albums of one artist, each with its JSON path, and warns about values such as `(P)` written in place of `℗`. `ilibrary validate CATALOG.json` checks the document alone; with paths, it also checks that every file matches a track and every track a file.

## Title Rules

`titleRules` applies to every title before it is written to a file or used in a file name; the catalog itself keeps the titles as written, and the default rules change nothing. `removeQualifiers` removes trailing parenthesized qualifiers that contain one of the listed terms, such as `(2012 Remaster)`. `bracketNested` writes a parenthetical that contains another parenthetical with square brackets. `preserve` lists words that are never changed.

`case` selects the capitalization: `keep` leaves titles as written, and `mla`, `apa`, and `start` apply MLA headline style, APA title case, and start case. APA lowercases articles, prepositions, and conjunctions of three letters or fewer. Words whose capitalization depends on their grammatical role, such as a word that may be a preposition or an adverb, are left unchanged and reported as warnings by `validate` and `apply`, so that a title is never changed on a guess. `apply --dry-run` shows each title as it will be written.

## Matching Files

A file is matched to an album by its album tag, compared with the album name and its aliases, and to a track by its disc and track numbers, by numbering that continues across discs, and by title. Every match and every refusal is reported, and `apply` changes nothing while any selected file is unmatched.

A file whose title differs from the catalog at its disc and track numbers is matched there, so that the catalog corrects the title, only when no other track carries the file's title and more of the album's files have agreeing titles than differing ones; files without a title tag do not count. Otherwise the file is reported as unmatched. Names follow the Music app: `NN Title.m4a` on single-disc albums and `D-NN Title.m4a` on multi-disc albums, with `_` in place of `:` and `/`, inside `Album Artist/Album/`.

## Authoring a Catalog

A catalog is drafted from existing tags, completed by a person, an AI agent, or an AI chat, validated, and previewed before it is applied. Output from a model is never applied without validation and a dry run.

```bash
ilibrary export ~/Music/Staging -o catalog.json --artwork covers
ilibrary prompt catalog.json > prompt.md
ilibrary validate catalog.json ~/Music/Staging
ilibrary apply catalog.json ~/Music/Staging --rename --timestamps --dry-run
```

`ilibrary prompt` prints the catalog with authoring rules: leave unknown values empty rather than guessing, record evidence for copyright lines and release dates in `notes` and `sources`, and keep the order of discs and tracks. Give the complete output to an AI chat, and replace `catalog.json` with the returned document only after checking that it is a single JSON document. An agent that runs commands should edit only the catalog, never the music files, run `ilibrary validate` after each edit and resolve every error and warning, and present the output of `apply --dry-run` for review before the change is applied.

## Release Dates and Timestamps

Release dates are written to files as `YYYY-MM-DDT00:00:00Z`. `apply --timestamps` and `timestamps` set the creation and modification dates of each file to its release date at local midnight, or at the first instant of the day where a time zone skips midnight. Album folders that hold one album receive the album's date, and an artist folder receives a date only when `artists` gives it a `folderDate`. A missing path is reported and never created, and symbolic links are refused.
