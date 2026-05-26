---
name: remote-checkpoint
description: Summarize the current remote-source wizard state for the user and confirm whether to continue. Reads .fairscape-remote-state.json. Invoked at session resume and between phases.
---

# Remote checkpoint

Read `.fairscape-remote-state.json` (in the current working directory by default) and produce a short status summary. Ask whether to continue, edit, or stop.

## Procedure

1. `Read` the state file. If it doesn't exist, say so and offer to start a fresh remote-source wizard.
2. Compose a summary using **counts**, not full records:
   ```
   Source: <kind> <url_or_doi>
   Crate:  <crate_dir>

   Phase: <phase>
     Imported:        YYYY-MM-DD HH:MM  (<N> tabular files, <K> .gz skipped)
     Schemas:         <M of N groups> inferred  (<E entries back-linked>)
     AI-Ready paper:  <paper.path>  (<M> fields merged — K RAI, S standard)
     Grading:         <K of 28> rubrics  →  <total>/<max>  (<pct>%)
     Improvements:    <N> ran (<comma list>); <K> skipped; rescored: <yes/no, delta>

   Last activity: <ts> — <skill>: <summary>
   ```
   Omit lines for phases that haven't started. Pull the last-activity line from the most recent `state.history` entry.
3. Ask: **"Continue from `<phase>`, or fix something first?"**
4. Common follow-ups:
   - **"Show me the imported files"** → list `state.tabular_files` by `name`, format, and size_bytes.
   - **"Show me the schemas"** → list `state.schemas` by `name` and `schema_path`.
   - **"Show me the AI-Ready fields"** (or "RAI fields") → dump keys of `state.ai_ready` with one-line previews per value. (Fall back to `state.rai` for state files written by an earlier version of the wizard.)
   - **"Show me the score breakdown"** → if `state.grading.aggregated_score_path` exists, read it and render the criterion-by-criterion summary.
   - **"Show me the improvements"** → if `state.improvements` exists, list `ran`, `skipped`, and any `validation_failures`. If `rescored_at` is set, show the score delta between the pre-improvement and post-improvement `state.grading.summary`.
   - **"Run more improvements"** → invoke `post-grade-improve`. Allowed from `phase = graded` or `phase = improved`.
   - **"Remove schema X"** → drop the entry from `state.schemas` and the matching id from `state.schemas_done`; append a `removed` `history` entry.
   - **"Restart from phase X"** → set `state.phase = "<earlier phase>"` and clear downstream lists; warn before destructive resets.

## Don't

- Don't dump full JSON unless explicitly asked.
- Don't auto-advance the phase — that's the next skill's job. You only summarize.
- Don't read or touch the project-folder wizard's `.fairscape-wizard-state.json` — that's a different flow.
