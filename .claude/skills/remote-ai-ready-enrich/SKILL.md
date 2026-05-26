---
name: remote-ai-ready-enrich
description: Phase 3 of the remote-source wizard. Read a paper (local PDF or URL), extract AI-Ready metadata — including MLCommons RAI fields (`rai:dataCollection`, `rai:dataBiases`, etc.) plus standard descriptors (license, conditionsOfAccess, copyrightNotice) — and merge them into the existing ro-crate-metadata.json without clobbering fields the importer already populated. This is the one phase where the crate JSON is mutated in place.
---

# Remote AI-Ready enrichment — Phase 3

Phase 1 produced a crate with minimal metadata pulled from the upstream repository (name, description, authors, doi, etc.). This phase enriches it with the additional fields that make the crate **AI-Ready**: things a downstream model trainer needs to know before using the data. Most of those fields come from the MLCommons RAI vocabulary (prefixed `rai:`), but the bucket also includes standard Schema.org descriptors like `license`, `conditionsOfAccess`, and `copyrightNotice` — anything the importer didn't already capture that a paper can tell us.

## What to tell the user before any commands run

Set context with one paragraph before asking for a paper:

> *"This phase fills in the fields that make the crate **AI-Ready** — the kind of context a downstream user needs before training a model on the data. Most of these live in the MLCommons RAI vocabulary (`rai:dataCollection`, `rai:dataBiases`, `rai:dataLimitations`, `rai:dataUseCases`, etc.) but the same step also fills standard descriptors the importer may have missed (`license`, `conditionsOfAccess`, `copyrightNotice`, `associatedPublication`). The repository's API usually doesn't have any of this — but the paper that describes the dataset usually does. If you point me at a PDF or URL I'll read it, propose values for each field, let you adjust, and then merge them into the root entry of `ro-crate-metadata.json`. I won't overwrite anything the importer already set — only fill in nulls and extend lists. Skip is fine; the grading phase will just score lower on the AI-Ready criteria that depend on these."*

## Inputs

Ask the user: **"Got a paper that describes this dataset? Local PDF path, URL, or skip?"**

Three paths:
- **Local PDF**: `Read` the file. PDFs > ~50 pages: read the first 30 + the last 10 (where Discussion/Limitations usually live). Tell the user which range you read.
- **URL**: `WebFetch` the URL with a prompt asking for the full extracted text.
- **Skip**: write `state.paper = null`, set `state.phase = "rai_done"`, log to history, return.

If the user doesn't have one available right now, skip — phase 4 still runs.

## What to extract

Pull these fields from the paper(s). For each, do exactly what `fairscape-local-frontend/src/services/llm/systemPrompt.ts` instructs — quoted below for convenience. If a field can't be found or reasonably inferred, leave it `null` (or `[]` for list fields). Do NOT fabricate.

**Standard metadata (fill only nulls — these are Schema.org descriptors, not RAI):**
- `name` — primary title from the paper.
- `description` — synthesize from abstract(s); 1–3 sentences, trim to ~600 chars.
- `keywords` — paper keywords merged with what's already there, deduped.
- `author` — author byline as a single comma-separated string (per the systemPrompt convention).
- `associatedPublication` — primary publication's DOI or citation string.
- `license` — explicit mention only.
- `conditionsOfAccess` — any text describing data access.
- `copyrightNotice` — copyright holder.

**RAI — Data Lifecycle (MLCommons RAI vocabulary):**
- `rai:dataCollection` — synthesized detailed description from Methods.
- `rai:dataCollectionType` — list aggregated from sources (e.g. `["Experiments", "Survey"]`).
- `rai:dataCollectionMissingData` — any mention of data loss or gaps.
- `rai:dataCollectionRawData` — description of original source data.
- `rai:dataCollectionTimeframe` — list of dates / durations.

**RAI — Data Processing & Labeling:**
- `rai:dataImputationProtocol` — imputation methods, or null.
- `rai:dataManipulationProtocol` and `rai:dataPreprocessingProtocol` — cleaning/filtering/normalization steps; list form for preprocessing.
- `rai:dataAnnotationProtocol`, `rai:dataAnnotationPlatform`, `rai:dataAnnotationAnalysis`, `rai:annotationsPerItem`, `rai:annotatorDemographics` — fill only if human labeling is described. Otherwise null/[].
- `rai:machineAnnotationTools` — list of automated feature-extraction tools.

**RAI — Compliance / Fairness:**
- `rai:dataReleaseMaintenancePlan` — future plans for the dataset.
- `rai:personalSensitiveInformation` — conclude based on the paper(s); list form (`[]` if clearly none).
- `rai:dataSocialImpact` — synthesize from Introduction + Discussion.
- `rai:dataBiases` — comprehensive list of acknowledged or implied biases.
- `rai:dataLimitations` — comprehensive list of acknowledged limitations.
- `rai:dataUseCases` — list of intended applications and future directions.

Maintain a neutral tone — this is "what the paper reports", not your judgment of whether assumptions are valid. (See `feedback_assumption_framing.md` in memory: B2AI projects make weak assumptions, not errors.)

## Show the user, accept edits

Before merging into the crate, render the extracted fields as a compact summary so the user can see what you're proposing to add:

```
From <paper>:
  (standard)
    description:           "..."
    keywords (new):        [...]
    conditionsOfAccess:    "..."
  (RAI)
    rai:dataCollection:    "..."  (~200 chars)
    rai:dataBiases:        4 items
    rai:dataLimitations:   3 items
    rai:dataUseCases:      5 items
    ...
```

Tell the user what this affects: *"These will get merged into the root of `ro-crate-metadata.json`. Anything that's already filled in by the importer (name, DOI, version, etc.) stays as-is — I only fill nulls and extend lists. Want to adjust any of these before I merge?"* Apply corrections inline.

## Merge into ro-crate-metadata.json

This is the one place the JSON is mutated. Tell the user what's about to happen in one sentence (*"Merging now — read the current crate, fill nulls + union lists, atomic write back over the file"*), then proceed. **Read → merge → atomic write.**

1. `Read` `state.crate_path`.
2. Ensure `@context` is an object and contains `"rai": "http://mlcommons.org/croissant/RAI/"`. Add the key if missing.
3. Locate the root Dataset entity. It's the entity in `@graph` whose `@id` matches the descriptor's `about.@id` (find the entity with `@type: "CreativeWork"` and `@id: "ro-crate-metadata.json"` — its `about["@id"]` points at the root).
4. For each extracted field:
   - If the existing value is `null`, missing, or empty (`""` / `[]`): set it to the extracted value.
   - If the existing value is a list and the extracted is a list: union them (preserve order; dedupe by lowercase string equality for strings).
   - If the existing value is a non-empty scalar: **leave it alone**. Importer wins on conflicts.
5. Atomic write: write to `<path>.tmp`, `os.replace` over the original.

After the write, summarize for the user: *"Merged. The root entry now has `<N>` AI-Ready fields populated (`<K>` RAI, `<S>` standard). Anything I skipped is in `state.ai_ready` for review — you can edit `ro-crate-metadata.json` directly if you want to add something I missed."*

## State write

```json
{
  ...,
  "paper": {"path": "<abs or url>", "kind": "pdf|url",
            "fetched_at": "<UTC ISO8601>", "pages_read": "1-30,60-70"},
  "ai_ready": {<exact dict of fields extracted, before merge>},
  "ai_ready_merged_at": "<UTC ISO8601>",
  "phase": "rai_done",
  "history": [..., {"ts": "...", "skill": "remote-ai-ready-enrich",
                    "summary": "merged AI-Ready fields from <paper> — N added"}]
}
```

The state key is `state.ai_ready` (renamed from the older `state.rai`) so it reflects the broader scope of what's actually being captured — RAI fields plus standard descriptors. If `state.rai` exists from a previous run on this crate, migrate it: copy to `state.ai_ready` and delete `state.rai`. Save with the *pre-merge* extracted dict (for audit and reruns), not the post-merge crate state.

`state.phase` remains `"rai_done"` — that label is internal and shared with the grading phase's resume logic; not worth renaming.

## Don't

- Don't overwrite fields the importer set (name, doi, version, etc.) unless they're null.
- Don't invent values to satisfy fields. `null` and `[]` are valid answers.
- Don't add `@context` namespaces beyond `rai:`. The importer already set the rest.
- Don't run if `state.crate_path` doesn't exist — tell the user phase 1 hasn't completed.
- Don't read the entire paper into the user's context for display — summarize.
- Don't say "RAI enrichment" to the user — say "AI-Ready enrichment". Reserve "RAI" for the JSON-LD field prefix that the spec actually uses.
