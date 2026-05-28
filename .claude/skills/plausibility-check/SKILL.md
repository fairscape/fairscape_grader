---
name: plausibility-check
description: LEGACY (used only by `fairscape-rocrate-wizard-legacy`). Validate entity-centric wizard state for graph plausibility — orphan datasets, dangling references, missing files, computations with no inputs/outputs. For the unified `fairscape-rocrate-wizard`, plausibility is enforced by the manifest format itself + `fairscape-cli rocrate validate` (the pydantic model) after import.
---

# Plausibility check

This is a pre-flight before `emit-build-script`. It catches semantic problems FAIRSCAPE's schema validator won't (orphans, dangling refs, missing files), and surfaces them as a numbered list the user can act on.

## Procedure

Read `.fairscape-wizard-state.json`. Run the checks below in order. Collect every failure into a numbered list with a one-line "what" and "fix suggestion". Do not modify state.

### Check 1 — Every output dataset has a producing computation
For each dataset in `state.datasets` where `is_raw_input == false`: confirm at least one `state.computations[*].generated` (or `generated_bulk_groups` for bulk) references its GUID.
Same check for bulk_groups with `is_raw_input == false`.

**Failure**: "Dataset 'cleaned.csv' is marked as a non-raw output but no step generates it."
**Fix**: "Run `create-computation` and add it as an output, or mark it as a raw input."

### Check 2 — Every computation has at least one input and one output
For each `state.computations` entry: `usedDataset + used_bulk_groups + usedSoftware` non-empty AND `generated + generated_bulk_groups` non-empty.

**Failure**: "Step 'Clean raw' has no outputs registered."

### Check 3 — Every referenced GUID exists
For every GUID in any `usedSoftware / usedDataset / generated`, confirm it appears in `state.software` or `state.datasets`.
For every `guid_prefix` in `used_bulk_groups / generated_bulk_groups`, confirm it appears in `state.bulk_groups`.

**Failure**: "Step 'Train' references software GUID `ark:59853/software-old-py-...` that no longer exists in state."

### Check 4 — contentUrl files exist on disk
For every `state.datasets` and `state.software` entry: if `contentUrl` starts with `file:///`, resolve it relative to `project_root` and confirm the file exists. Skip `Embargoed` and `http(s)://`.
For every `state.bulk_groups`: re-evaluate the glob and confirm at least one file matches.

**Failure**: "File `processed/cleaned.csv` referenced by dataset 'Cleaned data' does not exist."
**Fix**: Move the file into the project, or update the contentUrl to where it actually lives.

### Check 5 — Bulk group glob still matches its snapshot
For each `state.bulk_groups`: re-evaluate the glob. If the new file count differs from `len(snapshot_files)` by >10%, flag it (might be expected — files added since registration — or might be a moved directory).

**Warning** (not failure): "Bulk group 'raw microscopy images' snapshotted 847 files; glob now matches 920. The build script will use whatever's there at run time."

### Check 6 — Crate metadata sanity
- `state.crate_metadata.name` non-empty.
- `state.crate_metadata.description` ≥ 20 chars.
- `state.crate_metadata.authors` non-empty.

### Check 7 — All branches closed
If `state.branches` is present and non-empty: every branch must have `status` of `"complete"` or `"merged"`. Any `"open"` branch is a forgotten pipeline.

**Failure**: "Branch 'clinical' is still open (head: `processed_features.csv`). Did this branch produce a final output, or merge into another branch?"
**Fix**: Walk the branch to its end via the wizard's pipeline interview, or — if it really stops here — confirm and mark complete.

## How to run the checks

Either write a short inline Python via `Bash python -c '...'` that loads the JSON and runs the checks, or do it directly by reading the JSON file and reasoning through it. For the file-existence check, `Bash test -f <path>` or `Read` is fine.

## Report format

```
Plausibility check on .fairscape-wizard-state.json:

Issues:
  1. [missing file] dataset 'Cleaned data' points at processed/cleaned.csv but no such file exists.
     Fix: move the file into the project, or update its location.
  2. [orphan output] bulk group 'segmentation masks' is marked as a step output but no step generates it.
     Fix: register the step that produced these.

Warnings:
  - bulk group 'raw images' snapshotted 847 files; glob now matches 920.

If you're OK with all of this, say 'continue' and I'll write the build script.
```

If there are zero issues and zero warnings, just say `Plausibility check: clean. Ready to emit the build script.`
