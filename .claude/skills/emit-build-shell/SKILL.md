---
name: emit-build-shell
description: Write a `build_rocrate.sh` shell script alongside the crate that rebuilds the import step from `manifest.csv`. Invoked at the unified wizard's "Done" step. The script is the durable, re-runnable, human-readable artifact for the import phase; Phase 2+ enrichments are re-applied by re-running the wizard against the saved state file. Works for any source kind (local, dataverse, physionet, figshare, generic-remote-manifest).
---

# Emit `build_rocrate.sh`

The unified wizard's reproducibility win is a 3-line shell script next to the crate. Anyone with `fairscape-cli` installed can re-run it and reproduce the import step from `manifest.csv`. Post-import enrichments (schemas, RAI fields, provenance, grading) are re-applied by re-running the wizard against the saved state file.

## When you're invoked

At the end of the unified `fairscape-rocrate-wizard` flow — after Phase 5 (grading) and any Phase 6 (improvements). Also user-callable directly: `/emit-build-shell` regenerates the script from the current state.

## Prerequisites

The crate must have been produced via the manifest path. That means **either**:
- The wizard's local-folder branch (state.source.kind = `local`; `manifest.csv` + `crate.json` are in `state.source.project_root`); OR
- The wizard's manifest fallback (state.source.kind = `manifest`; files are in `state.source.manifest_dir`).

For Dataverse / PhysioNet / Figshare imports (state.source.kind = one of those), the originals are the API call itself — no manifest exists. In that case, emit a different script (see below) that re-runs the dedicated importer.

## Procedure

### Case A — manifest exists (local or manifest)

Pick the manifest directory:
- `local` → `state.source.project_root` (manifest.csv + crate.json sit in there)
- `manifest` → `state.source.manifest_dir`

Pick the crate output dir:
- `local` → `state.source.project_root` (crate IS the project root)
- `manifest` → `state.crate_dir`

Write `<crate_dir>/build_rocrate.sh`:

```sh
#!/usr/bin/env bash
# Rebuilds the import phase of this RO-Crate from manifest.csv.
# Phase 2+ enrichments (schemas, AI-Ready, provenance, grading) are re-runnable
# by invoking `fairscape-rocrate-wizard` in this folder — the wizard reads the
# saved .fairscape-state.json and resumes from the appropriate phase.
set -euo pipefail
cd "$(dirname "$0")"
MANIFEST="${1:-./manifest.csv}"
OUTPUT_DIR="${2:-.}"
fairscape-cli import manifest "$MANIFEST" --output-dir "$OUTPUT_DIR"
```

Then `chmod +x <crate_dir>/build_rocrate.sh`.

### Case B — dedicated importer (dataverse / physionet / figshare)

There's no manifest to wrap. Emit a script that re-runs the original CLI invocation. Look up the source kind and identifier from state:

```sh
#!/usr/bin/env bash
# Rebuilds the import phase of this RO-Crate by re-running the dedicated importer.
set -euo pipefail
cd "$(dirname "$0")"
fairscape-cli import <kind> <identifier> --output-dir . [--server-url <url> for dataverse]
```

Substitute `<kind>` and `<identifier>` from `state.source.kind` and `state.source.url_or_doi`. For Dataverse with a non-default server, append `--server-url <state.source.server_url>`.

## Validate before writing

Open the manifest path (Case A) and confirm:
- `manifest.csv` exists and has at least one data row.
- `crate.json` exists with `name`, `description`, `authors`.

For Case B, confirm `state.source.url_or_doi` is set.

If validation fails, surface the missing field and abort — don't write a script that won't work.

## State write

Append to `state.history`:
```json
{"ts": "...", "skill": "emit-build-shell",
 "summary": "wrote build_rocrate.sh at <crate_dir>; case=<A|B>"}
```

No phase change — this skill is post-phase-6 wrap-up, not its own phase.

## Tell the user what they got

After writing:

> *"Wrote `<crate_dir>/build_rocrate.sh`. Anyone with `fairscape-cli` installed can `cd <crate_dir> && ./build_rocrate.sh` to reproduce the import step. Schemas, AI-Ready fields, provenance, and grading are re-applied by running `/fairscape-rocrate-wizard` in this folder — it picks up `.fairscape-state.json` and resumes from the right phase."*

## What you must NOT do

- Don't emit a Python script (`build_rocrate.py`). That was the legacy wizard's path and it duplicates `ResearchData.to_rocrate()` logic. The 3-line shell script that defers to `fairscape-cli` is shorter and stays correct even when the importer evolves.
- Don't bake absolute paths into the script. Use `$(dirname "$0")` so the script works wherever the crate lands.
- Don't try to script the post-import phases. They depend on the wizard state and may require re-asking the user (RAI, provenance). Tell the user to re-run the wizard for those.
- Don't run the script you just wrote. Emit it; the user runs it.
