#!/usr/bin/env bash
# Starts the embedded MariaDB instance and waits until it is ready.
# Usage: start-mariadb.sh <datadir> <root-password>
set -e

DATADIR="${1}"
ROOT_PASS="${2}"
SOCKET=/var/run/mysqld/mysqld.sock

# Initialize data directory on first run
if [ ! -d "${DATADIR}/mysql" ]; then
    echo "[MariaDB] Initialising data directory in ${DATADIR} ..."
    mysql_install_db --user=mysql --datadir="${DATADIR}" --skip-test-db \
        > /tmp/mysql_init.log 2>&1
fi

# Start the daemon in the background.
# Memory tuning: Seafile only needs a small DB. The defaults reserve ~400MB
# for InnoDB; the values below cap MariaDB at ~80MB resident on a fresh
# install, leaving more headroom for Seahub/Seafile/nginx on small HA hosts.
echo "[MariaDB] Starting daemon ..."
mysqld \
    --user=mysql \
    --datadir="${DATADIR}" \
    --socket="${SOCKET}" \
    --bind-address=127.0.0.1 \
    --port=3306 \
    --skip-networking=OFF \
    --innodb-buffer-pool-size=128M \
    --innodb-log-file-size=16M \
    --innodb-log-buffer-size=4M \
    --key-buffer-size=8M \
    --max-connections=50 \
    --table-open-cache=64 \
    --performance-schema=OFF \
    --skip-log-bin \
    > /var/log/mariadb.log 2>&1 &

# Wait until the socket is ready (up to 60 s)
for i in $(seq 1 60); do
    if mysqladmin --socket="${SOCKET}" ping --silent 2>/dev/null; then
        echo "[MariaDB] Ready."
        break
    fi
    sleep 1
done

if ! mysqladmin --socket="${SOCKET}" ping --silent 2>/dev/null; then
    echo "[MariaDB] ERROR: daemon did not start in time." >&2
    cat /tmp/mysql_init.log >&2 || true
    cat /var/log/mariadb.log >&2 || true
    exit 1
fi

# Set / update the root password so Seafile can authenticate with ROOT_PASS.
# On first start root has no password; on subsequent starts it already does,
# so try the stored password first and fall back to no-password.
SQL_SETUP=$(cat <<SQL
ALTER USER IF EXISTS 'root'@'localhost' IDENTIFIED BY '${ROOT_PASS}';
CREATE USER IF NOT EXISTS 'root'@'127.0.0.1' IDENTIFIED BY '${ROOT_PASS}';
ALTER USER 'root'@'127.0.0.1' IDENTIFIED BY '${ROOT_PASS}';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'127.0.0.1' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL
)

if mysql --socket="${SOCKET}" -u root -p"${ROOT_PASS}" -e "SELECT 1" >/dev/null 2>&1; then
    mysql --socket="${SOCKET}" -u root -p"${ROOT_PASS}" -e "${SQL_SETUP}"
elif mysql --socket="${SOCKET}" -u root -e "SELECT 1" >/dev/null 2>&1; then
    mysql --socket="${SOCKET}" -u root -e "${SQL_SETUP}"
else
    echo "[MariaDB] ERROR: cannot authenticate as root with stored password" >&2
    echo "[MariaDB] If you reset /config/seafile/.db_root_pass, also remove" >&2
    echo "[MariaDB] /config/seafile/mariadb to reinitialise the database." >&2
    exit 1
fi

echo "[MariaDB] Root credentials configured."
