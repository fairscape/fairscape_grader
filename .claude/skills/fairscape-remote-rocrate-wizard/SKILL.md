---
name: fairscape-remote-rocrate-wizard
description: Build a FAIRSCAPE RO-Crate from a public Dataverse DOI or PhysioNet URL, without downloading the data. Drives a 5-phase flow — import → remote schema inference → AI-Ready enrichment from a paper → provenance tracking (computations + link-inverses, with embargoed placeholders for missing raw inputs) → agentic rubric grading. Delegates to remote-import, remote-schema-infer, remote-ai-ready-enrich, remote-provenance-tracking, register-embargoed-dataset, agentic-rescore, and remote-checkpoint.
---

# FAIRSCAPE Remote-Source RO-Crate Wizard

This wizard is **separate from** `fairscape-rocrate-wizard`. That one interviews users about a local project folder and emits a `build_rocrate.py`. This one takes a dataset that's *already published* on Dataverse or PhysioNet, builds an RO-Crate whose `contentUrl`s point at the remote files, enriches it with paper-derived RAI metadata, and grades it. The two wizards have separate state files and never read each other's.

## User-facing rules

1. **Vocabulary**: never say "entity", "ARK", "@id", "extractor", "rubric inputs" — say "the crate", "the file list", "the score". Translate the model behind the scenes.
2. **One question at a time.** Don't interrogate.
3. **Explain before you do.** Before any non-trivial action — a shell command, a CLI invocation, a write to the crate — say in 1–2 sentences what's about to happen and *why*. Example: *"I'll call `fairscape-cli import dataverse` next. That CLI talks to the Dataverse API, pulls the dataset's metadata (title, authors, file list, DOI), and writes a starter `ro-crate-metadata.json` into the output folder. The actual data files stay on Dataverse — we just record where to find them."* The user should never see a command without knowing its goal.
4. **Show progress at phase boundaries.** When a phase finishes, summarize what the user now has on disk and what the next phase will do. Not "phase 1 done" — give them: *"Phase 1 done. You now have `./<slug>-rocrate/ro-crate-metadata.json` listing 3,855 files with their Dataverse URLs and the dataset-level metadata Dataverse provided. Next I'll sample a representative of each file group to figure out the column structure."*
5. **Persist after every phase** to `.fairscape-remote-state.json`. The user must be able to quit anywhere and resume — tell them this once, at the start.
6. **Public datasets only** in this version. If the user pastes a private DOI, tell them token support isn't here yet.

## Conversation flow

### 1. Open

`Bash pwd` to confirm the working directory.

Check for `.fairscape-remote-state.json`:
- **Exists** → invoke `remote-checkpoint`. Ask: **"Resume from `<phase>`, or start over?"** On "start over", confirm before deleting state, then proceed to phase 1.
- **Doesn't exist** → give the user a real intro, not a one-liner:

  > *"I'll build an RO-Crate — a structured folder of metadata about a published dataset — by pulling everything I can from a public Dataverse or PhysioNet record. The data files themselves stay on the repository's servers; we just record their URLs and describe them.*
  >
  > *We'll go through five phases:*
  > *1. **Import.** Pull dataset-level metadata (title, authors, DOI, file list) from the repository's API and write the starter `ro-crate-metadata.json`.*
  > *2. **Schemas.** Group the tabular files by name pattern, sample one representative per group, and infer column names + types so the crate describes what's in each file.*
  > *3. **AI-Ready enrichment** (optional). If you have a paper describing the dataset, I'll read it and add the fields that make the crate AI-Ready — biases, limitations, collection methods, intended use cases, license/access details. Most of these live in the MLCommons RAI vocabulary (the `rai:*` field prefix); the bucket also includes standard descriptors like `license` and `conditionsOfAccess`.*
  > *4. **Provenance tracking** (optional). Document the pipeline that produced the derived files — for each step, what software ran (ideally a GitHub or Zenodo link), which datasets it consumed, which datasets it produced. We then run a tool that fills in the reverse links so every output points back at the step that made it.*
  > *5. **Grading** (optional). Score the crate against the 28-rubric AI-Ready checklist so you see where it's strong and where there are gaps.*
  >
  > *I save my progress after every step to `.fairscape-remote-state.json` in this folder — quit anytime, run me again with the same command and I'll pick up where we left off."*

  Then proceed.

### 2. Phase 1 — Import

Frame the phase first:

> *"**Phase 1 — Import.** I'll ask for a public link to your dataset and then call `fairscape-cli import` to pull what the repository already knows about it (name, authors, file list, DOI, publication date, license). That tool talks to the Dataverse or PhysioNet API and writes a starter `ro-crate-metadata.json` in an output folder. No data files get downloaded — each file's `contentUrl` will point back at the repository so anyone consuming the crate fetches the bytes from there."*

Then ask:

> *"Paste a Dataverse DOI like `doi:10.7910/DVN/XYZ`, or a PhysioNet URL like `https://physionet.org/content/<id>/<version>/`."*

Once you have it, invoke `remote-import`. After it finishes, summarize plainly for the user — not as a status line:

> *"Imported. Your starter crate is at `<crate_dir>/ro-crate-metadata.json`. It lists **3,855 files** with their Dataverse URLs and has the dataset-level metadata Dataverse provided (title, authors, DOI `<doi>`, version `<v>`). I categorized **3,840 as parquet, 12 csv, 3 tsv, 8 csv.gz** — the gzipped ones I'll skip when inferring schemas because the schema tool doesn't read gzip. State saved to `.fairscape-remote-state.json`."*

### 3. Phase 2 — Schemas

Frame the phase first:

> *"**Phase 2 — Schemas.** Right now the crate knows the files exist but not what's *in* them. I'll look at the file names and propose groups of files that probably share a structure (e.g. 3,840 per-patient parquets that all have the same columns). You confirm or revise the grouping. For each group I sample ONE file — Range-GET for text, full download for parquet/hdf5 — and run `fairscape-cli schema infer` to detect column names and types. The resulting schema is then linked to every Dataset entry in the group via `evi:Schema`, so the crate documents what every file looks like without me re-querying 3,840 of them."*

Then invoke `remote-schema-infer`. If `state.tabular_files` is empty, tell the user "no tabular files to infer schemas for — skipping phase 2" and bump phase.

After it finishes, summarize:

> *"Schemas done. I added `<K>` schemas (one per group), with `<M>` total Dataset entries pointing at them. The schema JSONs are at `<crate_dir>/schemas/` and the sampled raw data sits in `<crate_dir>/.cache/samples/` (gitignored). State saved."*

### 4. Phase 3 — AI-Ready enrichment

Frame the phase first:

> *"**Phase 3 — AI-Ready enrichment.** This is the optional but valuable step. We're going to fill in the fields that make the crate **AI-Ready** — the context a downstream model trainer needs before using the data. Most of these live in the MLCommons RAI vocabulary (`rai:dataCollection`, `rai:dataBiases`, `rai:dataLimitations`, `rai:dataUseCases`, ethics/maintenance fields), but the same step also fills in standard descriptors the importer may have missed (`license`, `conditionsOfAccess`, `copyrightNotice`, `associatedPublication`). The repository's API usually doesn't have any of this — but the paper that describes the dataset usually does. If you have a paper PDF (or URL), I'll read it and extract those fields, then merge them into the crate's root entry. I won't overwrite anything the importer already set — only fill in nulls and extend lists."*

Then ask:

> *"Got a paper? Give me a local path, a URL, or say 'skip' and we'll move on."*

Invoke `remote-ai-ready-enrich` with the user's answer. After it finishes, summarize:

> *"Merged `<N>` AI-Ready fields from `<paper>` — `<K>` RAI fields (e.g. `rai:dataCollection`, `rai:dataBiases` with 4 items, `rai:dataLimitations` with 3, `rai:dataUseCases` with 5) plus `<S>` standard descriptors (`license`, `conditionsOfAccess`, …). The full extracted dict is in state under `state.ai_ready` if you want to review or edit before grading."*

### 5. Phase 4 — Provenance Tracking (optional)

Frame the phase first:

> *"**Phase 4 — Provenance Tracking.** Right now the crate lists your files but doesn't connect them — there's no record of which file is a raw input and which was produced by some computation. This phase captures the pipeline: for each computational step, I'll ask what software ran (ideally a GitHub or Zenodo link so it stays reachable), which datasets it consumed, and which datasets it produced. The key thing is we're documenting **steps**, not files — if the same script ran over 50 inputs to produce 50 outputs, that's **one step** with 50 inputs and 50 outputs, not 50 steps. If a step's raw input isn't in the crate (sensitive PHI, temporary recording, file too large to host), I'll add a placeholder Dataset with `contentUrl: \"Embargoed\"` so the chain still has something to link — that path runs through a sub-skill called `register-embargoed-dataset`. When the user-facing half is done, I'll run `fairscape-cli augment link-inverses` to fill in the reverse direction automatically (so every output gets a `generatedBy` pointer back at the step). The Provenance criterion in grading will then have entities to score against."*

Then invoke `remote-provenance-tracking`. The skill asks the user whether to register provenance at all — if they skip, state advances to `provenance_tracked` with `skipped: true` and grading proceeds normally.

After it finishes, summarize:

> *"Provenance done. Recorded `<N>` computations and `<M>` software entries; ran `link-inverses` so every output dataset now has a `generatedBy` link back at the step that produced it. State saved."*

### 5.5 Build the datasheet (auto, before grading)

Not a phase — no user input. Before grading runs, the crate needs a sibling `ro-crate-datasheet.html`: rubric 3.a (Data Documentation) checks for that file by name (`extract.py: find_datasheet_file`), and its absence caps the 3.a score at 0/2 regardless of how well-populated the metadata is. The build also emits `ro-crate-linkml.yaml` as a side effect.

Tell the user one sentence, then run the command — don't prompt:

> *"Quick auto-step before grading: I'll generate an HTML rendering of the crate so it's shareable as a single page and the grader can find it. No input needed."*

Then:

```bash
fairscape-cli build datasheet "<state.crate_dir>"
```

On success, write `state.datasheet_built_at = <iso utc now>`, append a one-line `history` entry (`"Built ro-crate-datasheet.html"`), and continue to Phase 5. Do not advance `state.phase` — the datasheet build is gating, not a phase.

On failure, surface stderr and stop. Do not proceed to grading — rubric 3.a will misreport without the file. Most failures are missing template assets or a malformed crate; the user can usually fix and retry. Offer to re-run after they fix the underlying issue.

Run the build *every time* you enter Phase 5, even on resume — Phase 4 may have appended Computations and embargoed placeholders since the last build, and the datasheet should reflect them. The command is idempotent; re-running overwrites the HTML and LinkML in place.

### 6. Phase 5 — Grading (optional)

Frame the phase first:

> *"**Phase 5 — Grading.** Now we measure how complete the crate is against the 28-rubric AI-Ready checklist. The rubrics live in `rubrics/ai-ready/` and cover seven criteria: FAIRness, Provenance, Characterization, Pre-model Explainability, Ethics, Sustainability, Computability. The flow is two-step: first I run a deterministic extractor (`extract.py`) that walks the crate and dumps the relevant evidence per rubric — no LLM involved, just structured reading. Then I (Claude) read each rubric's scoring rules and the extracted evidence and give it a 0 (Absent), 1 (Partial), or 2 (Substantive), with a rationale and a list of gaps that would raise the score. The result is a per-rubric folder of `score.json` files plus an `aggregated_score.json` with the total."*

Then ask:

> *"Score all 28 now, or just one criterion (0–6) — say 'all', a digit, or 'skip'?"*

Three answers:
- **All 28** → invoke `agentic-rescore` with no filter.
- **One criterion (digit)** → invoke `agentic-rescore` with that prefix.
- **Skip** → leave `state.phase = "provenance_tracked"` and tell them they can run `/agentic-rescore` later from anywhere with this state file.

When grading finishes, `state.phase = "graded"`. Surface the per-criterion rollup with one-line interpretation, e.g. *"FAIRness 6/8 — strong on findability and accessibility; the gap is around interoperable namespace coverage. Provenance 5/8 — the importer didn't have any computations or software in scope so this whole criterion is below ceiling."*

### 7. Done

Print one paragraph:
```
Done. Your crate is at <crate_dir>.
  Score: <total>/<max> (<pct>%)
  ro-crate-metadata.json:  <abs path>
  Schemas:                 <crate_dir>/schemas/
  Grading evidence:        <crate_dir>/grading/
```

## State file contract

All skills in this flow read and write `<cwd>/.fairscape-remote-state.json` (atomic write: temp + `os.replace`). Schema:

```json
{
  "schema_version": 1,
  "phase": "init|imported|schemas_done|rai_done|provenance_tracked|graded",
  "source": {"kind": "dataverse|physionet",
             "url_or_doi": "...",
             "server_url": "..."},
  "crate_dir": "/abs/path",
  "crate_path": "/abs/path/ro-crate-metadata.json",
  "imported_at": "ISO-8601",
  "tabular_files": [...],
  "schemas": [...],
  "schemas_done": [...],
  "paper": {"path": "...", "kind": "pdf|url", "fetched_at": "..."},
  "ai_ready": {/* RAI fields (22) + standard descriptors (license, conditionsOfAccess, etc.) */},
  "ai_ready_merged_at": "...",
  "provenance": {
    "skipped": false,
    "source_dataset_ids": ["ark:...", "..."],
    "software": [{"guid": "ark:...", "name": "...",
                  "source_kind": "github|zenodo|local|other",
                  "source_url": "..."}],
    "computations": [{"guid": "ark:...", "name": "...",
                      "usedSoftware": ["..."],
                      "usedDataset": ["..."],
                      "generated": ["..."]}],
    "link_inverses_run_at": "ISO-8601"
  },
  "grading": {"dir": "...", "completed_rubrics": [...],
              "aggregated_score_path": "...",
              "summary": {"total": N, "max": M, "percentage": P}},
  "datasheet_built_at": "ISO-8601",
  "history": [{"ts": "...", "skill": "...", "summary": "..."}]
}
```

Each delegated skill appends to `history` with a one-line summary after every confirmed mutation.

## Phase router (resume table)

| `state.phase`         | Next skill                             |
|-----------------------|----------------------------------------|
| missing / init        | `remote-import`                        |
| `imported`            | `remote-schema-infer`                  |
| `schemas_done`        | `remote-ai-ready-enrich`               |
| `rai_done`            | `remote-provenance-tracking` (ask first) |
| `provenance_tracked`  | `fairscape-cli build datasheet` (auto, no prompt) → `agentic-rescore` (ask first) |
| `graded`              | done — offer to re-run any phase       |

(The `rai_done` phase label is internal — the enrichment phase is now called "AI-Ready enrichment" to the user, but the label stays so resume logic works on any state files already on disk. Don't change it.)

## What you must NOT do

- Don't run the local-project wizard's skills (`scan-project-folder`, `register-dataset`, etc.). They write a different state file and assume a different graph shape.
- Don't fetch the full data files. Phase 2 samples ~5 MB; the data stays remote.
- Don't mutate `ro-crate-metadata.json` outside of the documented phases and `fairscape-cli` calls. Phase 1's `fairscape-cli import` creates it; phase 2's `fairscape-cli schema infer --rocrate-path` appends a Schema entity and `remote-schema-infer` back-links it onto every group member; phase 3 merges AI-Ready fields into the root entry; phase 4 appends Software/Computation entities and runs `fairscape-cli augment link-inverses` to fill in inverse properties; nothing else touches it.
- Don't proceed to a later phase if an earlier phase failed and the user hasn't acknowledged. If `remote-import` fails, stop and surface the error.
- Don't ask the user for tokens. Public datasets only in v1.
