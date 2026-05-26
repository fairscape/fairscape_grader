---
name: checkpoint
description: Summarize the current wizard state for the user and confirm whether to continue. Invoked at session resume, between major phases, and on user request.
---

# Checkpoint

Read `.fairscape-wizard-state.json` and produce a short status summary. Ask the user whether to continue, correct something, or stop.

## Procedure

1. `Read` the state file. If it doesn't exist, say so and offer to start the wizard fresh.
2. Compose a summary using counts, not full records:
   ```
   Crate: <state.crate_metadata.name or "(no name yet)">
     <one-line description if present>

   Captured so far:
     - 3 single inputs
     - 1 folder of inputs (raw images, 847 files)
     - 2 scripts
     - 1 step
     - 1 single output
     - 0 folders of outputs

   Branches: imaging (open, head: segmented_masks), clinical (complete), demographics (merged into imaging)

   Last activity: 2026-05-04T14:23 — added step "Segment images"
   ```
   Pull the "last activity" line from the most recent `state.history` entry. Omit the "Branches:" line if `state.branches` is absent or empty (single-pipeline case).
3. Ask the user: "Continue from here, or correct/remove anything first?"
4. Common follow-ups:
   - "Show me what's in inputs" → list `state.datasets` where `is_raw_input` and `state.bulk_groups` where `is_raw_input`, by `name`/`user_label`.
   - "Show me the steps" → render each `state.computations` entry as `<inputs> → <software> → <outputs>`.
   - "Remove X" → delete the matching entry, append a `removed` entry to `history`. If the removed entity is referenced by a computation, warn before removing or unwire it.

## Don't
- Don't dump full JSON unless explicitly asked.
- Don't propose new entities — that's the registration skills' job.
