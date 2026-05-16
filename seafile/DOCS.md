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

## Troubleshooting

- **Logs:** Check the add-on log tab. Detailed logs are in `/config/seafile/logs/`.
- **First start fails:** Ensure the configured `server_hostname` is reachable.
- **Port conflict:** Change the host port from `8080` to any free port in the add-on network settings.
