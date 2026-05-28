---
name: extract-crate-metadata
description: Capture the top-level RO-Crate metadata (name, description, authors, keywords, license, datePublished, version, associatedPublication) from a paper PDF, an existing ro-crate-metadata.json, a short interview, or a structured form. Writes to state.crate_metadata.
---

# Extract crate metadata

The crate needs a small set of top-level fields. Pick whichever of the four paths gets the answer with the fewest user keystrokes.

## Decide which path

1. **Form requested by the unified wizard's local branch**: when the orchestrator passes `mode=form`, go to path D directly. The form path collects more upfront fields (`license`, `publication_date`, `doi`) because the local branch doesn't have a later RAI phase to fall back to.
2. **PDF available** (`scan.files_by_category.pdfs` non-empty): offer "I can read <paper.pdf> and pre-fill title/authors/abstract for you. OK?" If yes → path A.
3. **Existing crate** (`scan.existing_crate` set): offer "I see an existing ro-crate-metadata.json. Want me to copy its top-level fields as a starting point?" If yes → path B.
4. **Otherwise** → path C (interview).

## Path A — read PDF

Use the `Read` tool on the PDF. Pull from it:
- `name` — paper title
- `description` — abstract (1–3 sentences; trim if longer than ~600 chars)
- `authors` — list of author names from the byline (string list)
- `keywords` — paper keywords if present, else 3–5 you infer from abstract
- `associatedPublication` — DOI or URL if present in the PDF metadata or first page
- `datePublished` — paper publication date if visible (ISO `YYYY-MM-DD`); else today

Show the proposed values to the user as a numbered list and ask "Anything to correct?" Apply corrections, then write to `state.crate_metadata`.

## Path B — existing crate

`Read` the existing `ro-crate-metadata.json`. Find the root-dataset element (`@type` includes `Dataset` and the `hasPart` array). Pull `name`, `description`, `keywords`, `author`, `license`, `version`, `datePublished`. Confirm with the user.

## Path C — interview

Ask, one at a time:
1. "What's the project called?" → `name`
2. "One or two sentences on what this project does." → `description`
3. "Who should be listed as the author(s)? Comma-separated names is fine." → `authors`
4. "Any keywords? (Optional — comma-separated, or skip.)" → `keywords`

Defer `license`, `datePublished`, `version`, `associatedPublication` to the RAI/governance phase at the end of the wizard. Set `version: "1.0"` and `datePublished: <today's ISO date>` as defaults silently.

## Path D — structured form (used by the unified wizard's local branch)

Collect more upfront than path C, because the local branch wants to build the manifest sidecar immediately afterward and doesn't have a later phase to fill license/date in. Use `AskUserQuestion` for the discrete fields where the choice space is small; use free-text for everything else.

Ask in this order:

1. **Name** (free text) — "What's the project called?"
2. **Description** (free text) — "One paragraph on what this project is. Plain language is fine."
3. **Authors** (free text, comma-separated) — "Who should be listed as the author(s)? Comma-separated names. ORCIDs can be added later by `/link-authors-orcids`."
4. **License** — present as `AskUserQuestion`:
   - CC0 1.0 Universal (public domain) — `https://creativecommons.org/publicdomain/zero/1.0/`
   - CC BY 4.0 — `https://creativecommons.org/licenses/by/4.0/`
   - MIT — `https://opensource.org/licenses/MIT`
   - Apache 2.0 — `https://www.apache.org/licenses/LICENSE-2.0`
   - Proprietary / unspecified — `null` (the rubric will penalize this; fine for early drafts)
   - **Other** — user provides a URL
5. **Keywords** (free text, comma-separated) — "Up to 8 short keywords describing the data. Skip if you'd rather come back to this later."
6. **Publication date** (free text, ISO `YYYY-MM-DD`) — "When was/will the dataset be released? ISO date. Default: today."
7. **DOI** (free text, optional) — "DOI for the associated paper, if any. Bare form (`10.xxxx/...`) or skip."

After collection, show the user a numbered summary of what got captured and ask "Anything to correct?" Apply corrections, then write to `state.crate_metadata`. The local branch will read this immediately afterward.

## State write

```json
"crate_metadata": {
  "name": "...",
  "description": "...",
  "authors": ["..."],
  "keywords": ["..."],
  "datePublished": "YYYY-MM-DD",
  "license": null,
  "version": "1.0",
  "associatedPublication": null,
  "publication_date": "YYYY-MM-DD",
  "doi": null
}
```

For path D, also populate `publication_date` and `doi` (form collects them). These map to the `crate.json` sidecar fields `publication_date` and `doi` that `build-local-manifest` reads.

Append to `history`: `{"ts": ..., "skill": "extract-crate-metadata", "summary": "captured top-level metadata: <name>"}`.
