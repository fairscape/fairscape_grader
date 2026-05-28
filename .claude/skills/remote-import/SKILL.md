---
name: remote-import
description: Phase 1 of the remote-source wizard. Take a public dataset reference (Dataverse DOI, PhysioNet URL, Figshare article, or anything else publicly accessible) and produce a real RO-Crate directory whose `ro-crate-metadata.json` already has minimal metadata (name, description, authors, keywords, version, doi, license) and per-file `contentUrl` entries pointing at remote URLs. For Dataverse/PhysioNet/Figshare it shells out to the dedicated `fairscape-cli import` subcommand; for anything else it falls back to `build-manifest` then `fairscape-cli import manifest`.
---

# Remote import — Phase 1

You wrap `fairscape-cli import {dataverse|physionet|figshare|manifest}` and capture the result in `.fairscape-remote-state.json`. Public datasets only — no API tokens.

**For sources without a dedicated importer**, this skill orchestrates a two-step path:
1. Invoke `build-manifest` to research the dataset's published file inventory and write `manifest.csv` + `crate.json`.
2. Shell out to `fairscape-cli import manifest` to produce the same crate shape the dedicated importers produce.

Either path lands the user at `state.phase = "imported"` and `tabular_files` populated — downstream phases (`remote-schema-infer`, `remote-ai-ready-enrich`, ...) don't care which import path got used.

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

Pick the first match:

- `doi:` prefix OR a known Dataverse hostname (`dataverse.harvard.edu`, `dataverse.lib.virginia.edu`, ...) → `dataverse`. Default `--server-url https://dataverse.harvard.edu` unless the input came from a known non-Harvard host, in which case pass `--server-url <host>`. (Note: `doi:10.6084/m9.figshare.*` is a Figshare DOI, not Dataverse — check before defaulting.)
- `physionet.org/content/` substring → `physionet`.
- DOI prefix `10.6084/m9.figshare.` OR `figshare.com/articles/` substring OR a bare numeric figshare article ID the user has flagged as such → `figshare`.
- The orchestrator passed `source.kind = "local"` directly (no auto-detection — the user picked "local folder" at the wizard's Phase 1 branch) → `local`.
- **Anything else** → `manifest`. This includes NCBI/GenBank/SRA/GEO URLs, ProteomeXchange/PRIDE, cellxgene, OpenNeuro, AWS/GCP open-data buckets, GitHub releases, lab portals, or just a "paper at <DOI>, data at <URL>" description. Don't tell the user "I can't handle this" — that's wrong; route to the manifest path instead.

## Run the import

### Dataverse
```
fairscape-cli import dataverse <DOI> --output-dir <dir> [--server-url <url>]
```

### PhysioNet
```
fairscape-cli import physionet <URL> --output-dir <dir>
```

### Figshare
```
fairscape-cli import figshare <ARTICLE_ID> --output-dir <dir>
```

### Manifest (generic remote fallback)

Two steps, both required:

1. **Build the manifest.** Invoke `build-manifest` with the user's brief (whatever they pasted: a paper DOI, a dataset URL, a "data is at <X>" hint). It produces:
   ```
   <workdir>/<slug>/
     manifest.csv
     crate.json
   ```
   where `<slug>` is a kebab-cased best guess from the dataset title. `build-manifest` does NOT call the importer — that's the next step.

2. **Import the manifest.** Pick a crate output directory (default: `<workdir>/<slug>-rocrate`). Tell the user the path before running. Then:
   ```
   fairscape-cli import manifest <workdir>/<slug>/manifest.csv --output-dir <crate_dir>
   ```

### Local folder

Four steps, the orchestrator drives them through this skill:

1. **Collect crate-level metadata via the form.** Invoke `extract-crate-metadata` with `mode=form`. It runs an `AskUserQuestion`-driven form for name, description, authors, license, keywords, publication_date, doi. Writes `state.crate_metadata`. State phase → `metadata_captured`.
2. **Walk the folder.** Invoke `scan-project-folder` against `state.source.project_root`. It enumerates files, categorizes by extension, and detects bulk groups (≥10 same-extension siblings in one directory). Writes `state.scan`.
3. **Build the manifest.** Invoke `build-local-manifest`. It hashes singleton files (streaming md5+sha256), skips hashes for bulk-group members, writes `<project_root>/manifest.csv` + `<project_root>/crate.json`. State phase → `manifest_built`.
4. **Import the manifest.** Shell out:
   ```
   fairscape-cli import manifest <project_root>/manifest.csv --output-dir <project_root>
   ```
   The crate is written *into* the project root — `<project_root>/ro-crate-metadata.json`.

Run all steps via `Bash`. If any fails, surface stderr verbatim. Common causes: form was cancelled mid-way (state.crate_metadata incomplete), folder has zero files after noise-dir filtering, hash computation hit a permission error (skill logs which file), or CSV had a description shorter than 10 characters (the Dataset model's minimum — `build-local-manifest` should pad, but if a user pre-edits the CSV they can violate this).

If any step fails, surface stderr verbatim. Common causes for the dedicated importers: dataset is private (suggest a public one), URL malformed, network down. Common causes for the manifest path: source's file inventory wasn't findable (build-manifest will say so), HEAD requests failed (URL pattern wrong), CSV missing required columns.

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
  "schema_version": 2,
  "phase": "imported",
  "source": {"kind": "dataverse|physionet|figshare|manifest|local",
             "url_or_doi": "doi:10.7910/DVN/XYZ",
             "server_url": "https://dataverse.harvard.edu",
             "manifest_dir": "<abs path>",
             "project_root": "<abs path>"},
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

For the **manifest path**, also set `source.manifest_dir` to the folder containing `manifest.csv` + `crate.json`, so resume logic can find the originals (and `build-manifest` is idempotent — re-running it overwrites in place).

Set `state.phase = "imported"` last, after the file is written.

## Don't

- Don't ask the user to fill in name/description/authors yourself — for the dedicated importers the CLI already did that from the upstream metadata, and for the manifest path `build-manifest` already populated the sidecar from the paper. Phase 3 enriches with paper-derived fields.
- Don't `Read` the entire crate JSON into the user's context. Read it, extract the fields you need, summarize.
- Don't fetch any of the data files — `contentUrl`s stay remote. Phase 2 will sample.
- Don't pass `--token` for the first version. If the user mentions a private dataset, tell them token support is out of scope right now.
- Don't tell the user "I only handle Dataverse or PhysioNet" when their input doesn't match a known pattern — that's outdated. Route to the manifest path instead.
