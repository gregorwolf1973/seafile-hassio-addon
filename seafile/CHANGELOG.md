# Changelog

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
