# fairscape-agent

A Claude Code skill bundle that walks a non-expert user through documenting a research pipeline as a [FAIRSCAPE](https://fairscape.github.io/) RO-Crate. The user describes their pipeline in plain language; the wizard translates that into the RO-Crate data model behind the scenes and emits a re-runnable Python script (`build_rocrate.py`) that produces `ro-crate-metadata.json`.

The wizard is the **interview** the user fills out. The emitted script is the **artifact** they keep.

## What's in here

```
fairscape-agent/
├── pyproject.toml                       # ships the small fairscape_wizard helper module
├── src/fairscape_wizard/                # ARK GUID + slug helpers used by the emitted script
│   ├── __init__.py
│   └── ids.py
└── .claude/skills/                      # the wizard itself, as 10 Claude Code skills
    ├── fairscape-rocrate-wizard/        # top-level entry — invoke this
    ├── scan-project-folder/             # file inventory by category
    ├── extract-crate-metadata/          # title/abstract/authors from PDF, existing crate, or interview
    ├── register-dataset/                # one distinct file → Dataset
    ├── register-folder-of-alike/        # 1 template → many files via glob (the bulk primitive)
    ├── register-software/               # one script (.py/.R/.sh/.ipynb) → Software
    ├── create-computation/              # link inputs → script → outputs
    ├── plausibility-check/              # orphans, dangling refs, missing files
    ├── checkpoint/                      # resume / inspect / correct
    └── emit-build-script/               # write build_rocrate.py and run it
```

## Usage

From inside Claude Code, in the project directory you want to document:

```
/fairscape-rocrate-wizard
```

The wizard:
1. Scans your folder.
2. Pre-fills crate-level metadata if a paper PDF or existing `ro-crate-metadata.json` is around.
3. Walks you through the pipeline one step at a time — "what did you start with?" → "what did you do to it?" → "what came out?" — registering inputs, scripts, and outputs as you go.
4. Runs a plausibility check before writing anything.
5. Emits `build_rocrate.py` and runs it, producing `ro-crate-metadata.json`. Validates with `fairscape rocrate validate`.

You can quit at any point and resume — state is persisted to `.fairscape-wizard-state.json` after every confirmed answer.

## The two artifacts

- **`.fairscape-wizard-state.json`** — wizard scratchpad. Created and mutated turn-by-turn during the interview. Safe to delete after you've emitted the build script. Safe to commit if you want a record of the interview.
- **`build_rocrate.py`** — the canonical script. Inlines all entity metadata; expands folder-of-alike registrations via `glob` at run time so new files matching the pattern get picked up. Edit it freely; re-running it overwrites `ro-crate-metadata.json`.

## Why a script and not a notebook

Earlier versions of this tool emitted a Jupyter notebook. The script form is easier to diff, easier to re-run unattended, and matches the existing `kaggle_rocrate.py` pattern.

## Why folder-of-alike is a first-class primitive

Asking 847 questions for 847 microscopy images makes users quit. The bulk primitive captures one template (description, author, format) and one glob; the emitted script expands it at run time. Per-file overrides are supported via an `overrides: {filename: {field: value}}` map.

## Helper module

`fairscape_wizard.ids.generate_guid(prefix, name)` produces ARK GUIDs of the form `ark:59853/<prefix>-<slug>-<squid>`. Used by the wizard to generate stable IDs for single entities. Bulk groups use a deterministic per-filename variant `ark:59853/<prefix>-<slug(filename)>` so re-running the build script produces the same GUIDs.

Install with:
```
pip install -e .
```

## Sandboxed run (Docker)

Run the wizard in a container that can only see one folder. Inside the container, `--dangerously-skip-permissions` ("YOLO mode") is safe — the container has no filesystem access outside the bind mount.

```bash
# one-time: build the image (bakes in Claude Code + fairscape-cli + the wizard skills)
./sandbox.sh --build

# launch against any folder
./sandbox.sh ~/crates/my-paper
```

First launch drops you into `claude` with no credentials — run `/login` inside to OAuth with your Claude subscription. The token is saved to a named Docker volume (`fairscape-claude-auth`) and reused on every later launch; no re-login per run.

The folder you pass is mounted as `/workspace`; outputs (the RO-Crate, `manifest.csv`, `build_rocrate.sh`, state) land back in that folder on the host. Everything else on your disk is invisible to the container.

Other launcher commands:
- `./sandbox.sh --build` — force a rebuild after pulling new skills
- `./sandbox.sh --shell <folder>` — drop into bash instead of starting `claude`
- `./sandbox.sh --logout` — wipe the persisted credentials volume
- `./sandbox.sh --help`

## Out of scope (for now)

- **BYO-LLM / Electron host.** The wizard logic lives in skill markdown; porting to a non-Claude-Code host is a separate effort.
- **Auto-draft from directory state.** Pipeline directories with years of grad-student churn are too ambiguous to infer; the wizard interviews the user instead.
- **A `fairscape rocrate register dataset-batch` CLI command.** The script-emission approach handles bulk registration via Python loops without needing new CLI surface.
