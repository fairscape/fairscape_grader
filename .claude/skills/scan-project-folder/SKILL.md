---
name: scan-project-folder
description: Inventory the project directory by file category (scripts, data, docs, PDFs, other) and write the result into .fairscape-wizard-state.json under `scan`. Skips the standard noise directories.
---

# Scan project folder

Walk the project root, categorize every file, and persist a structured inventory to `.fairscape-wizard-state.json`.

## Procedure

1. Read `.fairscape-wizard-state.json` (create if missing) and identify `project_root`. If absent, use `pwd`.
2. Use `Glob` (or `Bash find`) to list all files under the root, **skipping** these directory names anywhere in the path:
   - `.git`, `__pycache__`, `.ipynb_checkpoints`, `node_modules`, `.venv`, `venv`, `.env`, `env`, `.tox`, `.mypy_cache`, `ro-crate`
3. Skip these filenames: `.DS_Store`, `Thumbs.db`, `.gitignore`, `.gitkeep`.
4. Special-case: if `ro-crate-metadata.json` exists, record its path in `scan.existing_crate` and do NOT include it in the categorized lists.
5. Categorize each remaining file by extension using the table below. Compound extension `.nii.gz` counts as `.nii.gz`.
6. For each file record: relative path (from project root), size in bytes, extension, category.
7. Write back to state under `scan`:
   ```json
   "scan": {
     "scanned_at": "2026-05-04T12:00:00Z",
     "files_by_category": {
       "scripts": [...], "data": [...], "docs": [...], "pdfs": [...], "other": [...]
     },
     "existing_crate": null
   }
   ```
8. Return a short human summary: "scanned N files: 847 data, 3 scripts, 1 PDF, 12 other under processed/".

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
