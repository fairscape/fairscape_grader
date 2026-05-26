---
name: extract-crate-metadata
description: Capture the top-level RO-Crate metadata (name, description, authors, keywords, license, datePublished, version, associatedPublication) from a paper PDF, an existing ro-crate-metadata.json, or a short user interview. Writes to state.crate_metadata.
---

# Extract crate metadata

The crate needs a small set of top-level fields. Pick whichever of the three paths gets the answer with the fewest user keystrokes.

## Decide which path

1. **PDF available** (`scan.files_by_category.pdfs` non-empty): offer "I can read <paper.pdf> and pre-fill title/authors/abstract for you. OK?" If yes → path A.
2. **Existing crate** (`scan.existing_crate` set): offer "I see an existing ro-crate-metadata.json. Want me to copy its top-level fields as a starting point?" If yes → path B.
3. **Otherwise** → path C (interview).

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
  "associatedPublication": null
}
```

Append to `history`: `{"ts": ..., "skill": "extract-crate-metadata", "summary": "captured top-level metadata: <name>"}`.
