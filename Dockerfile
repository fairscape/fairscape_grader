FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        curl git ca-certificates \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g @anthropic-ai/claude-code

RUN pip install --upgrade pip \
    && pip install fairscape-models fairscape-cli

COPY pyproject.toml /opt/fairscape-wizard/pyproject.toml
COPY src/ /opt/fairscape-wizard/src/
RUN pip install /opt/fairscape-wizard

# Skills are baked OUTSIDE /root/.claude so they don't get hidden when the
# auth named volume is mounted at /root/.claude. The entrypoint syncs them
# into the live config dir on each start so updates land even on existing
# volumes.
COPY .claude/skills /opt/wizard-skills/

COPY <<'EOF' /usr/local/bin/sandbox-entry.sh
#!/usr/bin/env bash
set -e
mkdir -p /root/.claude/skills
cp -rT /opt/wizard-skills /root/.claude/skills
exec claude "$@"
EOF
RUN chmod +x /usr/local/bin/sandbox-entry.sh

WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/sandbox-entry.sh"]
CMD ["--dangerously-skip-permissions"]