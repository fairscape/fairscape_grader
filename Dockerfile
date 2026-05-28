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

COPY .claude /root/.claude

WORKDIR /workspace

ENTRYPOINT ["claude"]
CMD ["--dangerously-skip-permissions"]
