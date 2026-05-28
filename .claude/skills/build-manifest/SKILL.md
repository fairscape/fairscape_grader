---
name: build-manifest
description: Build a generic-import manifest (manifest.csv + crate.json) for a published dataset that doesn't have a dedicated repository connector (i.e. is not Dataverse, PhysioNet, or Figshare). Researches the dataset's published file inventory, rewrites cloud URIs to anonymously-fetchable HTTPS, pulls real hashes/sizes where the source publishes them, leaves them blank where it doesn't, composes per-file descriptions, and writes a sidecar with crate-level metadata from the paper. Output is the input to `fairscape-cli import manifest`. Does NOT call the importer.
---

# Build a generic-import manifest

You produce **two files in a fresh folder**:

```
<workdir>/<slug>/
  manifest.csv     # one row per file (name, description, contentUrl, [md5, sha256, size_bytes, ...])
  crate.json       # sidecar with title, authors, doi, license, publication date, keywords
```

That folder is the input to `fairscape-cli import manifest <manifest.csv> --output-dir <crate_dir>`. **Do not run the importer here** — your job ends when the two files are on disk and validated.

The manifest format is documented in `wizards/manifest-import-design/DESIGN.md`. A working reference example lives at `wizards/manifest-import-design/hprc-subset/` (HPRC year-1 phased assemblies, 6 files). Read both before drafting.

## When you're invoked

The expected caller is **`remote-import`** (Phase 1 of `fairscape-remote-rocrate-wizard`), which routes here automatically when the user's paste isn't a Dataverse DOI, PhysioNet URL, or Figshare article. You can also be invoked directly by a user who already knows they want a manifest for an arbitrary source.

Either way, your output (`manifest.csv` + `crate.json`) is the input to `fairscape-cli import manifest`. The caller runs that — not you.

Cues that you're the right skill:

- The data is in an **AWS / GCP open-data bucket** (`s3://`, `gs://`).
- The data is on **NCBI GenBank / SRA / GEO**, **ProteomeXchange**, **cellxgene**, **OpenNeuro**, **Mendeley Data**, or any portal without a dedicated `fairscape-cli import <kind>` subcommand.
- The user has a **paper + a vague "data is at this URL"** but no fetcher will work.
- The user has a **list of files on hand** (TSV/CSV/spreadsheet) and just wants those wrapped as a crate.

If the data is on Dataverse, PhysioNet, or Figshare, **stop and tell the user** to use `fairscape-cli import <kind>` directly — those importers do this for free.

## What the orchestrator (or user) passes you

A free-form brief is fine — accept any of:

- A paper DOI (`10.1038/s41586-023-05896-x`) or URL.
- A repository URL (`https://github.com/human-pangenomics/HPP_Year1_Assemblies`).
- A "data is at <URL>" pointer with no further structure.
- A paper PDF on disk.
- A pre-existing inventory file (TSV/CSV/JSON) the user already has.
- A working directory where the output should land (default: `./<slug>/` under pwd).

If too little is given, ask one focused question to fill the biggest gap. Don't interrogate — three rounds max.

## Phase A — Identify the inventory source

Before writing anything, **find the file inventory**. In order of preference:

1. **Pre-existing inventory the user already has.** If they hand you a TSV/CSV/JSON file listing the data files, use that — don't re-derive.
2. **A "release manifest" or "index" file published with the dataset.** Look on the dataset's GitHub repo (`assembly_index/`, `manifests/`, `releases/`), the paper's supplementary data, or a sibling `files.tsv` next to the data.
3. **A listing API.** S3 buckets without `ListBucket` denial expose `?list-type=2`; GitHub releases expose `/releases/<id>` JSON; NCBI gives FTP listings.
4. **The paper's Data Availability section.** Sometimes the manifest is literally a table in supplementary materials.
5. **As a last resort**, walk the user through what files they want included (one-by-one). Only do this when nothing else turned up — it's expensive and error-prone.

`WebFetch` and `WebSearch` are your friends here. Don't guess inventory URLs — verify by fetching first.

Once you have the inventory in hand, tell the user what you found:

> *"Found the file inventory at `<url>`. It lists `<N>` files across `<K>` groups (e.g. samples / haplotypes / runs). Columns published: `<col list>`. Notably, the source publishes `<sha256 | md5 | nothing>` for hashes and `<does | doesn't>` include sizes."*

## Phase B — Scope

Ask the user whether to include everything or a subset. Phrase the trade-off:

> *"The inventory has `<N>` files totaling roughly `<size>`. The crate will reference all of them by URL — no data downloads — but each becomes a Dataset entry in `@graph`, which can get noisy for very large inventories. Want all `<N>`, or a subset (and if so, which axis to filter on — first K samples, specific cohort, single haplotype)?"*

For datasets > a few hundred files, default to suggesting a representative subset for the first crate, and tell them they can re-run with the full inventory once they've eyeballed the result.

## Phase C — Per-file row build

For each file in scope, populate the row:

### `name`
The basename of the file (`HG00438.paternal.f1_assembly_v2_genbank.fa.gz`). Not the full URL.

### `description`
A short, templated description that reads naturally. Most inventories give you 2–3 axis values (sample × haplotype, run × condition, donor × organ). Compose like:

> *"Phased diploid assembly (paternal haplotype) for HPRC sample HG00438; year-1 v2 GenBank release."*

If the inventory has a per-file `description` column, use it verbatim. Don't make up details that aren't in the source — vague but truthful beats specific but invented.

### `contentUrl` — rewriting cloud URIs

The crate's downstream consumers (datasheet, validator) currently assume `http(s)://`. Rewrite the inventory's URI:

| Inventory has | Rewrite to |
|---|---|
| `s3://<bucket>/<key>` (public AWS Open Data) | `https://<bucket>.s3.amazonaws.com/<key>` |
| `gs://<bucket>/<key>` (public GCS) | `https://storage.googleapis.com/<bucket>/<key>` |
| `ftp://<host>/<path>` | Leave as-is OR switch to `https://<host>/<path>` if the host serves both. |
| `<github>/blob/<sha>/<path>` | `<github>/raw/<sha>/<path>` |

For private/auth'd buckets — stop. The manifest path is for openly-accessible data. Tell the user we don't support tokens here in v1.

**Verify one URL is reachable** before continuing — pick a representative file and `curl -sI` it. If you get HTTP 200, the rest of the bucket is probably fine. If you get 403/404, the URL pattern is wrong; debug.

### `md5` / `sha256`

Pull from the inventory if published. **Never download to compute.** If only one is published, fill that column and leave the other blank — fairscape's `Dataset` model accepts either. If neither is published, leave both blank; the user can run `/hash-coverage` later for any files they're willing to download locally.

When hashes are blank, **note it in the sidecar** (see Phase D) so the gap is documented rather than silent.

### `size_bytes`

Prefer the inventory's published byte count. If absent, `curl -sI <url> | grep -i ^content-length:` per file. For inventories > 50 files, batch the HEAD requests:

```bash
for url in <urls>; do
  size=$(curl -sI "$url" | awk 'BEGIN{IGNORECASE=1} /^Content-Length:/ {gsub(/[\r\n]/,"",$2); print $2; exit}')
  echo "$url,$size"
done
```

The manifest's `_human_size()` helper (in `manifest_connector.py`) formats `size_bytes` into the human-readable `contentSize` string ("833.8 MB") on the way to the crate, so the CSV only carries the integer.

### `format`

If the inventory publishes a MIME type, use it. Otherwise leave blank — the connector falls back to the filename extension. Don't invent MIME types you're not sure about (`application/x-bgzip` is wrong for `.fa.gz`; it's just `fasta-gz` if anything).

### `keywords` (optional, pipe-separated)

Per-file keywords that meaningfully narrow the file beyond what the crate-level `keywords` already cover. Skip if the file is generic.

### `group` (optional)

Free-form label for files that share a structure (e.g. `"paternal-haplotype-fasta"`, `"per-sample-vcf"`). Reserved for future schema-inference grouping — write it now, it'll light up later for free.

### `type` (optional)

`dataset` (default) or `software`. The manifest connector reads this column and routes the row to either `GenerateDataset` → `fairscape_models.dataset.Dataset` or `GenerateSoftware` → `fairscape_models.software.Software`. If blank, the connector auto-detects from extension: `.py .r .sh .bash .ipynb .jl .m .exe .java .cpp .js .jsx .ts .tsx .css` → `software`; everything else → `dataset`.

For most remote published datasets the source's file inventory is purely data, so the column is rarely needed. Set it explicitly when the source ships scripts you want to surface as Software (e.g. analysis code published alongside the data).

## Phase D — Sidecar (crate.json)

Pull from the paper (DOI lookup, PDF read) and the dataset's GitHub repo:

| Field | Required? | Notes |
|---|---|---|
| `name` | yes | Paper title or dataset title. Add "(subset)" if scope is partial. |
| `description` | yes | One paragraph. Pull from paper abstract or repo README. |
| `authors` | yes | Full author list from the paper. Order matters. Don't truncate. |
| `license` | strongly recommended | URL form (`https://creativecommons.org/...`). Look at the data repo, not the paper's CC-BY — those are often different. |
| `keywords` | recommended | 4–8 short terms grounded in the domain. |
| `publication_date` | recommended | ISO date of the paper. |
| `doi` | recommended | Bare DOI (`10.1038/...`), not the URL form. |
| `associated_publication` | recommended | URL form of the DOI. |
| `repository_name` | recommended | Free text — "HPRC (AWS Open Data)", "NCBI GenBank", "Zenodo (record 12345)". Not a URL. |
| `project_id` | recommended | A short slug or accession the source uses. |
| `version` | optional | Release version, defaults to "1.0". |
| `url` | optional | A canonical landing URL for the dataset (the GitHub repo, the portal page, etc.). |

If hashes were blank for some rows in Phase C, **add a free-text note** to `description`: *"Note: file hashes are not published by the source repository; `/hash-coverage` can populate them later for files downloaded locally."* This keeps the gap documented inside the crate itself.

## Phase E — Write + spot-check

1. `Write` `manifest.csv` and `crate.json` to `<workdir>/<slug>/`.
2. **Validate locally — don't shell out to the importer.** Programmatic checks:
   - `csv.DictReader` opens cleanly.
   - Required columns present: `name`, `description`, `contentUrl`.
   - At least one row.
   - First row's `contentUrl` returns HTTP 200 on HEAD.
   - Sidecar has `name`, `description`, `authors` (a list).
3. **Spot-check one URL by sampling.** `curl -r 0-1023 <one_url>` — pulls 1 KB. Confirms not only reachability but that the bytes are real (not a 200-but-empty redirect page).

## Phase F — Report

Print a short summary the user can act on:

> *"Manifest ready at `<workdir>/<slug>/`. `<N>` files referenced; total declared size `<H>` (computed from `size_bytes`). Hashes: `<K>` rows have sha256, `<L>` have md5, `<M>` have neither. Run `fairscape-cli import manifest <workdir>/<slug>/manifest.csv --output-dir <crate_dir>` to build the crate. The remote-source wizard's phases 2–6 (schema infer, AI-Ready enrich, provenance, grade, improve) work against the resulting crate unchanged."*

## What you must NOT do

- **Don't call `fairscape-cli import manifest`.** Your output is the manifest + sidecar. The caller decides when to build.
- **Don't download data files to compute hashes.** HEAD is fine; GET is not. If hashes aren't published, leave blank and document.
- **Don't invent metadata.** Per-file descriptions can be templated, but the *facts* in them (sample IDs, conditions, file types) must come from the inventory, not your imagination. If you don't know, say "data file" and move on.
- **Don't include private/auth'd URLs.** If a row would require a token, the row doesn't belong in the manifest — it belongs in a Dataset with `contentUrl: "Embargoed"` placeholder, added later via `register-embargoed-dataset`.
- **Don't try to be smart about cloud URI rewrites you haven't verified.** If a bucket isn't documented as public, HEAD it to confirm `200 OK` *before* writing the URL into the manifest.
- **Don't write `MEMORY.md`-style "this is a great dataset" commentary into the sidecar.** Stick to factual fields.

## Reference: the HPRC test case

`wizards/manifest-import-design/hprc-subset/` is the canonical worked example. When in doubt, mirror its shape:

- 6 rows (3 samples × 2 haplotypes).
- `contentUrl`s rewritten from `s3://human-pangenomics/...` to `https://human-pangenomics.s3.amazonaws.com/...`.
- `sha256` pulled verbatim from `Year1_assemblies_v2_genbank.index`; `md5` blank because HPRC doesn't publish md5.
- `size_bytes` from HTTP HEAD against each public URL.
- `crate.json` has 119 authors copied from the Liao 2023 Nature paper, CC0 license matching HPRC's open-data terms, DOI `10.1038/s41586-023-05896-x`, publication date `2023-05-10`.

That manifest produced a crate that validates as `ROCrate v1.2` and has every per-file Dataset carrying `contentUrl`, `sha256`, and `contentSize`.
