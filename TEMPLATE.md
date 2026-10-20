# DeepSeek Harness 0.2 Coding Agent with Web UI: Railway template spec

## Listing

| Field | Value |
|---|---|
| Name | **DeepSeek Harness 0.2 Coding Agent with Web UI** (assigned name plus `0.2` = major.minor of the pinned `0.2.1-rc.2`; see the trademark note under Open questions) |
| Description | DeepSeek's open-source agent harness, always on, with plugins and a web UI. (75 chars, unchanged) |
| Category | AI/ML |
| Tags | deepseek, deepseek-harness, dsh, ai-agent, coding-agent, llm, web-ui, plugins |
| Icon | `https://cdn.jsdelivr.net/gh/deepseek-ai/deepseek-harness@dsh-v0.2.1-rc.2/apps/desktop/resources/icon.svg` (upstream app icon at the pinned tag, HTTP 200 checked) |

Every promise in the description is delivered:
- **Open-source agent harness by DeepSeek**: `github.com/deepseek-ai/deepseek-harness`, MIT.
- **Always on**: one service with restart policy `ALWAYS`, state on a volume.
- **Plugins**: dsh's plugin manager (Web UI → Plugins, and `dsh plugin --profile web ...` over `railway ssh`) installs bundles with pnpm into `$DSH_HOME/profiles/web`; pnpm 11.28.5 is in the image and the profile lives on the volume.
- **Web UI**: upstream's own browser UI (`dsh web`), not a third-party front end.

### Is there a real server/web mode?

Yes. `dsh web` (the `web` profile) is a long-running HTTP + WebSocket server with a browser UI for chat, sessions, workspaces, model settings, plugins and scheduled tasks. Upstream documents remote use behind a reverse proxy (`docs/user/guide/public-deployments.md`): the listener stays on loopback (wildcard binds are rejected on purpose), `--public-url` sets the advertised address and `--trusted-host` admits the public host name. Authentication is built in: each process prints a URL with a random launch token; opening it exchanges the token for a signed, HttpOnly, 30-day session cookie whose signing secret is stored in `$DSH_HOME/.credentials.yaml`, and every API call and WebSocket stream checks that cookie. What upstream does not provide is a fixed password: the token changes on every restart and is only shown in the process output. This template closes that gap with a generated password in front (see Architecture).

## Base market template

| Market template | Active | What it is | Verdict |
|---|---|---|---|
| "DeepSeek Harness \| (Just Updated) DeepSeek's Own Coding Agent, Gated" | 41 | Third-party image `ghcr.io/bon5co/deepseek-harness-railway:0.2.0-rc.2` (Ubuntu 24.04, Node 24), Caddy basic auth, volume `/home/dsh`, `DSH_PASSWORD` = `secret(24)`, `/healthz`, `ON_FAILURE` ×10 | **Base for the shape** (one container, loopback dsh, password gate, volume, healthcheck). Source not available, so nothing reused; version behind (0.2.0-rc.2) |
| "DeepSeek Harness + Web UI" (`Timboslice212/deepseek-harness-railway`, MIT) | 11 | Built from a repo: Node.js `http-proxy` gateway with its own login form in front of upstream's Web UI, launch-token capture, `/data` volume. Pins `@deepseek-ai/dsh@0.1.7-alpha.1` and patches a compiled upstream file. Username and password are **user-typed with empty defaults** | Its "Web UI" is upstream's own `dsh web` UI plus a third-party login page. Ideas reused (token hand-off, `documentsDirectory`), code not copied |
| "DeepSeek Harness on NixOS ..." | 2 | Same author as the first, nix-based image `0.1.0-rc.6` | Read only |

## Pinned versions

| Component | Source | Version | Release date | Checked |
|---|---|---|---|---|
| DeepSeek Harness | npm `@deepseek-ai/dsh` (npm `latest` and `next` tags), git tag `dsh-v0.2.1-rc.2` = commit `687f282e8625c6b8d11ff58211a90524be2e4317` | 0.2.1-rc.2 | 2026-10-17 | 2026-10-20 |
| Node.js base | `node:24.22.0-trixie-slim@sha256:7f486cab…c315` | 24.22.0 (Debian 13) | 2026-10-14 | 2026-10-20 |
| Caddy | `caddy:2.11.7-alpine@sha256:d8542f48…5f75f` (binary only) | 2.11.7 (latest) | 2026-10-06 | 2026-10-20 |
| pnpm | npm `pnpm@11.28.5` | 11.28.5 (upstream's `packageManager`; latest 11.x is 11.28.6) | | 2026-10-20 |

Upstream publishes no GitHub releases; it tags `dsh-v*` and publishes to npm. Every published 0.x version is an alpha or release candidate ("developer preview, compatibility-breaking changes"), so the newest `latest`-tagged npm version is pinned.

Upgrade: change `ARG DSH_VERSION` in `services/deepseek-harness/Dockerfile` (check `npm view @deepseek-ai/dsh dist-tags`), redeploy. The build fails if `dsh --version` does not print exactly that version. Rename the listing when the minor version changes (0.3 → "DeepSeek Harness 0.3 ...").

## Architecture

```
 Browser ──HTTPS──► Railway edge ──HTTP──► :8080  Caddy 2.11.7 (user caddy)
                                            │  /healthz            → dsh GET / ; 401 means "up" → 200
                                            │  /api/* + dsh cookie → dsh (dsh checks its signed cookie)
                                            │  everything else     → basic auth (DSH_WEB_USERNAME/PASSWORD)
                                            │      GET / without a dsh session → 303 /?token={launch token}
                                            ▼
                                   127.0.0.1:3080  dsh web 0.2.1-rc.2 (user dsh)
                                            │  --public-url https://{RAILWAY_PUBLIC_DOMAIN}/
                                            │  --trusted-host {RAILWAY_PUBLIC_DOMAIN} [+ DSH_TRUSTED_HOSTS]
                                            │  --patch railway.patch.yml (documentsDirectory)
                                            ▼
  volume /data ── home/            HOME of user dsh (cwd of dsh, git/ssh/pnpm/pip caches)
                  home/.dsh/       DSH_HOME: profiles/web (settings, plugins), .credentials.yaml
                                   (provider keys + cookie signing secret), sessions/, logs/
                  home/Documents/deepseek-harness/default-workspace   first-use workspace
```

`railway-start.sh` (entrypoint, root) validates variables, fixes volume ownership on first boot, hashes the password with `caddy hash-password` (stdin, bcrypt), then:
1. starts `dsh web --patch /opt/dsh-railway/railway.patch.yml --no-open --port 3080 --public-url … --trusted-host …` as user `dsh` with `setpriv --no-new-privs`, from `/data/home`, without the gateway secrets in its environment;
2. reads dsh's output line by line, captures the launch token from the `dsh web: {url}?token=…` readiness line into a root-only file, and prints every line with tokens replaced by `[redacted]`;
3. starts Caddy as user `caddy` with an empty environment except its own settings (no provider keys, no plain password, launch token only here; the `dsh` user cannot read another user's process environment);
4. supervises both: if either exits, the other is stopped and the container exits non-zero, so Railway restarts both together (the launch token is valid only for the dsh process that printed it). SIGTERM is forwarded; dsh gets up to ~10 s to drain.

Why the `/api/*` cookie bypass: dsh authenticates every API call and WebSocket stream with its own cookie, and some browsers (Safari/iOS) do not send basic-auth credentials on WebSocket upgrades. Requests without a dsh cookie, and all page loads, still need the password; a request with a forged cookie name reaches dsh and gets dsh's 401.

Why one container: dsh must stay on loopback (it rejects wildcard binds and upstream says to restrict the port to the proxy), and its state needs the volume, which only one service can mount.

## Service: deepseek-harness

| Setting | Value |
|---|---|
| Source | repo `baranberkay96/dsh-railway`, root `/services/deepseek-harness` (Dockerfile) |
| Start | image ENTRYPOINT `/usr/local/bin/railway-start` (no start command) |
| Healthcheck | `GET /healthz` on `PORT=8080`, timeout 600 s. Answered by Caddy from a live dsh probe, so it turns green only when dsh serves its UI |
| Public domain | yes, target port 8080 |
| TCP proxy | none |
| Volume | `/data` |
| Restart policy | `ALWAYS` (always-on agent; a clean exit after a plugin/config restart must come back) |
| Replicas | 1 (single-writer file state) |

### Variables

| Variable | Default | Required | Notes |
|---|---|---|---|
| `PORT` | `8080` | no | Caddy port = healthcheck port = domain target (Rule 8.1) |
| `DSH_WEB_USERNAME` | `admin` | no | Basic-auth user, validated `[A-Za-z0-9._-]{1,64}` |
| `DSH_WEB_PASSWORD` | `${{secret(32)}}` | no (generated) | The service refuses to start if empty or under 12 characters: never an open agent |
| `DEEPSEEK_API_KEY` | empty | no | Optional. dsh starts and serves its UI without any key; the key can be saved in Settings → Models instead (stored write-only in `.credentials.yaml` on the volume, never exported to the process environment). Agent shells never see it: dsh scrubs `*KEY*`/`*TOKEN*`/`*SECRET*`/`*PASSWORD*` names from child environments |
| `DSH_PERMISSION_MODE` | `workspace-write` | no | Upstream's process fallback for new sessions; validated |
| `DSH_TRUSTED_HOSTS` | empty | no | Extra host names (custom domains), comma-separated, validated as bare `host[:port]` |
| `DSH_TELEMETRY_DISABLED` | `1` | no | Any non-empty value disables upstream's feedback-triggered OTel upload |
| `TZ` | `UTC` | no | Clock and schedules |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `15` | no | Room for dsh's 5 s graceful drain |

Not exposed on purpose: `DSH_HOME` (fixed at `/data/home/.dsh` so state always lands on the volume), `DSH_INTERNAL_PORT` (3080, image ENV), `DSH_PUBLIC_URL` (optional override of the advertised URL, read by the start script if set), other provider keys (other providers must be added in Settings → Models anyway; a key added as a Railway variable such as `OPENROUTER_API_KEY` or `ANTHROPIC_API_KEY` is detected there when the key field is left blank), `DSH_STARTUP_TIMEOUT` (600 s).

### First login

1. Open `https://{your-domain}/`, sign in with `DSH_WEB_USERNAME` / `DSH_WEB_PASSWORD`.
2. Caddy forwards you through dsh's token exchange; dsh sets its session cookie and shows the UI. The cookie lasts 30 days and survives restarts (its signing secret is on the volume); after a restart only the password prompt may appear again.
3. Settings → Models: add a DeepSeek key (default model `deepseek-official` / `deepseek-flash`) or another provider.
4. Choose workspace → the default workspace, or add a folder under `/data/home` (folder picker runs in browse mode for remote hosts).
5. Start a session.

## Improvements over market templates

1. **Current version**: 0.2.1-rc.2 (npm `latest`, 2026-10-17) instead of 0.2.0-rc.2, 0.1.7-alpha.1 or 0.1.0-rc.6.
2. **Password generated with `secret(32)` and enforced**: the most-deployed template generates one too, but the repo-based one ships empty username/password defaults; here an empty or short password stops the service with a clear log message.
3. **Upstream's own session auth stays in force** behind the gate: the template uses dsh's launch-token exchange and signed cookie (30 days, persists across restarts) instead of replacing them, adds `Secure` to the cookie on the HTTPS leg, and keeps dsh's Host/Origin fence on (`--trusted-host` set to the Railway domain).
4. **No patching of upstream code**: the repo-based market template rewrites a compiled upstream file and only works on 0.1.7-alpha.1; in 0.2.1-rc.2 remote settings persist without it.
5. **Healthcheck reflects dsh, not just the proxy**: `/healthz` probes dsh and returns 200 only when the Web UI answers.
6. **Supervision**: dsh and Caddy are restarted together; a dsh crash cannot leave a green proxy in front of a dead agent. Restart policy `ALWAYS` (market: `ON_FAILURE` ×10, which gives up).
7. **Privilege separation**: dsh and every agent command run as `dsh` (UID 10001) with no-new-privs; the gate runs as `caddy`, whose environment (password hash, launch token) the agent cannot read; provider keys never reach Caddy.
8. **Launch token kept out of logs**: the readiness line and any other output (including Caddy error logs) are redacted.
9. **Default workspace on the volume** via upstream's `documentsDirectory` setting (Linux containers have no `xdg-user-dir`, so upstream would start without one).
10. **Plugins work**: pnpm 11 in the image (dsh's plugin manager needs it on PATH); profile, plugin store and caches live on the volume.
11. **Agent toolbox**: git, Python 3.13 + venv/pip, build-essential, ripgrep, jq, curl, ssh, zip; bubblewrap for dsh's sandbox probe (Landlock fallback ships with dsh).
12. **Custom domains** supported through `DSH_TRUSTED_HOSTS` (market templates hard-wire the Railway domain).
13. **Privacy defaults documented**: OTel upload off; the DeepSeek session-log upload switch is explained in the README.
14. **Build-time checks**: the image build fails if the dsh version, the Web frontend dist, the node-pty Linux prebuild, pnpm or the Caddyfile are missing or invalid.

## Resource estimate

Railway prices: RAM $10/GB-month, vCPU $20/vCPU-month, volume $0.15/GB-month. Estimates, not measured (no container run).

| Service | Idle RAM / CPU | Typical RAM / CPU | Notes |
|---|---|---|---|
| deepseek-harness (dsh + Caddy) | ~0.35 GB / 0.01-0.02 vCPU | 0.8-1.5 GB / 0.1-0.2 vCPU | dsh is one Node.js process (~150 plugin packages, in-memory SQLite session index); Caddy ~20 MB. Peaks come from what the agent runs (npm/pip installs, builds, tests). One market template reports 164 MiB idle for 0.2.0-rc.2 |
| Volume | 0.2 GB | 2-5 GB | Sessions, caches, plugin store, cloned repositories |

Estimated monthly cost: **idle ≈ $4-5**, **typical ≈ $12-20**. Model usage is billed by the provider.

Minimum plan: **Trial** (1 GB RAM per service) boots and idles, but agent builds can hit the limit; **Hobby** is the realistic plan (5 GB volume per service is enough for a few repositories). The image is large (~1.5 GB, toolchain included), first build ≈ 5-8 minutes.

## Verification results (2026-10-20, no Docker)

| Check | How | Result |
|---|---|---|
| `docker build --platform linux/amd64` | Docker | **not run** (no Docker by instruction) |
| Container run, Railway deploy | | **not run** |
| `railway-start.sh` syntax | `bash -n` (macOS bash 3.2; image has bash 5.2) | OK; also checked again at image build time |
| `railway-start.sh` behaviour | run locally as non-root with stub `dsh` and `caddy` executables (privilege drop skipped when not root) | normal start: token captured, Caddy started with token/hash/user/ports and an otherwise empty environment, dsh started with the expected arguments, cwd `/data/home`, `DSH_HOME`/`DSH_DOCUMENTS_DIR`/`DSH_PERMISSION_MODE` set and **no** `DSH_WEB_PASSWORD`; tokens redacted in dsh stdout, stderr and Caddy logs; SIGTERM stops both and exits 0; dsh crash → Caddy stopped, exit 1; Caddy crash → dsh stopped, exit 1; dsh failing during startup → exit 1 with message; startup timeout; empty/short password, bad username, bad host, bad permission mode, equal ports, bad timeout all rejected; no leftover processes or run directories |
| Caddyfile | Caddy v2.11.7 source read for `basic_auth` (bcrypt default, hash cache on), `hash-password` stdin, `header_down` regex replacement per `Set-Cookie` value, `handle_response`/response matchers, `handle_errors` codes | consistent; **not executed** (no Caddy binary locally); the Dockerfile runs `caddy validate` at build time |
| npm versions | `npm view` | `@deepseek-ai/dsh@0.2.1-rc.2` exists (dist-tag latest); all 86 direct dependencies resolve on npm (78 pinned at exactly `0.2.1-rc.2`, 8 third-party/Cordis ranges); `@deepseek-ai/dsh-web-frontend@0.2.1-rc.2` ships `dist/index.html`; `pnpm@11.28.5` exists; `node-pty@1.2.0-beta.15` ships `prebuilds/linux-x64`; `koffi@3.1.1` and `@vscode/ripgrep@1.18.0` use per-platform optional packages; `@deepseek-ai/node-addon-system@0.1.2` has a linux-x64 package |
| Images | Docker Hub API | `node:24.22.0-trixie-slim` (amd64 digest present, 2026-10-14), `caddy:2.11.7-alpine` is the latest Caddy tag and its digest matches the one pinned in other packages in this repo |
| Debian packages | packages.debian.org (trixie) | all apt packages exist; `/usr/bin/setpriv` is in `util-linux` (essential) |
| Upstream CLI/flags | source at `dsh-v0.2.1-rc.2`: `args.ts`, `startup.ts`, `web-app/src/index.ts` | `dsh web --patch X --no-open --port N --public-url U --trusted-host H` parses as launcher flags then app flags; readiness line format `dsh web: {url}?token={base64url}` |
| template.json | `_tools/to_serialized.py` | converts (1 service, volume `/data`, domain on 8080, Dockerfile builder); description 75 chars; every variable described |
| Icon | HTTP GET | 200 (7.3 kB SVG) |

## Verification checklist (first deploy)

- [ ] Build log: `0.2.1-rc.2` printed by `dsh --version`, pnpm version printed, `caddy validate` passes.
- [ ] Deploy log: `[railway] public address: https://{domain}/ …`, `starting dsh 0.2.1-rc.2`, `dsh web: https://{domain}/?token=[redacted]`, `dsh is ready after ~Ns`, `Caddy password gate listening on port 8080`; healthcheck `/healthz` green.
- [ ] `curl -i https://{domain}/` → 401 with `WWW-Authenticate: Basic`; `curl -i https://{domain}/api/anything` → 401; `curl -i https://{domain}/healthz` → 200 `ok`.
- [ ] Browser: password prompt → UI loads; the address bar ends at `/` (token removed); cookie `dsh-auth-…` is `HttpOnly; SameSite=Strict; Secure`.
- [ ] Settings → Models: save a DeepSeek key; send a prompt; reply streams (WebSocket through Caddy). Repeat on iOS Safari.
- [ ] Ask the agent to run `id; pwd; touch x` in the default workspace: runs as `dsh`, approval prompts appear for wider writes. Check the log for the sandbox runner (bwrap or Landlock) or a `SANDBOX_UNAVAILABLE` error.
- [ ] Plugins page: install one official optional bundle; confirm pnpm runs and the bundle survives a redeploy.
- [ ] Redeploy: still signed in (cookie survives), sessions, settings, key and workspace files still there.
- [ ] Kill dsh from `railway ssh` (`pkill -f "dsh web"`): container restarts, UI comes back.
- [ ] `railway ssh`: `cat /proc/$(pgrep -u caddy caddy)/environ` as user `dsh` fails (permission denied).

## Open questions

- **Nothing has been built or run in a container.** The first Railway build is the first build of this Dockerfile. Most likely failure points: `npm install --global` of the full dependency closure (native addons, a transitive package range resolving to a broken release), and `caddy validate`.
- **Sandbox on Railway is unverified.** dsh's `workspace-write` mode confines bash with bubblewrap (needs unprivileged user namespaces) or Landlock (needs kernel support); if neither works in Railway's containers, shell commands fail closed with `SANDBOX_UNAVAILABLE`. Workaround: switch the session (or `DSH_PERMISSION_MODE`) to `danger-full-access`, which also turns off approval prompts; the container stays the boundary.
- **WebSocket path**: the `/api/*` cookie bypass is reasoned from dsh's source (every API call and stream is cookie-authenticated); not exercised in a browser.
- **Trademark**: upstream's `BRAND_GUIDELINES.md` asks projects not to use the full "DeepSeek Harness" mark in project names and not to imply endorsement. The listing deploys the unmodified upstream software and says "community template, not affiliated", but the name still starts with "DeepSeek Harness". A safer variant is "DSH 0.2 (DeepSeek Harness) Coding Agent with Web UI"; the decision is left to the publisher. The app icon is used for the listing.
- **Session-log upload** to DeepSeek is upstream's default when the official DeepSeek API is used; left as upstream ships it and documented, because the template cannot change it without locking the Web UI switch.
- Office document skills, the DeepSeek account sign-in flow and the Python SDK/ACP surfaces were not examined for remote use; API clients cannot use `/connect?token=…` because the launch token is never shown.
- Memory and CPU figures are estimates.

## Naming note (trademark)

Upstream's BRAND_GUIDELINES.md asks that project names use "DSH" rather than the full "DeepSeek Harness" trademark, that descriptions say "built on DeepSeek Harness", and that official brand materials are not used in a way that suggests endorsement. The listing name, repo name (`baranberkay96/dsh-railway`), README headings and icon (a neutral terminal icon instead of the upstream logo) follow that.
