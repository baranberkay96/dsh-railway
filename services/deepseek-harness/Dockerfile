# DeepSeek Harness (dsh) Web UI for Railway.
#
# One container: the official npm package @deepseek-ai/dsh (Web profile,
# loopback only) behind Caddy (password gate on Railway's PORT). All state
# lives on the /data volume. See railway-start.sh for the process layout.

# Caddy 2.11.7 (Apache-2.0), official image; only its static binary is used.
FROM caddy:2.11.7-alpine@sha256:d8542f48d34a9cf4e4c11a478865229840e87e4c96ea3f439101f31a5d35f75f AS caddy

# Node.js 24 LTS on Debian 13 (trixie). dsh needs Node ^22.19 or >=24.
FROM node:24.22.0-trixie-slim@sha256:7f486cabe892bff8fef04c0f7da8dba84a560be3e4e2740b7a86afc57ebec315

# Pinned upstream versions. DSH_VERSION is the npm release of
# github.com/deepseek-ai/deepseek-harness (git tag dsh-v0.2.1-rc.2);
# PNPM_VERSION matches upstream's packageManager and is what dsh's plugin
# manager calls to install plugins into the Web profile.
ARG DSH_VERSION=0.2.1-rc.2
ARG PNPM_VERSION=11.28.5

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# Toolbox for the agent's shell (git, Python, compilers, search and archive
# tools) plus bubblewrap, the first sandbox runner dsh probes on Linux (it
# falls back to Landlock when user namespaces are unavailable).
# build-essential and python3 also let npm compile native addons if a
# prebuilt binary is ever missing.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bash bubblewrap build-essential ca-certificates curl git jq less \
      openssh-client procps python3 python3-pip python3-venv ripgrep \
      unzip xz-utils zip \
 && rm -rf /var/lib/apt/lists/*

RUN npm install --global --no-fund --no-audit --loglevel=warn \
      "@deepseek-ai/dsh@${DSH_VERSION}" "pnpm@${PNPM_VERSION}" \
 && npm cache clean --force \
 && mkdir -p /opt/dsh-railway \
 && dsh --version | tee /opt/dsh-railway/DSH_VERSION \
 && test "$(cat /opt/dsh-railway/DSH_VERSION)" = "${DSH_VERSION}" \
 && pnpm --version \
 && find "$(npm root --global)/@deepseek-ai/dsh" -path '*/@deepseek-ai/dsh-web-frontend/dist/index.html' | grep -q . \
 && find "$(npm root --global)/@deepseek-ai/dsh" -path '*/node-pty/prebuilds/linux-x64/pty.node' | grep -q .

# Two unprivileged users: "dsh" runs the Harness and every agent command
# (home on the volume), "caddy" runs the password gate.
RUN groupadd --gid 10001 dsh \
 && useradd --uid 10001 --gid dsh --home-dir /data/home --no-create-home --shell /bin/bash dsh \
 && groupadd --system --gid 10002 caddy \
 && useradd --system --uid 10002 --gid caddy --home-dir /nonexistent --no-create-home --shell /usr/sbin/nologin caddy

COPY --from=caddy /usr/bin/caddy /usr/local/bin/caddy
COPY Caddyfile /etc/caddy/Caddyfile
COPY railway.patch.yml /opt/dsh-railway/railway.patch.yml
COPY --chmod=0755 railway-start.sh /usr/local/bin/railway-start

# Fail the build early if the Caddyfile does not parse (dummy values only).
RUN PORT=8080 DSH_INTERNAL_PORT=3080 DSH_WEB_USERNAME=admin DSH_LAUNCH_TOKEN=build-check \
    DSH_WEB_PASSWORD_HASH="$(printf 'build-check-password\n' | caddy hash-password)" \
    HOME=/tmp XDG_CONFIG_HOME=/tmp/caddy-config XDG_DATA_HOME=/tmp/caddy-data \
    caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile \
 && rm -rf /tmp/caddy-config /tmp/caddy-data \
 && bash -n /usr/local/bin/railway-start

ENV DATA_DIR=/data \
    DSH_HOME=/data/home/.dsh \
    DSH_INTERNAL_PORT=3080 \
    PORT=8080

WORKDIR /data
EXPOSE 8080

# Starts as root to prepare the volume, then drops to the two users above.
ENTRYPOINT ["/usr/local/bin/railway-start"]
