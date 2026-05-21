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
    COLLABORA_URL=$(bashio::config 'collabora_url')
    SERVICE_URL=$(bashio::config 'service_url')
    FILE_SERVER_ROOT=$(bashio::config 'file_server_root')
    VERBOSE_LOGS=$(bashio::config 'verbose_logs')
    DJANGO_DEBUG=$(bashio::config 'django_debug')
    bashio::log.info "=== Seafile add-on starting ==="
else
    ADMIN_EMAIL="${SEAFILE_ADMIN_EMAIL:-admin@example.com}"
    ADMIN_PASSWORD="${SEAFILE_ADMIN_PASSWORD:-seafile_admin}"
    SERVER_NAME="${SEAFILE_SERVER_NAME:-MySeafile}"
    SERVER_HOSTNAME="${SEAFILE_SERVER_HOSTNAME:-localhost:8080}"
    TIME_ZONE="${TIME_ZONE:-Europe/Berlin}"
    COLLABORA_URL="${COLLABORA_URL:-}"
    SERVICE_URL="${SERVICE_URL:-}"
    FILE_SERVER_ROOT="${FILE_SERVER_ROOT:-}"
    VERBOSE_LOGS="${VERBOSE_LOGS:-false}"
    DJANGO_DEBUG="${DJANGO_DEBUG:-false}"
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

# ── Apply Collabora / SERVICE_URL settings (idempotent) ───────────────────
# seahub_settings.py is created by setup-seafile-mysql.py during the very
# first start, so on first boot the file does not exist yet. In that case
# we drop a my_init.d hook that patches the file once it exists, then
# restarts seahub. On every subsequent boot we just patch directly.

apply_seahub_settings() {
    local settings=/shared/seafile/conf/seahub_settings.py
    [ -f "${settings}" ] || return 1

    # Strip any previous block we wrote, so changes in HA options take effect.
    sed -i '/# >>> HA add-on managed block >>>/,/# <<< HA add-on managed block <<</d' "${settings}"

    {
        echo ""
        echo "# >>> HA add-on managed block >>>"
        if [ -n "${SERVICE_URL}" ]; then
            echo "SERVICE_URL = '${SERVICE_URL%/}'"
            echo "CSRF_TRUSTED_ORIGINS = ['${SERVICE_URL%/}']"
            # Reverse-proxy terminates TLS; trust the X-Forwarded-Proto header
            # so Django/Seahub generate https:// URLs and accept the CSRF token.
            echo "SECURE_PROXY_SSL_HEADER = ('HTTP_X_FORWARDED_PROTO', 'https')"
        fi
        if [ -n "${FILE_SERVER_ROOT}" ]; then
            echo "FILE_SERVER_ROOT = '${FILE_SERVER_ROOT%/}'"
        fi
        if [ "${DJANGO_DEBUG}" = "true" ]; then
            # WARNING: exposes tracebacks to clients. Use only for diagnosis.
            echo "DEBUG = True"
        fi
        if [ "${VERBOSE_LOGS}" = "true" ]; then
            cat <<'PYEOF'
LOGGING = {
    'version': 1,
    'disable_existing_loggers': False,
    'handlers': {
        'console': {'class': 'logging.StreamHandler'},
    },
    'root': {'handlers': ['console'], 'level': 'DEBUG'},
    'loggers': {
        'django': {'handlers': ['console'], 'level': 'DEBUG', 'propagate': False},
        'seahub': {'handlers': ['console'], 'level': 'DEBUG', 'propagate': False},
    },
}
PYEOF
        fi
        if [ -n "${COLLABORA_URL}" ]; then
            echo "ENABLE_OFFICE_WEB_APP = True"
            echo "OFFICE_WEB_APP_BASE_URL = '${COLLABORA_URL%/}/hosting/discovery'"
            echo "WOPI_ACCESS_TOKEN_EXPIRATION = 1800"
            echo "OFFICE_WEB_APP_FILE_EXTENSION = ('odp','ods','odt','doc','docx','xls','xlsx','ppt','pptx','pdf')"
            echo "ENABLE_OFFICE_WEB_APP_EDIT = True"
            echo "OFFICE_WEB_APP_EDIT_FILE_EXTENSION = ('odp','ods','odt','doc','docx','xls','xlsx','ppt','pptx')"
        fi
        echo "# <<< HA add-on managed block <<<"
    } >> "${settings}"
    echo "[Seafile] Applied managed seahub_settings.py block."
}

if ! apply_seahub_settings; then
    echo "[Seafile] seahub_settings.py not present yet — installing post-setup hook."
    mkdir -p /etc/my_init.d
    cat > /etc/my_init.d/99_ha_seahub_settings.sh <<HOOK
#!/bin/bash
# Generated by HA Seafile add-on. Patches seahub_settings.py once setup
# has finished, then restarts seahub so the new settings take effect.
export COLLABORA_URL='${COLLABORA_URL}'
export SERVICE_URL='${SERVICE_URL}'
export FILE_SERVER_ROOT='${FILE_SERVER_ROOT}'

(
    settings=/shared/seafile/conf/seahub_settings.py
    for i in \$(seq 1 120); do
        [ -f "\${settings}" ] && break
        sleep 2
    done
    [ -f "\${settings}" ] || exit 0

    sed -i '/# >>> HA add-on managed block >>>/,/# <<< HA add-on managed block <<</d' "\${settings}"
    {
        echo ""
        echo "# >>> HA add-on managed block >>>"
        [ -n "\${SERVICE_URL}" ] && {
            echo "SERVICE_URL = '\${SERVICE_URL%/}'"
            echo "CSRF_TRUSTED_ORIGINS = ['\${SERVICE_URL%/}']"
            echo "SECURE_PROXY_SSL_HEADER = ('HTTP_X_FORWARDED_PROTO', 'https')"
        }
        [ -n "\${FILE_SERVER_ROOT}" ] && echo "FILE_SERVER_ROOT = '\${FILE_SERVER_ROOT%/}'"
        [ -n "\${COLLABORA_URL}" ] && {
            echo "ENABLE_OFFICE_WEB_APP = True"
            echo "OFFICE_WEB_APP_BASE_URL = '\${COLLABORA_URL%/}/hosting/discovery'"
            echo "WOPI_ACCESS_TOKEN_EXPIRATION = 1800"
            echo "OFFICE_WEB_APP_FILE_EXTENSION = ('odp','ods','odt','doc','docx','xls','xlsx','ppt','pptx','pdf')"
            echo "ENABLE_OFFICE_WEB_APP_EDIT = True"
            echo "OFFICE_WEB_APP_EDIT_FILE_EXTENSION = ('odp','ods','odt','doc','docx','xls','xlsx','ppt','pptx')"
        }
        echo "# <<< HA add-on managed block <<<"
    } >> "\${settings}"

    # Restart seahub so new settings are loaded
    sleep 5
    /opt/seafile/seafile-server-latest/seahub.sh restart 8000 || true
) &
HOOK
    chmod +x /etc/my_init.d/99_ha_seahub_settings.sh
fi

# ── Stream Seafile / Seahub logs to add-on stdout ─────────────────────────
# These files don't exist on a fresh install; `tail --retry -F` waits for
# them to appear and then follows. Each line is prefixed with its filename
# so the HA log shows which component spoke.
(
    sleep 3
    exec tail --retry -n0 -F \
        /shared/logs/seafile.log \
        /shared/logs/seahub.log \
        /shared/logs/controller.log \
        /shared/logs/ccnet.log \
        /shared/logs/seahub_django_request.log \
        /shared/logs/onlyoffice.log \
        /var/log/nginx/error.log \
        2>/dev/null | awk '
            /^==> / { file=$2; sub(/^.*\//,"",file); sub(/ <==$/,"",file); next }
            { print "[" file "] " $0; fflush() }
        '
) &

# ── Hand off to the official Seafile startup chain ────────────────────────
# The seafile-mc image expects to be launched through `my_init`, which is the
# only thing that starts nginx (defined in /etc/service/nginx). Bypassing it
# (running start.py directly) means port 80 stays dead even though Seafile
# itself runs. Always go through my_init + enterpoint.sh.
echo "[Seafile] Launching Seafile (hostname: ${SERVER_HOSTNAME}) ..."
if [ -x /sbin/my_init ]; then
    exec /sbin/my_init -- /scripts/enterpoint.sh
else
    exec /scripts/enterpoint.sh
fi
