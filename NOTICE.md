# NOTICE: DeepSeek Harness template

## Software deployed

| Component | Source | License | How it is used |
|---|---|---|---|
| DeepSeek Harness (`dsh`) | npm `@deepseek-ai/dsh@0.2.1-rc.2` (published 2026-10-17), built from https://github.com/deepseek-ai/deepseek-harness tag `dsh-v0.2.1-rc.2` (commit `687f282e8625c6b8d11ff58211a90524be2e4317`) | MIT, Copyright (c) 2026 DeepSeek | Installed unmodified with `npm install --global` at image build time. Its dependency closure carries its own licenses (upstream `THIRD_PARTY_NOTICES.md`); the Landlock launcher `@deepseek-ai/node-addon-system` is BSD-3-Clause, the vendored Cordis libraries are MIT. |
| Caddy 2.11.7 | Docker Hub `caddy:2.11.7-alpine` (digest pinned in the Dockerfile) | Apache-2.0 | Only the static `caddy` binary is copied into the image and run unmodified. |
| Node.js 24.22.0 | Docker Hub `node:24.22.0-trixie-slim` (digest pinned) | MIT (Node.js), Debian packages under their own licenses | Base image. |
| pnpm 11.28.5 | npm `pnpm@11.28.5` | MIT | Installed globally; dsh's plugin manager calls it to install plugins. |
| Debian 13 packages | apt (bubblewrap, git, python3, build-essential, ripgrep, jq, ...) | Their respective licenses (GPL, LGPL, MIT, BSD, ...) | Installed at build time as the agent's toolbox. |

"DeepSeek" and "DeepSeek Harness" are trademarks of DeepSeek. This is a community template; it is not affiliated with, endorsed by, or supported by DeepSeek. The listing icon is the project's own application icon, loaded from the upstream repository at the pinned tag.

## Files written for this template

`Dockerfile`, `railway-start.sh`, `Caddyfile`, `railway.patch.yml`, `TEMPLATE.md`, `template.json`, `README.md` and this NOTICE were written for this package. No upstream files are copied into the image or the repository; the npm package is installed as published.

The Railway-specific behaviour follows upstream's own documentation at the pinned tag:

- `docs/user/guide/public-deployments.md` and `packages/bundle/web-app/README.md`: loopback listener behind a reverse proxy, `--public-url`, `--trusted-host`, preserved `Host`, WebSocket forwarding, adding `Secure` to the session cookie on the HTTPS leg.
- `packages/client/connection/README.md` and `src/browser-auth.ts`: per-process launch token, `GET /?token=` exchange, signed `dsh-auth-*` cookie whose signing secret is stored in `$DSH_HOME/.credentials.yaml`, 401 for unauthenticated index requests (used by `/healthz`).
- `packages/api/workspace-controller/README.md` and `src/default-directory.ts`: `documentsDirectory` override for hosts without `xdg-user-dir` (used in `railway.patch.yml`).
- `apps/cli/README.md`, `apps/cli/reference/README.md`, `apps/cli/src/args.ts`, `packages/bundle/web-app/src/startup.ts`: launcher grammar (`dsh web --patch ... --no-open --port ...`), `DSH_HOME`, `DSH_PERMISSION_MODE`, `DSH_TELEMETRY_DISABLED`, shutdown behaviour.

## Upstream files checked (tag `dsh-v0.2.1-rc.2`, checked 2026-10-20)

`README.md`, `SAFETY.md`, `BRAND_GUIDELINES.md`, `LICENSE`, `THIRD_PARTY_NOTICES.md`, `package.json`, `pnpm-workspace.yaml`, `pnpm-lock.yaml` (native dependencies), `docs/user/guide/index.md`, `docs/user/guide/public-deployments.md`, `docs/user/guide/providers.md`, `docs/user/guide/plugin-market.md`, `apps/cli/README.md`, `apps/cli/reference/README.md`, `apps/cli/src/args.ts`, `apps/cli/src/bin.ts`, `packages/bundle/base/cordis.patch.yml`, `packages/bundle/web-app/cordis.patch.yml`, `packages/bundle/web-app/README.md`, `packages/bundle/web-app/src/index.ts`, `packages/bundle/web-app/src/startup.ts`, `packages/client/connection/README.md`, `packages/client/connection/src/browser-auth.ts`, `packages/client/connection/src/api-request-trust.ts`, `packages/client/ui-settings-general/src/client/index.ts`, `packages/api/workspace-controller/src/*`, `packages/sandbox/sandbox-local/README.md`, `packages/sandbox/sandbox-policy/README.md`, `packages/shell/bash-sandbox/README.md`, `packages/subprocess/subprocess/README.md`, `packages/subprocess/subprocess-local/README.md`, `packages/boot/plugin-manager/README.md`, `packages/session/session-log-deepseek/README.md`, `packages/fs/tool-fs-search/README.md`, `packages/llm/llm-pi-ai/src/provider-data.generated.ts`.

Caddy behaviour (basic_auth hash cache and bcrypt default, `hash-password` reading stdin, `header_down` regex replacement on every `Set-Cookie` value, `handle_response`) was checked in the Caddy source at tag `v2.11.7`.

## Market templates and repositories reviewed

| Template / repo | License | Use |
|---|---|---|
| "DeepSeek Harness \| (Just Updated) ..." (image `ghcr.io/bon5co/deepseek-harness-railway:0.2.0-rc.2`) | image only, no source available locally | Only the marketplace JSON and readme were read (Caddy basic auth in front of a loopback dsh, `/home/dsh` volume). Nothing copied. |
| "DeepSeek Harness on NixOS ..." (image `ghcr.io/bon5co/deepseek-harness-nixos-railway:0.1.0-rc.6`) | image only | Marketplace JSON and readme read. Nothing copied. |
| "DeepSeek Harness + Web UI" / `Timboslice212/deepseek-harness-railway` | MIT, Copyright (c) 2026 Railway Template Factory contributors | Read for ideas: capturing dsh's printed launch token behind a login gate and redirecting signed-in browsers to the token URL, and the `workspace-controller.documentsDirectory` overlay. Both ideas are implemented differently here (Caddy + a bash supervisor instead of a Node.js `http-proxy` gateway); no code or text was copied. Its compatibility patch of `@deepseek-ai/dsh-client-ui-settings` (0.1.7-alpha.1) is not needed for 0.2.1-rc.2 and is not used. |

The MIT license text of the reviewed wrapper: https://github.com/Timboslice212/deepseek-harness-railway/blob/main/LICENSE
