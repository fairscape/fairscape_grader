---
name: remote-import
description: Phase 1 of the remote-source wizard. Take a public Dataverse DOI or PhysioNet URL, shell out to `fairscape-cli import`, and produce a real RO-Crate directory whose `ro-crate-metadata.json` already has minimal metadata (name, description, authors, keywords, version, doi, license) and per-file `contentUrl` entries pointing at remote URLs.
---

# Remote import — Phase 1

You wrap `fairscape-cli import {dataverse|physionet}` and capture the result in `.fairscape-remote-state.json`. Public datasets only — no API tokens.

## What to tell the user before any commands run

Before invoking the CLI, give the user a one-paragraph explanation in plain language so they know what they're watching:

> *"I'm about to call `fairscape-cli import <kind>`. That command talks to the `<kind>` REST API, fetches the dataset's record — title, authors, file list, DOI, publication date, license, keywords — and writes a starter `ro-crate-metadata.json` into `<output_dir>`. Each file in that JSON gets a `contentUrl` pointing back at the repository (e.g. `https://dataverse.lib.virginia.edu/api/access/datafile/<id>`), so no actual data bytes are downloaded — anyone consuming the crate fetches them from the repository directly. This usually takes 5–30 seconds depending on file count."*

Substitute the real kind, output dir, and a realistic time estimate based on what you can see. Don't lecture if the user has already been through this wizard before (check `state.history`).

## Inputs

Ask the user (or accept from the orchestrator) for **one** of:
- A Dataverse DOI like `doi:10.7910/DVN/XYZ` (also accept full URLs like `https://dataverse.harvard.edu/dataset.xhtml?persistentId=doi:10.7910/DVN/XYZ` — extract the `doi:` token).
- A PhysioNet URL like `https://physionet.org/content/<id>/<version>/` (trailing slash required by the CLI).

Optionally ask for an output directory. Default: `./<slug>-rocrate` resolved against `pwd`, where `<slug>` is a kebab-cased best guess from the DOI/URL (e.g. `dvn-xyz`, `<id>-<version>`). Tell the user the path before running.

## Detect source kind

- `doi:` prefix → `dataverse`. Default `--server-url https://dataverse.harvard.edu` unless the input came from a known non-Harvard host (e.g. `dataverse.lib.virginia.edu`), in which case pass `--server-url <host>`.
- `physionet.org/content/` substring → `physionet`.
- Anything else → tell the user "I only handle Dataverse DOIs or PhysioNet URLs right now."

## Run the import

For Dataverse:
```
fairscape-cli import dataverse <DOI> --output-dir <dir> [--server-url <url>]
```

For PhysioNet:
```
fairscape-cli import physionet <URL> --output-dir <dir>
```

Run via `Bash`. If it fails, surface the CLI's stderr verbatim — don't paraphrase. Common causes: dataset is private (we say so + suggest the user try a public one), URL malformed, network down.

## After it succeeds

1. `Read` `<dir>/ro-crate-metadata.json`.
2. Find the root Dataset (the entity referenced by the descriptor's `about.@id`). Tell the user what just got created — not a status line, an actual picture they can use:

   > *"Here's what the importer found and wrote into `<dir>/ro-crate-metadata.json`:*
   > *• **Name:** `<title>`*
   > *• **Authors:** `<author string>`*
   > *• **DOI:** `<doi or 'none recorded'>`*
   > *• **Version:** `<version>`*
   > *• **Files:** `<N>` total — broken down by type below.*
   >
   > *That JSON is your crate's spine. From now on, every phase either appends new entries to it (phase 2 adds schemas) or fills in fields on the root entry (phase 3 adds RAI). The data files themselves are still on `<source.kind>` — the crate just references them."*

3. Build `state.tabular_files` by walking `@graph` for entities `schema infer` can read. The CLI supports CSV, TSV, Parquet, and HDF5. Detection (in order of preference):
   - `format` field equals (case-insensitive) `csv`, `tsv`, `parquet`, `hdf5`, `h5`, `text/csv`, `text/tab-separated-values`, `application/parquet`, `application/x-hdf5`, etc. The Dataverse importer often sets `format` to the bare extension (e.g. `parquet`), so substring match on the lowercased value is the safest signal.
   - If `format` is missing, fall back to the `name` field's extension (Dataverse `contentUrl`s look like `/api/access/datafile/123` and carry no extension — don't rely on the URL).
   - Skip `.gz`-suffixed names — `schema infer` doesn't read gzipped files. Record them with `"skipped": "compressed"` so the user sees we noticed.
   For each match, record `{"@id", "name", "contentUrl", "format", "size_bytes"}`.
4. Tell the user how many tabular-like files we found, grouped by detected type (e.g. "8 parquet, 2 csv"). Zero is fine — phase 2 will be a no-op.

## State write

Either create `.fairscape-remote-state.json` if missing, or update the existing one. Atomic write: write to `<file>.tmp`, then `os.replace`. Fields:

```json
{
  "schema_version": 1,
  "phase": "imported",
  "source": {"kind": "dataverse", "url_or_doi": "doi:10.7910/DVN/XYZ",
             "server_url": "https://dataverse.harvard.edu"},
  "crate_dir": "<abs path>",
  "crate_path": "<abs path>/ro-crate-metadata.json",
  "imported_at": "<UTC ISO8601>",
  "tabular_files": [
    {"@id": "ark:...", "name": "vitals.csv",
     "contentUrl": "https://.../vitals.csv",
     "format": "text/csv", "size_bytes": 12345678}
  ],
  "history": [
    {"ts": "...", "skill": "remote-import",
     "summary": "imported <kind> <id> → <N> total files, <M> tabular"}
  ]
}
```

Preserve any pre-existing fields (e.g. if the orchestrator already wrote `source.url_or_doi` before invoking you). Append to `history` rather than overwriting.

Set `state.phase = "imported"` last, after the file is written.

## Don't

- Don't ask the user to fill in name/description/authors yourself — the CLI already did that from the upstream metadata. Phase 3 enriches with paper-derived fields.
- Don't `Read` the entire crate JSON into the user's context. Read it, extract the fields you need, summarize.
- Don't fetch any of the data files — `contentUrl`s stay remote. Phase 2 will sample.
- Don't pass `--token` for the first version. If the user mentions a private dataset, tell them token support is out of scope right now.
