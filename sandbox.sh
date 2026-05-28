#!/usr/bin/env bash
# Launch the FAIRSCAPE RO-Crate wizard inside a sandboxed Docker container.
# The container can only see the folder you pass in. YOLO mode is safe here:
# `--dangerously-skip-permissions` only applies inside the container, which
# has no filesystem access outside the bind mount.
#
# Auth: OAuth /login persisted in a named Docker volume. Run `/login` inside
# the container once; subsequent launches reuse the saved credentials.
#
# Usage:
#   ./sandbox.sh <folder>          # mount <folder> as /workspace and start wizard
#   ./sandbox.sh --build           # force a rebuild of the image
#   ./sandbox.sh --shell <folder>  # open a bash shell instead of claude
#   ./sandbox.sh --logout          # wipe persisted credentials

set -euo pipefail

IMAGE="fairscape-wizard:latest"
AUTH_VOLUME="fairscape-claude-auth"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

build_image() {
  echo ">> building $IMAGE..."
  docker build -t "$IMAGE" "$REPO"
}

ensure_volume() {
  docker volume inspect "$AUTH_VOLUME" >/dev/null 2>&1 \
    || docker volume create "$AUTH_VOLUME" >/dev/null
}

ENTRY=()
case "${1:-}" in
  --build)
    build_image
    exit 0
    ;;
  --logout)
    docker volume rm "$AUTH_VOLUME" 2>/dev/null \
      && echo ">> wiped $AUTH_VOLUME" \
      || echo ">> no $AUTH_VOLUME volume to wipe"
    exit 0
    ;;
  --shell)
    shift
    ENTRY=(--entrypoint /bin/bash)
    ;;
  "" | -h | --help)
    cat <<EOF
usage: $0 <folder>                 mount <folder> and start the wizard
       $0 --build                  rebuild the image
       $0 --shell <folder>         open a bash shell in the container
       $0 --logout                 wipe persisted OAuth credentials

The container sees ONLY <folder>, mounted at /workspace. Outputs land
back in <folder> on the host. The image bakes the wizard skills in,
so no extra setup is needed.

Auth:
  First launch will land you in claude with no credentials — run
  /login inside to OAuth with your Claude subscription. The token is
  saved to the '$AUTH_VOLUME' Docker volume and reused on every later
  launch. Use --logout to wipe it.
EOF
    exit 0
    ;;
esac

PROJECT="${1:?folder argument required (try --help)}"
[[ -d "$PROJECT" ]] || { echo "not a directory: $PROJECT" >&2; exit 1; }
PROJECT="$(cd "$PROJECT" && pwd)"

docker image inspect "$IMAGE" >/dev/null 2>&1 || build_image
ensure_volume

exec docker run --rm -it \
  -v "$PROJECT:/workspace" \
  -v "$AUTH_VOLUME:/root/.claude" \
  "${ENTRY[@]}" \
  "$IMAGE"
