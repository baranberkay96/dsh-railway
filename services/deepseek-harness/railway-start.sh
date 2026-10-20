#!/usr/bin/env bash
# Container entrypoint for the DeepSeek Harness Railway template.
#
# Runs as root only to prepare the /data volume and hash the password, then
# starts two unprivileged processes and supervises them:
#   1. dsh (the official DeepSeek Harness CLI, Web profile) as user "dsh",
#      listening on 127.0.0.1 only. Once ready it prints a URL carrying a fresh
#      per-process launch token; this script captures the token and removes it
#      from the logs.
#   2. Caddy as user "caddy" on Railway's PORT: basic-auth password gate,
#      /healthz, and the hand-off of the launch token to signed-in browsers.
# If either process exits, the other one is stopped and the container exits,
# so Railway's restart policy brings both back together (the launch token is
# only valid for the dsh process that printed it).
#
# Railway's PID 1 is its own init (podman-init); this script is its child and
# forwards SIGTERM/SIGINT to both processes.
set -Eeuo pipefail

DATA_DIR="${DATA_DIR:-/data}"
HOME_DIR="${DSH_USER_HOME:-${DATA_DIR}/home}"
DSH_HOME_DIR="${DSH_HOME:-${HOME_DIR}/.dsh}"
DOCUMENTS_DIR="${DSH_DOCUMENTS_DIR:-${HOME_DIR}/Documents}"
PATCH_FILE="${DSH_RAILWAY_PATCH:-/opt/dsh-railway/railway.patch.yml}"
CADDYFILE="${CADDYFILE:-/etc/caddy/Caddyfile}"
DSH_BIN="${DSH_BIN:-dsh}"
CADDY_BIN="${CADDY_BIN:-caddy}"
SETPRIV_BIN="${SETPRIV_BIN:-setpriv}"
DSH_RUN_USER="${DSH_RUN_USER:-dsh}"
CADDY_RUN_USER="${CADDY_RUN_USER:-caddy}"
STARTUP_TIMEOUT="${DSH_STARTUP_TIMEOUT:-600}"
PUBLIC_PORT="${PORT:-8080}"
INTERNAL_PORT="${DSH_INTERNAL_PORT:-3080}"
WEB_USER="${DSH_WEB_USERNAME:-admin}"
WEB_PASSWORD="${DSH_WEB_PASSWORD:-}"
PERMISSION_MODE="${DSH_PERMISSION_MODE:-workspace-write}"
CADDY_PATH="${CADDY_PATH:-/usr/local/bin:/usr/bin:/bin}"
DSH_VERSION_LABEL="$(cat /opt/dsh-railway/DSH_VERSION 2>/dev/null || echo '(version unknown)')"
TOKEN_PATTERN='[?&]token=([A-Za-z0-9_-]+)'
PRIV=()
TRUSTED_HOSTS=()
PUBLIC_URL=""
TOKEN_FILE=""
PASSWORD_HASH=""

DSH_PID=""
CADDY_PID=""
STOPPING=""
RUN_DIR=""

log() { printf '[railway] %s\n' "$*"; }
warn() { printf '[railway] WARNING: %s\n' "$*" >&2; }
die() {
	printf '[railway] ERROR: %s\n' "$*" >&2
	stop_children
	exit 1
}

stop_children() {
	if [[ -n "$CADDY_PID" ]]; then kill -TERM "$CADDY_PID" 2>/dev/null || true; fi
	if [[ -n "$DSH_PID" ]]; then kill -TERM "$DSH_PID" 2>/dev/null || true; fi
}

on_signal() {
	STOPPING="$1"
	log "received SIG$1, stopping dsh and Caddy"
	stop_children
}

cleanup() {
	if [[ -n "$RUN_DIR" ]]; then rm -rf "$RUN_DIR"; fi
}

is_port() {
	[[ "$1" =~ ^[0-9]{1,5}$ ]] && ((10#$1 >= 1 && 10#$1 <= 65535))
}

# Copies dsh/Caddy output to the container log line by line. Launch tokens are
# replaced with [redacted]; with a target file, the first token from a
# "dsh web: <url>" line is also written there (mode 0600) for Caddy.
filter_output() {
	local token_file="${1:-}" line token
	while IFS= read -r line || [[ -n "$line" ]]; do
		while [[ "$line" =~ $TOKEN_PATTERN ]]; do
			token="${BASH_REMATCH[1]}"
			if [[ -n "$token_file" && "$line" == "dsh web: "* && ! -s "$token_file" ]]; then
				(umask 077 && printf '%s\n' "$token" >"${token_file}.tmp" && mv "${token_file}.tmp" "$token_file")
			fi
			line="${line//token=${token}/token=[redacted]}"
		done
		printf '%s\n' "$line"
	done
}

owner_uid() {
	ls -nd "$1" | awk '{print $3}'
}

validate_settings() {
	is_port "$PUBLIC_PORT" || die "PORT must be a TCP port number, got '${PUBLIC_PORT}'"
	is_port "$INTERNAL_PORT" || die "DSH_INTERNAL_PORT must be a TCP port number, got '${INTERNAL_PORT}'"
	[[ "$PUBLIC_PORT" != "$INTERNAL_PORT" ]] || die "PORT and DSH_INTERNAL_PORT must differ (both are ${PUBLIC_PORT})"
	[[ "$WEB_USER" =~ ^[A-Za-z0-9._-]{1,64}$ ]] ||
		die "DSH_WEB_USERNAME may only use letters, digits, '.', '_' and '-' (1-64 characters)"
	[[ -n "$WEB_PASSWORD" ]] ||
		die "DSH_WEB_PASSWORD is empty. This agent can run shell commands and spend API credits, so it never starts without a password. Set DSH_WEB_PASSWORD on the service and redeploy."
	((${#WEB_PASSWORD} >= 12)) || die "DSH_WEB_PASSWORD must be at least 12 characters long"
	case "$WEB_PASSWORD" in
	*$'\n'* | *$'\r'*) die "DSH_WEB_PASSWORD must be a single line" ;;
	esac
	case "$PERMISSION_MODE" in
	read-only | workspace-write | danger-full-access) ;;
	*) die "DSH_PERMISSION_MODE must be read-only, workspace-write or danger-full-access, got '${PERMISSION_MODE}'" ;;
	esac
	[[ "$STARTUP_TIMEOUT" =~ ^[0-9]+$ ]] || die "DSH_STARTUP_TIMEOUT must be a number of seconds"
}

# Fills TRUSTED_HOSTS (authorities dsh's Host/Origin fence must accept) and
# PUBLIC_URL (the address dsh advertises to the agent and in its logs).
resolve_public_address() {
	local entries=() entry
	TRUSTED_HOSTS=()
	PUBLIC_URL="${DSH_PUBLIC_URL:-}"
	if [[ -n "${RAILWAY_PUBLIC_DOMAIN:-}" ]]; then
		entries+=("$RAILWAY_PUBLIC_DOMAIN")
		[[ -n "$PUBLIC_URL" ]] || PUBLIC_URL="https://${RAILWAY_PUBLIC_DOMAIN}/"
	fi
	if [[ -n "${DSH_TRUSTED_HOSTS:-}" ]]; then
		IFS=', ' read -r -a extra <<<"$DSH_TRUSTED_HOSTS"
		entries+=(${extra[@]+"${extra[@]}"})
	fi
	for entry in ${entries[@]+"${entries[@]}"}; do
		[[ -n "$entry" ]] || continue
		[[ "$entry" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?(:[0-9]{1,5})?$ ]] ||
			die "'${entry}' is not a bare host name (DSH_TRUSTED_HOSTS takes names like agent.example.com, without https:// or paths)"
		TRUSTED_HOSTS+=("$entry")
	done
	if [[ -n "$PUBLIC_URL" && ! "$PUBLIC_URL" =~ ^https?://[^[:space:]]+$ ]]; then
		die "DSH_PUBLIC_URL must be an http(s) URL, got '${PUBLIC_URL}'"
	fi
	if ((${#TRUSTED_HOSTS[@]} == 0)); then
		warn "no public domain: generate one in Settings -> Networking (target port ${PUBLIC_PORT}); until then the Web UI is not reachable from a browser"
	else
		log "public address: ${PUBLIC_URL:-none} (trusted hosts: ${TRUSTED_HOSTS[*]})"
	fi
}

prepare_volume() {
	mkdir -p "$DATA_DIR" "$HOME_DIR" "$DSH_HOME_DIR" "$DOCUMENTS_DIR"
	if [[ "$(id -u)" != "0" ]]; then
		warn "not running as root; skipping volume ownership fix and privilege drop"
		return
	fi
	local uid
	uid="$(id -u "$DSH_RUN_USER")"
	# A fresh Railway volume is root-owned. Fix ownership recursively only when
	# the home directory is not owned by the dsh user yet (first boot, or files
	# restored as root), so large workspaces do not slow down every start.
	if [[ "$(owner_uid "$HOME_DIR")" != "$uid" ]]; then
		log "setting ownership of ${HOME_DIR} to ${DSH_RUN_USER} (first boot)"
		chown -R "${DSH_RUN_USER}:${DSH_RUN_USER}" "$HOME_DIR"
	fi
	chown "${DSH_RUN_USER}:${DSH_RUN_USER}" "$DSH_HOME_DIR" "$DOCUMENTS_DIR"
	chmod 0700 "$HOME_DIR" "$DSH_HOME_DIR"
}

# Fills PRIV with the command prefix that drops root to the given user
# (numeric ids, no new privileges). Without root (local tests) PRIV is empty.
privilege_prefix() {
	local user="$1" groups_flag="$2"
	PRIV=()
	if [[ "$(id -u)" == "0" ]]; then
		PRIV=("$SETPRIV_BIN" "--reuid=$(id -u "$user")" "--regid=$(id -g "$user")" "$groups_flag" --no-new-privs --)
	fi
}

start_dsh() {
	local args=(web --patch "$PATCH_FILE" --no-open --port "$INTERNAL_PORT") host
	[[ -z "$PUBLIC_URL" ]] || args+=(--public-url "$PUBLIC_URL")
	for host in ${TRUSTED_HOSTS[@]+"${TRUSTED_HOSTS[@]}"}; do
		args+=(--trusted-host "$host")
	done
	privilege_prefix "$DSH_RUN_USER" --init-groups
	log "starting dsh ${DSH_VERSION_LABEL} on 127.0.0.1:${INTERNAL_PORT} (permission mode ${PERMISSION_MODE})"
	(
		cd "$HOME_DIR"
		# The agent's shells inherit this environment: drop the gateway secrets.
		unset DSH_WEB_PASSWORD DSH_WEB_PASSWORD_HASH DSH_LAUNCH_TOKEN WEB_PASSWORD PASSWORD_HASH
		export HOME="$HOME_DIR" USER="$DSH_RUN_USER" LOGNAME="$DSH_RUN_USER" SHELL=/bin/bash
		export DSH_HOME="$DSH_HOME_DIR" DSH_DOCUMENTS_DIR="$DOCUMENTS_DIR" DSH_PERMISSION_MODE="$PERMISSION_MODE"
		exec ${PRIV[@]+"${PRIV[@]}"} "$DSH_BIN" "${args[@]}"
	) > >(filter_output "$TOKEN_FILE") 2>&1 &
	DSH_PID=$!
}

wait_for_token() {
	local waited=0
	until [[ -s "$TOKEN_FILE" ]]; do
		[[ -z "$STOPPING" ]] || exit 0
		if ! kill -0 "$DSH_PID" 2>/dev/null; then
			local code=0
			wait "$DSH_PID" || code=$?
			DSH_PID=""
			die "dsh exited during startup (exit code ${code}); see the lines above. Startup reports are kept in ${DSH_HOME_DIR}/logs/"
		fi
		((waited < STARTUP_TIMEOUT)) || die "dsh did not report readiness within ${STARTUP_TIMEOUT}s"
		sleep 1
		waited=$((waited + 1))
	done
	log "dsh is ready after ~${waited}s"
}

start_caddy() {
	local token
	token="$(head -n 1 "$TOKEN_FILE")"
	[[ "$token" =~ ^[A-Za-z0-9_-]+$ ]] || die "could not read dsh's launch token"
	privilege_prefix "$CADDY_RUN_USER" --clear-groups
	(
		cd /
		# Caddy gets a minimal environment: no provider keys, no plain password.
		exec env -i \
			PATH="$CADDY_PATH" \
			HOME="${RUN_DIR}/caddy" XDG_CONFIG_HOME="${RUN_DIR}/caddy/config" XDG_DATA_HOME="${RUN_DIR}/caddy/data" \
			PORT="$PUBLIC_PORT" DSH_INTERNAL_PORT="$INTERNAL_PORT" \
			DSH_WEB_USERNAME="$WEB_USER" DSH_WEB_PASSWORD_HASH="$PASSWORD_HASH" DSH_LAUNCH_TOKEN="$token" \
			${PRIV[@]+"${PRIV[@]}"} "$CADDY_BIN" run --config "$CADDYFILE" --adapter caddyfile
	) > >(filter_output) 2>&1 &
	CADDY_PID=$!
	log "Caddy password gate listening on port ${PUBLIC_PORT} (user '${WEB_USER}')"
}

# Sends SIGTERM to both processes and waits up to ~10 s (dsh drains for up to
# 5 s), then SIGKILL. Railway kills the container after its draining period.
stop_and_wait() {
	local tries=0 pid
	stop_children
	while ((tries < 20)); do
		pid=""
		if [[ -n "$DSH_PID" ]] && kill -0 "$DSH_PID" 2>/dev/null; then pid="$DSH_PID"; fi
		if [[ -n "$CADDY_PID" ]] && kill -0 "$CADDY_PID" 2>/dev/null; then pid="${pid} ${CADDY_PID}"; fi
		[[ -n "${pid// /}" ]] || return 0
		sleep 0.5
		tries=$((tries + 1))
	done
	warn "forcing shutdown of:${pid}"
	kill -KILL $pid 2>/dev/null || true
}

supervise() {
	local code=0 name=""
	while [[ -z "$name" ]]; do
		if ! kill -0 "$DSH_PID" 2>/dev/null; then
			name="dsh"
			wait "$DSH_PID" || code=$?
		elif ! kill -0 "$CADDY_PID" 2>/dev/null; then
			name="Caddy"
			wait "$CADDY_PID" || code=$?
		else
			sleep 1 &
			wait $! || true
		fi
	done
	if [[ -n "$STOPPING" ]]; then
		stop_and_wait
		log "stopped"
		exit 0
	fi
	warn "${name} exited unexpectedly (exit code ${code}); stopping the container so Railway restarts it"
	stop_and_wait
	exit 1
}

main() {
	trap 'on_signal TERM' TERM
	trap 'on_signal INT' INT
	trap cleanup EXIT

	validate_settings
	resolve_public_address
	prepare_volume

	# Private run directory: the token file stays root-only (0600); Caddy may
	# only traverse it to reach its own scratch directory.
	RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dsh-railway.XXXXXX")"
	chmod 0711 "$RUN_DIR"
	TOKEN_FILE="${RUN_DIR}/launch-token"
	mkdir -p "${RUN_DIR}/caddy/config" "${RUN_DIR}/caddy/data"
	if [[ "$(id -u)" == "0" ]]; then
		chown -R "${CADDY_RUN_USER}:${CADDY_RUN_USER}" "${RUN_DIR}/caddy"
	fi

	# bcrypt hash for Caddy's basic_auth; the password is passed on stdin so it
	# never appears in a process list.
	PASSWORD_HASH="$(printf '%s\n' "$WEB_PASSWORD" | "$CADDY_BIN" hash-password)" ||
		die "could not hash DSH_WEB_PASSWORD with caddy hash-password"
	[[ -n "$PASSWORD_HASH" ]] || die "caddy hash-password returned an empty hash"
	unset WEB_PASSWORD DSH_WEB_PASSWORD

	start_dsh
	wait_for_token
	start_caddy
	supervise
}

main "$@"
