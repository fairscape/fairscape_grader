"""
dump_prompts.py — extract evidence and write per-rubric prompts to a folder.

Local half of an air-gapped grading flow:
  1. python dump_prompts.py <crate> <out-dir>      (run here)
  2. ship <out-dir> to Rivanna
  3. python score_uvarc.py <out-dir> --api-key X   (run on the compute node)

Output layout (everything score_uvarc.py needs, no fairscape deps):
  <out-dir>/
    summary.json                       # crate path, stats, rubric manifest, criterion names
    system_prompt.txt                  # base system prompt
    rubrics/
      <id>-<slug>/
        rubric.yaml                    # copied source rubric (reference only)
        evidence.json                  # extracted evidence (reference only)
        prompt.txt                     # the full user-message prompt to send
"""
from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parents[2]
MODELS_DIR = REPO_ROOT.parent / "fairscape_models"
for p in (HERE, MODELS_DIR):
    if p.exists() and str(p) not in sys.path:
        sys.path.insert(0, str(p))

from extract import ALL_EXTRACTORS, ExtractContext, ReleaseBundle, root_summary  # noqa: E402
from grade import (  # noqa: E402
    BASE_SYSTEM_PROMPT,
    CRITERION_NAMES,
    RUBRIC_SRC_DIR,
    _build_prompt,
    _load_rubric_yaml,
)


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Dump all 28 rubric prompts to a self-contained folder."
    )
    ap.add_argument("crate_path", type=Path, help="path to ro-crate-metadata.json")
    ap.add_argument("output_dir", type=Path, help="output directory (created if missing)")
    args = ap.parse_args()

    if not args.crate_path.exists():
        raise SystemExit(f"crate not found: {args.crate_path}")

    print(f"[dump] loading {args.crate_path}")
    bundle = ReleaseBundle.load(args.crate_path)
    ctx = ExtractContext(bundle)
    print(
        f"[dump] dataset={ctx.dataset_count}  software={ctx.software_count}  "
        f"computation={ctx.computation_count}  experiment={ctx.experiment_count}  "
        f"schema={ctx.schema_count}"
    )

    rubrics_dir = args.output_dir / "rubrics"
    rubrics_dir.mkdir(parents=True, exist_ok=True)
    (args.output_dir / "system_prompt.txt").write_text(BASE_SYSTEM_PROMPT + "\n")

    manifest = []
    for cls in ALL_EXTRACTORS:
        slug_dir = rubrics_dir / f"{cls.rubric_id}-{cls.rubric_slug}"
        slug_dir.mkdir(parents=True, exist_ok=True)

        src_yaml = RUBRIC_SRC_DIR / f"{cls.rubric_id}-{cls.rubric_slug}.yaml"
        if not src_yaml.exists():
            raise FileNotFoundError(f"rubric YAML missing: {src_yaml}")
        shutil.copy(src_yaml, slug_dir / "rubric.yaml")

        evidence_payload = cls().extract(ctx)
        (slug_dir / "evidence.json").write_text(
            json.dumps(evidence_payload, indent=2, sort_keys=True, default=str) + "\n"
        )

        rubric_yaml = _load_rubric_yaml(cls.rubric_id, cls.rubric_slug)
        prompt = _build_prompt(rubric_yaml, evidence_payload)
        (slug_dir / "prompt.txt").write_text(prompt)

        manifest.append(
            {"id": cls.rubric_id, "slug": cls.rubric_slug, "dir": slug_dir.name}
        )
        print(f"  [{cls.rubric_id}] {cls.rubric_slug}")

    summary = {
        "target": str(args.crate_path),
        "root_summary": root_summary(bundle),
        "stats": ctx.stats,
        "rubrics": manifest,
        "criterion_names": CRITERION_NAMES,
    }
    (args.output_dir / "summary.json").write_text(
        json.dumps(summary, indent=2, sort_keys=True, default=str) + "\n"
    )
    print(f"[dump] wrote {len(manifest)} prompts to {args.output_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
