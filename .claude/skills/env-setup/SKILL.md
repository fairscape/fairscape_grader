---
name: env-setup
description: Interactive environment helper, invoked when preflight-check reports blockers. Detects whether sibling fairscape repos are present (for editable dev installs) or whether the user should install from PyPI (the default for most users). Optionally creates a `.venv` after explicit confirmation. Runs pip installs. Re-runs preflight to verify. Never touches the user's environment without asking.
---

# Environment setup

The user just hit a preflight failure. This skill walks them out of it: figures out the right install path, asks before mutating anything, installs the missing packages, then re-runs preflight to confirm. Never auto-modifies system Python.

## What to tell the user

> *"Preflight found `<N>` blockers. I can help you fix them. Two install paths:*
> *  - **PyPI install** (recommended — what most users want). One `pip install fairscape-cli fairscape-wizard` and you're done.*
> *  - **Editable dev install** (only if you're working out of the fairscape repos themselves — common for fairscape developers). I'd `pip install -e` each sibling repo.*
> *Either way, I can set up a fresh `.venv` in the current directory first so we don't touch your system Python. I'll ask before running anything."*

## 1. Detect context

Run in one Bash call:

```bash
python3 - <<'PY'
import json, os, shutil, sys
ctx = {
    "python_executable": sys.executable,
    "python_version": ".".join(map(str, sys.version_info[:3])),
    "in_venv": sys.prefix != sys.base_prefix,
    "venv_prefix": sys.prefix if sys.prefix != sys.base_prefix else None,
    "cwd": os.getcwd(),
    "has_uv": shutil.which("uv") is not None,
    "has_pipx": shutil.which("pipx") is not None,
    "has_conda": shutil.which("conda") is not None,
}
# Sibling-repo detection — look up one or two parents for the three repos
candidates = ["fairscape-cli", "fairscape_models", "fairscape-grader"]
ctx["sibling_repos"] = {}
for base in (".", "..", "../.."):
    for name in candidates:
        p = os.path.abspath(os.path.join(base, name, "pyproject.toml"))
        if os.path.exists(p) and name not in ctx["sibling_repos"]:
            ctx["sibling_repos"][name] = os.path.dirname(p)
print(json.dumps(ctx, indent=2))
PY
```

Use the result to inform the next questions. Specifically:
- `in_venv == False` → suggest creating `.venv`.
- All three sibling repos found → editable install is actually viable; mention it without pushing.
- Only PyPI viable (no sibling repos) → don't even offer editable; collapse the question.
- `has_uv` → mention `uv` as a faster alternative to plain pip if you go with it.

## 2. Ask the install path

> *"PyPI install or editable dev install?*
> *  1. **PyPI** — `pip install fairscape-cli fairscape-wizard` from the index. Most users want this.*
> *  2. **Editable** — found sibling repos at `<paths>`. `pip install -e` each. Pick this only if you're a fairscape developer working out of these repos.*
> *  Or `skip` and I'll print the commands for you to run yourself."*

(If no sibling repos were found, collapse to: *"PyPI install — `pip install fairscape-cli fairscape-wizard`. Or `skip` and I'll print the command."*)

## 3. Ask about a venv

If the user is **not** in a venv already:

> *"You're on system Python (`<python_executable>`). Create a fresh `.venv` in `<cwd>` and install there? (Recommended — keeps the install isolated. `yes` / `no` — say `no` if you've already got a venv elsewhere you want to use.)"*

If they say yes, run:

```bash
python3 -m venv .venv
```

After creation, **you cannot rely on `source .venv/bin/activate` persisting across Bash calls** (each Bash invocation is a fresh subshell). Instead, do the install using the venv's pip directly:

```bash
./.venv/bin/pip install --upgrade pip
./.venv/bin/pip install fairscape-cli fairscape-wizard
```

If the user is already in a venv, just use `pip install` directly — the active venv's pip is what runs.

If `uv` is available and the user wants speed, offer `uv pip install` instead of `pip install`. Don't push it; offer once.

## 4. Run the install

**PyPI path**:

```bash
<pip-binary> install fairscape-cli fairscape-wizard
```

`fairscape-cli` pulls `fairscape-models` as a dep (`fairscape-models>=1.1.1`). `fairscape-wizard` pulls both.

**Editable path**: order matters because `fairscape-cli` depends on `fairscape-models`, and `fairscape-wizard` depends on both. Run in this order:

```bash
<pip-binary> install -e <sibling_repos[fairscape_models]>
<pip-binary> install -e <sibling_repos[fairscape-cli]>
<pip-binary> install -e <sibling_repos[fairscape-grader]>
```

Stream stderr so the user sees what's happening on a slow network. If pip emits a resolver error, surface it verbatim — do not paper over it.

## 5. Re-run preflight

After install, invoke `preflight-check` again. Show the result to the user:

**If preflight now passes**:

> *"Done. Preflight passed. `<binary>` is at `<path>`, all packages importable.*
> *If you created a venv just now, future sessions need to activate it first:*
> *  `source ./.venv/bin/activate`*
> *Then re-run the wizard."*

**Important about the venv**: tell them this explicitly. The current session inherits the parent shell's environment; the venv we just created is only active for the binaries we invoked by absolute path. New shells / new sessions need to activate.

**If preflight still fails**:

> *"`<count>` blockers remain after install — see below. This usually means a version conflict or a system Python interfering. Surfacing the pip output and the new preflight detail; you'll likely want to triage manually from here."*

Don't loop or retry automatically.

## 6. Skip path

If the user said `skip` at any point, print the exact commands they need and exit:

```
You can install by running:

  python3 -m venv .venv && source ./.venv/bin/activate
  pip install --upgrade pip
  pip install fairscape-cli fairscape-wizard

Then re-run the wizard.
```

For editable:

```
For dev (editable) install:

  python3 -m venv .venv && source ./.venv/bin/activate
  pip install --upgrade pip
  pip install -e <abs path to fairscape_models>
  pip install -e <abs path to fairscape-cli>
  pip install -e <abs path to fairscape-grader>
```

## What about a system Python user who refuses both a venv and pipx?

If they explicitly want to `pip install` into system Python: warn once (*"Installing into `<python_executable>` will touch your system Python — packages may collide with OS-managed ones. Continue?"*), and respect their choice. Do not refuse — they might be in a container or know what they're doing. Just don't `sudo` anything ever.

## Don't

- Don't `pip install` anything without explicit user confirmation on this turn. "I said yes last time" doesn't count.
- Don't `sudo`. Ever. Not for `pip`, not for `python -m venv`, not for anything.
- Don't activate the venv via `source` in a `Bash` call and expect it to persist — each Bash call is a fresh subshell. Use absolute paths to the venv's pip / python instead.
- Don't run `pip uninstall` or modify packages the user already has installed. If there's a version conflict, surface it and let them decide.
- Don't change the user's shell rc files (`.bashrc`, `.zshrc`). Activation is the user's responsibility after we create the venv.
- Don't use this skill to upgrade fairscape packages on a working install. That's a different conversation. This skill exists to *unblock preflight failures*, not to manage versions.
