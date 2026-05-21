# Seafile Add-on Documentation

## Overview

Seafile is a self-hosted file sync and sharing platform. This add-on bundles Seafile server (v11), Seahub (the web UI) and an embedded MariaDB database so no external database is needed.

## First-time Setup

1. Configure the options below.
2. Set `server_hostname` to the address your devices will use to reach Home Assistant — for example `192.168.1.10:8080` or `nas.example.com:8080`.
3. Start the add-on. First boot takes 1–2 minutes while the database is initialised.
4. Open the web UI at `http://<your-ha-ip>:8080` and log in with your admin credentials.

## Configuration Options

| Option | Description | Default |
|---|---|---|
| `admin_email` | E-mail address for the initial admin account | `admin@example.com` |
| `admin_password` | Password for the initial admin account | `seafile_admin` |
| `server_name` | Display name shown in the Seafile UI | `MySeafile` |
| `server_hostname` | Hostname (and port) that clients use to reach the server | `homeassistant.local:8080` |
| `time_zone` | Server time zone | `Europe/Berlin` |
| `service_url` | Public URL Seafile is reachable at (e.g. `https://seafile.example.com`). Used for share links and required for Collabora. Leave empty if not using a reverse proxy. | `""` |
| `file_server_root` | Public URL of the Seafile fileserver, e.g. `https://seafile.example.com/seafhttp`. Only set this if your reverse proxy publishes `/seafhttp` — wrong values break uploads ("Netzwerkfehler"). | `""` |
| `collabora_url` | HTTPS base URL of your Collabora Online (CODE) server, e.g. `https://collabora.example.com`. Leave empty to disable office integration. | `""` |
| `verbose_logs` | Enable verbose DEBUG-level Django/Seahub logging streamed to the add-on log. | `false` |
| `django_debug` | Turn on Django `DEBUG=True`. Shows full tracebacks in browser on errors. **Do not leave on in production** — it leaks settings/paths. | `false` |

**Important:** Change `admin_password` before exposing the add-on to the internet.

## Data Persistence

| Path | Content |
|---|---|
| `/config/seafile/mariadb/` | MariaDB database files |
| `/config/seafile/shared/` | Complete Seafile state (conf, ccnet, seafile-data, seahub-data, nginx config) |

The entire Seafile installation lives under `/config/seafile/`, so a complete backup of that folder (plus `mariadb/`) is sufficient to restore the server.

## Ports

| Port | Description |
|---|---|
| `8080/tcp` | Seafile web interface (Seahub) |

## Clients

Download the official Seafile clients from [https://www.seafile.com/download/](https://www.seafile.com/download/).  
Configure them with server URL `http://<server_hostname>`.

## Collabora Online Integration

Set `collabora_url` (and ideally `service_url`) in the add-on options and restart. The add-on patches `seahub_settings.py` automatically.

You also need to allow Seafile as a WOPI host inside Collabora itself. In your Collabora HA add-on options, add to the WOPI host allowlist (regex format, escape dots):

```
homeassistant\.local
seafile\.example\.com
```

Both servers must reach each other over **HTTPS**.

After saving the options, restart the Seafile add-on. Office files (`.docx`, `.xlsx`, `.odt`, …) will then open in Collabora directly from Seahub.

## Troubleshooting

- **Logs:** Check the add-on log tab. Detailed logs are in `/config/seafile/logs/`.
- **First start fails:** Ensure the configured `server_hostname` is reachable.
- **Port conflict:** Change the host port from `8080` to any free port in the add-on network settings.
