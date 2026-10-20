# Deploy and Host DSH with Railway

Run DSH (`dsh`), the open-source agent harness built on DeepSeek Harness, as an always-on coding agent with its browser UI. It reads and edits files, runs commands, delegates to subagents, schedules tasks and loads plugins, while sessions, settings and workspaces stay on a Railway volume. This is a community template, not affiliated with or endorsed by DeepSeek.

## About Hosting DSH

Upstream runs the Web UI with `npx @deepseek-ai/dsh web` on `127.0.0.1:3080`, so it lives only as long as your laptop does. This template installs the pinned npm release 0.2.1-rc.2 in one container and keeps the Harness on loopback, following upstream's reverse-proxy guide. A Caddy reverse proxy in the same container owns the public port: it asks for a generated password first, then hands your browser the Harness's own login token, so you sign in once and the Harness's signed session cookie keeps you signed in for 30 days, across restarts. Railway's edge supplies HTTPS. The agent runs as an unprivileged user with upstream's sandbox and approval prompts.

## Common Use Cases

- A coding agent you can reach from any browser or phone that keeps working on a repository while your laptop is closed
- Repository summaries, refactors, test runs and dependency upgrades on code cloned into the persistent workspace
- Scheduled reminders and recurring checks with the Harness's built-in scheduler
- Trying DSH plugins, agent presets and different model providers (DeepSeek, Anthropic, OpenAI, OpenRouter, Kimi, GLM or any compatible gateway) without a local install

## Dependencies for DSH Hosting

- A model provider key: a DeepSeek API key for the default model (set `DEEPSEEK_API_KEY` or enter it in **Settings → Models**), or any other supported provider added in the Web UI
- A Railway volume at `/data` (included) for settings, credentials, sessions, plugins and workspaces

### Deployment Dependencies

- DeepSeek Harness repository: https://github.com/deepseek-ai/deepseek-harness
- npm package: https://www.npmjs.com/package/@deepseek-ai/dsh
- Web UI guide: https://github.com/deepseek-ai/deepseek-harness/blob/dsh-v0.2.1-rc.2/docs/user/guide/index.md
- Reverse-proxy guide: https://github.com/deepseek-ai/deepseek-harness/blob/dsh-v0.2.1-rc.2/docs/user/guide/public-deployments.md
- Model configuration: https://github.com/deepseek-ai/deepseek-harness/blob/dsh-v0.2.1-rc.2/docs/user/guide/providers.md
- Safety notice: https://github.com/deepseek-ai/deepseek-harness/blob/dsh-v0.2.1-rc.2/SAFETY.md
- DeepSeek API keys: https://platform.deepseek.com/
- Caddy: https://caddyserver.com/docs/

### Implementation Details

| Service | Source | Purpose |
|---|---|---|
| deepseek-harness | Dockerfile in `services/deepseek-harness` (Node.js 24, `@deepseek-ai/dsh@0.2.1-rc.2`, pnpm 11.28.5, Caddy 2.11.7) | dsh Web UI on `127.0.0.1:3080` behind a Caddy password gate on port 8080, healthcheck `/healthz`, volume at `/data` |

**First login**

1. Open the service's public URL. The browser asks for a username and password.
2. Sign in with `DSH_WEB_USERNAME` (default `admin`) and `DSH_WEB_PASSWORD` (Railway → deepseek-harness → Variables). You land in the DSH Web UI.
3. If you did not set `DEEPSEEK_API_KEY`, open **Settings → Models**, enter a DeepSeek key, or add another provider.
4. Choose or create a workspace. The default workspace is `/data/home/Documents/deepseek-harness/default-workspace`; clone repositories anywhere under `/data/home` and add them with the folder picker.
5. Start a session and send a task, for example "Summarize this repository".

**Security model**: the password protects the page and the hand-out of the Harness's login token; after that, the Harness checks its own signed, HttpOnly session cookie on every API call and WebSocket stream. The agent can run shell commands and spend API credits, so keep the password private and set spending limits at your provider. New sessions use upstream's `workspace-write` preset: writes limited to the session workspace, approval prompts for anything wider. Read [SAFETY.md](https://github.com/deepseek-ai/deepseek-harness/blob/dsh-v0.2.1-rc.2/SAFETY.md) before giving it access to anything sensitive.

**Privacy defaults**: OpenTelemetry upload is off (`DSH_TELEMETRY_DISABLED=1`). Upstream's session-log upload to DeepSeek is on by default when you use the official DeepSeek API; switch it off in **Settings → General → Upload Session Log when using the official model API** if you prefer.

**Custom domain**: add it in Railway and list it in `DSH_TRUSTED_HOSTS` (for example `agent.example.com`), then redeploy. The Harness refuses API calls from host names it does not trust.

**Scaling**: the Harness is a single-writer process with file-based state on one volume. Keep one replica and scale vertically; give it more memory if the agent builds large projects.

**Pinning and upgrades**: the Dockerfile pins `DSH_VERSION=0.2.1-rc.2` (npm), `PNPM_VERSION`, the Node.js and Caddy images. To upgrade, change `DSH_VERSION` to a newer release from npm and redeploy; the volume keeps settings, credentials and sessions. The project is a developer preview with breaking changes between releases, so read the release notes first.

### Why Deploy DSH on Railway?

An agent harness is most useful when it keeps running after you close the lid. Railway gives it an HTTPS address, a persistent volume, automatic restarts and logs without a server to maintain, and you pay for the little RAM and CPU it uses between tasks. Model usage is billed by your provider.
