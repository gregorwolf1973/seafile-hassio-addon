# Changelog

## 0.2.10 — 2026-05-21

- **Fix Seahub slowness (5–6 s per request).** The default `CACHES`
  config written by `setup-seafile-mysql.py` points at a memcached
  hostname that doesn't resolve in this container, and the image's
  memcached binary isn't in `PATH`. Every request was firing 30+
  `pylibmc.HostLookupError` lookups before timing out. We now
  override `CACHES` in the managed block to use Django's
  `filebased.FileBasedCache` at `/tmp/seafile-cache` — no daemon
  needed, works across gunicorn workers.
- Pre-create `/tmp/seafile-cache` world-writable so the seafile
  user can populate it.
- Search common paths for the `memcached` binary (`/usr/bin`,
  `/usr/local/bin`, `/usr/sbin`) before giving up.

## 0.2.9 — 2026-05-21

- Log streamer follows symlinks now (`find -L`) — seafile-mc often
  symlinks `/opt/seafile/logs` to `/shared/logs` and the previous
  find missed it. Adds one-shot startup diagnostics dumping `ls` of
  candidate log directories so we can see where they live.
- Bumped InnoDB buffer pool back to 128M — 48M was hurting query
  performance for browsing libraries.
- Memcached startup now logs the actual failure reason instead of
  swallowing stderr.

## 0.2.8 — 2026-05-21

- Log streaming reborn as a runit service under `/etc/service/log-stream`.
  The previous background subshell was being orphaned/killed by my_init
  so no output reached the add-on log. The runit service is properly
  supervised and writes to PID 1's stdout via `/proc/1/fd/1`, so the
  output is guaranteed to appear in HA's add-on log view.

## 0.2.7 — 2026-05-21

- Log-streaming rewrite: `find` all `*.log` files under `/shared`,
  `/opt/seafile`, `/var/log`, retry on rotation, re-scan periodically
  so new log files written later are picked up too.

## 0.2.6 — 2026-05-21

- Simplify log streaming: wait for the logs dir to populate, then
  follow every `*.log` file found in `/shared/logs`,
  `/opt/seafile/logs`, and `/var/log/nginx`. The previous awk filter
  was eating output. Each file's lines now appear under a
  `==> /shared/logs/seahub.log <==` header.

## 0.2.5 — 2026-05-21

- Fix `ServerDown: 1 keys failed` 500 on login. Memcached (which
  seahub uses for the login rate-limit counter) was not coming up
  via the image's runit service. We now start it explicitly from
  run.sh before handing off to my_init.

## 0.2.4 — 2026-05-21

- Stream Seafile/Seahub/nginx logs to the add-on log so you no longer
  need to dig through `/config/seafile/shared/logs/`. Each line is
  prefixed with `[seahub.log]`, `[seafile.log]`, etc.
- New `verbose_logs` option enables DEBUG-level Django/Seahub logging.
- New `django_debug` option turns on `DEBUG = True` for diagnosing
  500 errors (**off by default** — leaks information).

## 0.2.3 — 2026-05-16

- Drastically lower MariaDB memory footprint
  (innodb-buffer-pool-size 48M, performance-schema off, no binlog,
  smaller caches). Saves roughly 300 MB on idle systems — important
  for HA installations that already run many add-ons.

## 0.2.2 — 2026-05-16

- Auto-write `CSRF_TRUSTED_ORIGINS` and `SECURE_PROXY_SSL_HEADER`
  to `seahub_settings.py` when `service_url` is set, fixing
  "CSRF-Verifizierung fehlgeschlagen (403)" behind HTTPS proxies.

## 0.2.1 — 2026-05-16

- **Fix uploads breaking after enabling `service_url`.** v0.2.0
  silently set `FILE_SERVER_ROOT = '<service_url>/seafhttp'`, which
  redirected uploads to a URL the browser usually couldn't reach
  ("Netzwerkfehler"). `FILE_SERVER_ROOT` is now its own option and
  defaults to empty, letting Seafile auto-detect from the request.

## 0.2.0 — 2026-05-16

- New options `collabora_url` and `service_url` enable Collabora
  Online (CODE) office integration. The add-on patches
  `seahub_settings.py` on every start with a managed block, so
  updating the options in HA is enough — no manual file edits.
- On first boot (before setup has created `seahub_settings.py`) the
  patch is deferred via a `my_init.d` hook, then seahub is restarted.

## 0.1.5 — 2026-05-16

- Launch Seafile via `my_init` + `enterpoint.sh` instead of calling
  `start.py` directly. `my_init` is what starts nginx (from
  `/etc/service/nginx`); bypassing it left port 80 dead even though
  Seafile itself was running.

## 0.1.4 — 2026-05-16

- **Breaking layout change:** all Seafile state is now persisted under
  `/config/seafile/shared/` (entire `/shared` is a symlink to it).
- Stop pre-creating `seafile-data`, which made Seafile skip setup and
  crash on missing `admin.txt` / `/opt/seafile/conf` symlink.
- Auto-detect and wipe an incomplete previous setup so the next start
  re-runs `setup-seafile-mysql.py` cleanly.
- Removed the `/share/seafile-data` symlink for now (was hiding setup
  bugs); will return as an opt-in option later.

## 0.1.3 — 2026-05-16

- Pre-create `seahub-data/avatars` and `seahub-data/custom` so the
  Seafile upgrade script's `mv` succeeds.
- Create nginx runtime dirs (`/var/run/nginx`, `/var/lib/nginx`,
  `/var/log/nginx`) the upstream image is missing.

## 0.1.2 — 2026-05-16

- Fix restart failure: authenticate as root with the stored password
  on subsequent starts instead of trying password-less login.

## 0.1.1 — 2026-05-16

- Fix first-start crash: pre-create `/shared/nginx/conf` and other
  directories the Seafile bootstrap expects but does not create itself.
- Move user data symlink from `/shared/seafile-data` to the correct
  `/shared/seafile/seafile-data` location.

## 0.1.0 — 2026-05-16

- Initial release
- Seafile server v11 (seafileltd/seafile-mc)
- Embedded MariaDB (no external database required)
- Persistent data in `/config/seafile/` and `/share/seafile-data/`
- Configurable admin account, server name, hostname, and time zone
