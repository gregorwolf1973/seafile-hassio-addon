#!/usr/bin/env bash
# Main entrypoint for the Seafile HA add-on.
set -e

# ── Load HA configuration ─────────────────────────────────────────────────
if command -v bashio &>/dev/null && [ -f /data/options.json ]; then
    source /usr/lib/bashio/bashio.sh
    ADMIN_EMAIL=$(bashio::config 'admin_email')
    ADMIN_PASSWORD=$(bashio::config 'admin_password')
    SERVER_NAME=$(bashio::config 'server_name')
    SERVER_HOSTNAME=$(bashio::config 'server_hostname')
    TIME_ZONE=$(bashio::config 'time_zone')
    bashio::log.info "=== Seafile add-on starting ==="
else
    ADMIN_EMAIL="${SEAFILE_ADMIN_EMAIL:-admin@example.com}"
    ADMIN_PASSWORD="${SEAFILE_ADMIN_PASSWORD:-seafile_admin}"
    SERVER_NAME="${SEAFILE_SERVER_NAME:-MySeafile}"
    SERVER_HOSTNAME="${SEAFILE_SERVER_HOSTNAME:-localhost:8080}"
    TIME_ZONE="${TIME_ZONE:-Europe/Berlin}"
    echo "=== Seafile starting (standalone mode) ==="
fi

# ── Persistence layout ────────────────────────────────────────────────────
# Everything Seafile expects under /shared lives in /config/seafile/shared,
# so the entire installation (conf, ccnet, seafile-data, seahub-data,
# nginx config, ssl) survives add-on rebuilds.

PERSIST=/config/seafile
SHARED_PERSIST="${PERSIST}/shared"
mkdir -p "${PERSIST}/mariadb" "${SHARED_PERSIST}"

# Replace the container-internal /shared with a symlink to persistent storage.
if [ ! -L /shared ]; then
    if [ -d /shared ] && [ -n "$(ls -A /shared 2>/dev/null)" ]; then
        cp -a /shared/. "${SHARED_PERSIST}/" 2>/dev/null || true
    fi
    rm -rf /shared
    ln -sfn "${SHARED_PERSIST}" /shared
fi

# Detect (and clean up) a half-finished setup from earlier add-on versions:
# seafile-data exists but seafile.conf was never written by setup.
if [ -d /shared/seafile/seafile-data ] && [ ! -f /shared/seafile/conf/seafile.conf ]; then
    echo "[Seafile] Incomplete previous setup detected — wiping /shared/seafile to rerun setup."
    rm -rf /shared/seafile
fi

# Pre-create only what Seafile's bootstrap needs but does not create itself
# (it does `mv`, never `mkdir -p`). Setup will create everything else.
mkdir -p /shared/nginx/conf

# nginx runtime directories (the upstream image is missing them)
mkdir -p /var/run/nginx /var/lib/nginx /var/log/nginx

# ── DB root password (generated once, then reused) ────────────────────────
DB_PASS_FILE="${PERSIST}/.db_root_pass"
if [ ! -f "${DB_PASS_FILE}" ]; then
    openssl rand -hex 20 > "${DB_PASS_FILE}"
    chmod 600 "${DB_PASS_FILE}"
fi
DB_ROOT_PASS=$(cat "${DB_PASS_FILE}")

# ── Start embedded MariaDB ────────────────────────────────────────────────
/start-mariadb.sh "${PERSIST}/mariadb" "${DB_ROOT_PASS}"

# ── Configure Seafile environment ─────────────────────────────────────────
export DB_HOST=127.0.0.1
export DB_ROOT_PASSWD="${DB_ROOT_PASS}"
export SEAFILE_ADMIN_EMAIL="${ADMIN_EMAIL}"
export SEAFILE_ADMIN_PASSWORD="${ADMIN_PASSWORD}"
export SEAFILE_SERVER_LETSENCRYPT=false
export SEAFILE_SERVER_HOSTNAME="${SERVER_HOSTNAME}"
export TIME_ZONE="${TIME_ZONE}"

# ── Hand off to the official Seafile startup script ───────────────────────
echo "[Seafile] Launching Seafile (hostname: ${SERVER_HOSTNAME}) ..."
exec /scripts/start.py
