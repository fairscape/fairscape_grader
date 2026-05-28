---
name: build-local-manifest
description: Build a manifest (manifest.csv + crate.json) from a local project folder. Walks the folder's file inventory (produced by scan-project-folder), computes md5+sha256 for singleton files via streaming hash, skips hashing for bulk-group members (≥10 same-extension siblings in one directory) when over the project-total threshold, composes per-file descriptions, sets contentUrl to `file:///<relpath>`, and writes the sidecar with crate-level metadata collected via the form path. Output is the input to `fairscape-cli import manifest`. Does NOT call the importer.
---

# Build a manifest from a local folder

You're the **local-source mirror** of `build-manifest`. Same output contract — `manifest.csv` + `crate.json` in a folder — but the files exist on disk, so hashes get computed locally instead of pulled from a published index.

```
<project_root>/
  manifest.csv     # one row per file (name, description, contentUrl=file:///<relpath>, [md5, sha256, size_bytes, ...])
  crate.json       # sidecar with title, authors, license, keywords, publication_date, [doi]
```

Caller (`remote-import` or the unified wizard) runs `fairscape-cli import manifest manifest.csv --output-dir <project_root>` next. **You do not.**

The manifest format is the same as `wizards/manifest-import-design/DESIGN.md`. The HPRC test case at `wizards/manifest-import-design/hprc-subset/` is the canonical CSV/JSON shape — mirror it.

## When you're invoked

Expected caller is **`remote-import`** when the user picked the local-folder branch in the unified wizard (`source.kind = "local"`). You can also be invoked directly when a user has already collected crate-level metadata and just wants the manifest produced for a folder.

## Inputs

The orchestrator must supply (either via state or directly):

- **`project_root`** — absolute path to the folder. This will also be the crate output directory.
- **`state.scan`** — the output of `scan-project-folder` (file inventory grouped by category, with `group_key` annotation per file marking bulk groups). If state isn't already populated, run `scan-project-folder` first.
- **`state.crate_metadata`** — the form output from `extract-crate-metadata` (form path): `name`, `description`, `authors[]`, `keywords[]`, `license`, `publication_date`, `doi` (optional).

If any are missing, stop and ask the caller to populate them. Don't interview the user yourself — the form path lives in `extract-crate-metadata`, not here.

## Procedure

### 1. Resolve files in scope

From `state.scan.files_by_category`, flatten every category (`scripts`, `data`, `docs`, `pdfs`, `other`) into a single list. Drop `state.scan.existing_crate` if set (the existing `ro-crate-metadata.json` mustn't appear in the new manifest).

Annotate each file as either:
- **`singleton`** — `group_key` is null/absent, OR the group has fewer than 10 members.
- **`bulk`** — `group_key` is set and the group has ≥ 10 members.

The threshold matches `scan-project-folder`. It's deliberately set at 10 (not 3 or 4) because small clusters of same-extension files in a directory are usually distinct work (four sibling Python scripts, three CSVs with different contents) rather than a templated bulk pattern; treating them as bulk would hide their individual identities in the crate.

Also determine the **entity type** for each file (default: extension-based auto-detection, which matches what the manifest connector does):

- **`software`** — files whose extension is one of: `.py .r .sh .bash .ipynb .jl .m .exe .java .cpp .js .jsx .ts .tsx .css`. These become `Software` entities in the crate via `GenerateSoftware` → `fairscape_models.software.Software`.
- **`dataset`** — everything else. These become `Dataset` entities via `GenerateDataset` → `fairscape_models.dataset.Dataset`.

The manifest CSV carries the type explicitly in a `type` column (see step 3) so the import is deterministic and the user can override edge cases (e.g. a `.py` file that's actually data).

### 2. Decide whether to hash everything

Compute totals over the files-in-scope: `TOTAL_FILES = count`, `TOTAL_BYTES = sum(size_bytes)`.

**Threshold rule:** if `TOTAL_FILES < 1000` AND `TOTAL_BYTES < 1 GiB (1,073,741,824 bytes)`, **hash every file**, bulk groups included. Otherwise hash singletons only and leave bulk-group hashes blank.

The reasoning: small projects can afford the I/O, and bulk-group rubric scoring (3.c Verifiable) benefits from complete coverage. Large projects (sequencing runs, microscopy archives) would block on the streaming hash for too long.

Tell the user the decision before you start, framed by the actual numbers:

- **Under threshold:** *"Hashing all `<N>` files (`<H>` total; under the 1000-files / 1 GiB threshold). Roughly `<T>` at ~100 MB/s."*
- **Over threshold:** *"Hashing `<M>` distinct files (`<H>` total); skipping `<K>` bulk-group files because the project exceeds the 1000-files / 1 GiB threshold (e.g. `<example_group>` with `<k>` files). You can run `/hash-coverage` later if you want hashes on those too."*

### 3. Hash the in-scope files

For each file marked for hashing (everything when under threshold; singletons only when over), compute md5 + sha256 in **one pass via streaming hash**:

```python
import hashlib
md5 = hashlib.md5()
sha256 = hashlib.sha256()
with open(path, "rb") as f:
    while chunk := f.read(1024 * 1024):  # 1 MB
        md5.update(chunk)
        sha256.update(chunk)
return md5.hexdigest(), sha256.hexdigest()
```

Show a one-line progress update every 10 files or so (`"hashed 30/120..."`). Don't spam.

If a file is unreadable (permission denied, broken symlink), don't crash. Leave both hashes blank for that row, add a note to the run log, keep going.

### 4. Build the per-file rows

For each file (singleton or bulk):

| Column | Value |
|---|---|
| `name` | basename (e.g. `raw_counts.csv`). |
| `type` | `software` or `dataset` per Step 1's detection. The manifest connector reads this column and routes accordingly; if blank it auto-detects from extension, so explicit values are not strictly required but make the manifest self-documenting. |
| `description` | template: `"<basename> from <parent-relpath>"`. If the file's parent is the project root, use `"<basename> in project root"`. **Pad to a minimum of 10 characters** — the Dataset and Software models reject shorter descriptions. The user can edit later in the CSV before importing. |
| `contentUrl` | `file:///<relpath>` where `<relpath>` is the path relative to `project_root` with forward slashes. |
| `format` | the file's extension token (e.g. `csv`, `parquet`, `tif`, `py`). Bare extension, no leading dot. Don't invent MIME types. |
| `md5` | from the hashing pass, or blank if hashing was skipped for this file. |
| `sha256` | from the hashing pass, or blank if hashing was skipped for this file. |
| `size_bytes` | from `state.scan` (or `os.stat()` if scan is stale). |
| `datePublished` | leave blank — the connector falls back to the sidecar's `publication_date`. For software rows the connector automatically remaps this to `dateModified` on the way to `GenerateSoftware`. |
| `version` | leave blank — connector defaults to `"1.0"`. |
| `keywords` | leave blank unless the user supplied per-file keywords in state. |
| `group` | the `group_key` from `state.scan` for bulk files; blank for singletons. Reserved for future schema inference; safe to write. |

### 5. Write the sidecar

Compose `crate.json` from `state.crate_metadata`. Fields:

```json
{
  "name": "<from form>",
  "description": "<from form, augmented if hashes were skipped>",
  "authors": ["<from form>"],
  "license": "<from form, URL form preferred>",
  "keywords": ["<from form>"],
  "publication_date": "<from form, ISO date>",
  "doi": "<from form, optional>",
  "associated_publication": "<form's doi as URL, or omit>",
  "repository_name": "Local project",
  "project_id": "<slugged version of name>",
  "version": "1.0"
}
```

**If any files had hashes skipped** (the over-threshold case), append a note to `description`:

> *"Note: hashes were skipped for `<M>` bulk-group files (e.g. `<example_group_key>`) because the project exceeds the 1000-files / 1 GiB hashing threshold; run `/hash-coverage` from inside the crate to fill them in."*

This keeps the gap honest and pointer-rich.

### 6. Write the files

- `Write` to `<project_root>/manifest.csv` (CSV with header row, UTF-8 no BOM).
- `Write` to `<project_root>/crate.json` (JSON pretty-printed, 2-space indent).

### 7. Validate locally

Don't shell out to the importer. Programmatic checks only:
- Open `manifest.csv` with `csv.DictReader`; confirm required columns (`name`, `description`, `contentUrl`) are present.
- Confirm row count matches the number of in-scope files from scan.
- Confirm `crate.json` has `name`, `description`, `authors[]` populated.

### 8. State write

Update `.fairscape-state.json` (the unified state file once Step 2 lands; until then `.fairscape-remote-state.json`):

```json
{
  "phase": "manifest_built",
  "source": {
    "kind": "local",
    "project_root": "<abs>"
  },
  "history": [
    {"ts": "...", "skill": "build-local-manifest",
     "summary": "wrote <N>-row manifest + sidecar at <project_root> (M hashed, K bulk skipped)"}
  ]
}
```

### 9. Report

> *"Manifest ready at `<project_root>/manifest.csv`. `<N>` rows — `<D>` Datasets and `<S>` Software entries (detected by extension; you can override the `type` column before importing). Hashes set on `<M>` files; left blank on `<K>` files (`<reason: bulk-group skip / unreadable>`). The importer step is next — `fairscape-cli import manifest <project_root>/manifest.csv --output-dir <project_root>` — but that's the caller's job, not mine."*

## What you must NOT do

- **Don't call `fairscape-cli import manifest`.** That's the caller. Your output is the manifest + sidecar.
- **Don't interview the user.** All metadata comes from `state.crate_metadata` (form path of `extract-crate-metadata`). If state is missing fields, stop and tell the caller.
- **Don't hash bulk-group files when over the 1000-files / 1 GiB threshold.** The whole point of the threshold is to avoid 10,000-file hash storms on sequencing/imaging archives. Bulk = blank hashes + a documented gap. Under threshold, hash everything — the gap closes.
- **Don't follow symlinks outside the project root.** Use `os.path.realpath` and skip anything that escapes.
- **Don't compute hashes for files > 10 GB without warning the user first.** Streaming is correct but uninterruptible mid-file; if a huge file exists, surface it and let the user say keep / skip / cancel before starting.
- **Don't put absolute paths in `contentUrl`.** Always relative-to-project-root: `file:///data/raw.csv`, never `file:///Users/justin/.../data/raw.csv`.
- **Don't change file formats heuristically.** `csv.gz` is `csv-gz` or similar; `nii.gz` is `nii-gz`. Compound extensions stay compound. The importer's downstream consumers may care.

## Reference

- `wizards/manifest-import-design/hprc-subset/manifest.csv` — canonical column layout. Same columns; different `contentUrl` scheme (`https://` vs `file:///`).
- `wizards/manifest-import-design/hprc-subset/crate.json` — canonical sidecar shape.
- `fairscape-cli/src/fairscape_cli/models/dataset.py` lines 56-63 — the `GenerateDataset` path. Will *also* auto-compute md5 from a `file:///` contentUrl during import if the manifest left it blank, but **we don't rely on that** — we put hashes in the manifest so they're durable and visible.
