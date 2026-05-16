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
# /config/seafile/ — MariaDB data + Seafile conf (survives add-on updates)
# /share/seafile-data/ — user files (accessible from other add-ons / SMB)

PERSIST=/config/seafile
mkdir -p \
    "${PERSIST}/mariadb" \
    "${PERSIST}/logs"

# Seafile expects this directory layout under /shared. Create everything
# up-front so its bootstrap script (which only does `mv`, never `mkdir -p`)
# can place files where it wants them.
mkdir -p \
    /shared \
    /shared/nginx/conf \
    /shared/logs/var-log \
    /shared/seafile/conf \
    /shared/seafile/ccnet \
    /shared/seafile/seafile-data \
    /shared/seafile/seahub-data \
    /shared/seafile/seahub-data/avatars \
    /shared/seafile/seahub-data/custom \
    /shared/ssl

# nginx runtime directories (the seafile-mc image doesn't ship them)
mkdir -p /var/run/nginx /var/lib/nginx /var/log/nginx

# Redirect user file storage to /share so it is reachable from other add-ons.
# Only convert to a symlink on first start (when seafile-data is still empty).
if [ ! -L /shared/seafile/seafile-data ]; then
    mkdir -p /share/seafile-data
    if [ -d /shared/seafile/seafile-data ] && [ -n "$(ls -A /shared/seafile/seafile-data 2>/dev/null)" ]; then
        cp -a /shared/seafile/seafile-data/. /share/seafile-data/ 2>/dev/null || true
    fi
    rm -rf /shared/seafile/seafile-data
    ln -sfn /share/seafile-data /shared/seafile/seafile-data
fi

# Persist Seafile logs in /config (logs/var-log is for nginx/syslog files)
if [ ! -L /shared/logs ] || [ "$(readlink /shared/logs)" != "${PERSIST}/logs" ]; then
    rm -rf /shared/logs
    ln -sfn "${PERSIST}/logs" /shared/logs
    mkdir -p "${PERSIST}/logs/var-log"
fi

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
