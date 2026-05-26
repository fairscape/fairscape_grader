---
name: create-computation
description: Wire one step of the pipeline — link the script that ran, the inputs it used, and the outputs it produced. Invoked after the user describes a step ("I ran clean.py on raw.csv to get cleaned.csv").
---

# Create a computation

A Computation is one step of the pipeline: software + inputs → outputs. This is the linker — it doesn't create datasets or software, it points at ones already registered.

## Prerequisite

Before invoking, the inputs / outputs / script for this step should already be in `state.datasets` / `state.bulk_groups` / `state.software`. If they aren't:
- Register inputs (`register-dataset` or `register-folder-of-alike`).
- Register the script (`register-software`).
- Register outputs (`register-dataset` or `register-folder-of-alike`, with `is_raw_input: false`).
- Then invoke this skill.

The wizard's main loop should normally drive this ordering for you.

## Inputs you need

1. **Step name.** "What would you call this step?" (e.g., "Clean raw measurements"). 1–8 words.
2. **One-sentence description.** What it did.
3. **Which script ran it.** Match against `state.software` by name or `user_label`. If multiple, ask. If none, send the user back to `register-software`.
4. **Which inputs it used.** Match against `state.datasets` (by user_label / guid) and `state.bulk_groups` (by guid_prefix / user_label). Multi-select OK. If a needed input isn't registered, send the user back.
5. **What it produced.** Same matching as inputs.
6. **Who ran it.** Default crate-level author.
7. **When.** ISO date; default today.

## Linking semantics

- `usedSoftware`: list of GUIDs from `state.software` (typically one).
- `usedDataset`: list of GUIDs from `state.datasets` (single-file inputs).
- `used_bulk_groups`: list of `guid_prefix` strings from `state.bulk_groups` (folder inputs). The build script will expand these into per-file GUIDs.
- `generated`: list of GUIDs from `state.datasets` (single-file outputs).
- `generated_bulk_groups`: list of `guid_prefix` strings (folder outputs).

## GUID

`ark:59853/computation-<slug(name)>-<squid>`.

## Write to state

Append to `state.computations`:
```json
{
  "guid": "ark:59853/computation-clean-raw-measurements-...",
  "name": "Clean raw measurements",
  "description": "Removes NaNs and outliers from the raw acquisition CSV",
  "runBy": "Justin",
  "dateCreated": "2026-05-04",
  "usedSoftware": ["ark:59853/software-process-py-..."],
  "usedDataset": ["ark:59853/dataset-raw-csv-..."],
  "used_bulk_groups": [],
  "generated": ["ark:59853/dataset-cleaned-csv-..."],
  "generated_bulk_groups": []
}
```

After writing, summarize the step graphically:
```
Step "Clean raw measurements":
  raw.csv  →  process.py  →  cleaned.csv
```
This is the moment to show progress — the user wants to see their pipeline materialize.

Append `history`.
