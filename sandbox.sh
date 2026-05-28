#!/usr/bin/env bash
# Launch the FAIRSCAPE RO-Crate wizard inside a sandboxed Docker container.
# The container can only see the folder you pass in. YOLO mode is safe here:
# `--dangerously-skip-permissions` only applies inside the container, which
# has no filesystem access outside the bind mount.
#
# Usage:
#   ./sandbox.sh <folder>        # mount <folder> as /workspace and start wizard
#   ./sandbox.sh --build         # force a rebuild of the image
#   ./sandbox.sh --shell <folder># open a bash shell instead of claude

set -euo pipefail

IMAGE="fairscape-wizard:latest"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

build_image() {
  echo ">> building $IMAGE..."
  docker build -t "$IMAGE" "$REPO"
}

case "${1:-}" in
  --build)
    build_image
    exit 0
    ;;
  --shell)
    shift
    ENTRY=(--entrypoint /bin/bash)
    CMD=()
    ;;
  "" | -h | --help)
    cat <<EOF
usage: $0 <folder>                 mount <folder> and start the wizard
       $0 --build                  rebuild the image
       $0 --shell <folder>         open a bash shell in the container

The container sees ONLY <folder>, mounted at /workspace. Outputs land
back in <folder> on the host. The image bakes the wizard skills in,
so no extra setup is needed.

Auth:
  Set ANTHROPIC_API_KEY in your shell before launching. If unset, the
  container starts an OAuth flow that won't persist between runs.
EOF
    exit 0
    ;;
  *)
    ENTRY=()
    CMD=()
    ;;
esac

PROJECT="${1:?folder argument required (try --help)}"
[[ -d "$PROJECT" ]] || { echo "not a directory: $PROJECT" >&2; exit 1; }
PROJECT="$(cd "$PROJECT" && pwd)"

docker image inspect "$IMAGE" >/dev/null 2>&1 || build_image

AUTH_ARGS=()
if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
  AUTH_ARGS+=(-e "ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY")
fi

exec docker run --rm -it \
  -v "$PROJECT:/workspace" \
  "${AUTH_ARGS[@]}" \
  "${ENTRY[@]}" \
  "$IMAGE" \
  "${CMD[@]}"
