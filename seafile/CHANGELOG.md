# Changelog

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
