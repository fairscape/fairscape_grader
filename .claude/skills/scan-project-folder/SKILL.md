---
name: scan-project-folder
description: Inventory the project directory by file category (scripts, data, docs, PDFs, other), detect bulk-group siblings (≥10 same-extension files in one directory), and write the result into the unified state file under `scan`. Skips the standard noise directories.
---

# Scan project folder

Walk the project root, categorize every file, detect bulk groups, and persist a structured inventory to the wizard state file (`.fairscape-state.json` once Step 2 of the unification lands; until then `.fairscape-wizard-state.json`).

## Procedure

1. Read the state file (create if missing) and identify `project_root`. If absent, use `pwd`.
2. Use `Glob` (or `Bash find`) to list all files under the root, **skipping** these directory names anywhere in the path:
   - `.git`, `__pycache__`, `.ipynb_checkpoints`, `node_modules`, `.venv`, `venv`, `.env`, `env`, `.tox`, `.mypy_cache`, `ro-crate`
3. Skip these filenames: `.DS_Store`, `Thumbs.db`, `.gitignore`, `.gitkeep`.
4. Also skip the unified-wizard's own working files at the project root: `manifest.csv`, `crate.json`, `ro-crate-metadata.json`, `.fairscape-state.json`, `.fairscape-wizard-state.json`, `.fairscape-remote-state.json`, `build_rocrate.sh`, `build_rocrate.py`. (Special-case ro-crate-metadata.json: if it exists, record its path in `scan.existing_crate` before skipping.)
5. Categorize each remaining file by extension using the table below. Compound extension `.nii.gz` counts as `.nii.gz`.
6. **Bulk-group detection.** Group files by `(parent_directory, extension)`. Any group with **≥ 10 members** is a bulk group. The threshold is set at 10 (not 3 or 4) because small clusters of same-extension files — four sibling Python scripts, three CSVs with different contents — are usually distinct work, not a bulk pattern; treating them as bulk would obscure them in the crate. Construct a stable `group_key` per group: `"<relative-parent-dir>/*.<ext>"` (e.g. `"raw/*.tif"`, `"data/per-sample/*.csv"`; use `"*.tif"` for files in the project root). Annotate each file in a bulk group with that `group_key`; singletons get `group_key: null`.
7. For each file record: relative path (from project root), size in bytes, extension, category, `group_key`.
8. Write back to state under `scan`:
   ```json
   "scan": {
     "scanned_at": "2026-05-04T12:00:00Z",
     "files_by_category": {
       "scripts": [...], "data": [...], "docs": [...], "pdfs": [...], "other": [...]
     },
     "bulk_groups": {
       "raw/*.tif": {"member_count": 847, "total_bytes": 3221225472, "category": "data"},
       "data/per-sample/*.csv": {"member_count": 50, "total_bytes": 12345678, "category": "data"}
     },
     "existing_crate": null
   }
   ```
   Each entry in `files_by_category[*]` carries `{relpath, size_bytes, extension, group_key}`. The top-level `bulk_groups` block is a summary index `build-local-manifest` reads to decide which files to skip-hash.
9. Return a short human summary: "scanned N files: 847 data, 3 scripts, 1 PDF, 12 other under processed/; detected K bulk groups (e.g. raw/*.tif with 847 files)".

## Extension → category table

| Category | Extensions |
|---|---|
| script | `.py .r .R .sh .bash .ipynb .jl .m` |
| pdf | `.pdf` |
| doc | `.md .rst .tex .docx .rtf` |
| data | `.csv .tsv .txt .json .jsonl .ndjson .h5 .hdf5 .hdf .nc .netcdf .parquet .arrow .feather .orc .avro .fastq .fq .fasta .fa .bam .sam .vcf .bcf .bed .gff .gtf .wav .mp3 .flac .ogg .m4a .png .jpg .jpeg .tiff .tif .bmp .svg .dcm .nii .nii.gz .mat .npy .npz .pkl .pickle .db .sqlite .sqlite3 .lmdb .mdb .xml .yaml .yml .toml .zip .tar .gz .bz2 .xz .7z .xls .xlsx .ods .d` |
| other | anything else |

(`.pdf` appears in `data` historically but should be reported as `pdf` here — pdf check wins.)

## Display rules for the caller

- If total files ≤ 200, show a numbered list when asked.
- If > 200, show a directory-grouped summary (e.g. "raw/: 847 .tif files; processed/: 12 .csv files") instead of a per-file list.
- Always lead with totals by category, not the full list.
