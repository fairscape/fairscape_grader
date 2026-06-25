"""Back-compat shim. The real grader now lives in ``fairscape_wizard.grade``.

Historically the AI-Ready grader was run as::

    python rubrics/ai-ready/grade.py <crate.json> <out-dir> --model ... --api-key ...

That still works via this shim, but the engine moved into the installable
package so it can also be used as a console script (``fairscape-grade``) and
imported from a script (``from fairscape_wizard import grade``). See
``src/fairscape_wizard/grade.py``.

This shim adds ``src/`` to ``sys.path`` so it keeps working from a bare source
checkout where ``fairscape_wizard`` has not been pip-installed.
"""
import sys
from pathlib import Path

_SRC = Path(__file__).resolve().parents[2] / "src"
if _SRC.exists() and str(_SRC) not in sys.path:
    sys.path.insert(0, str(_SRC))

from fairscape_wizard.grade import grade_crate, main  # noqa: E402,F401

if __name__ == "__main__":
    sys.exit(main())
