# Changelog

All notable changes to StardropHost are documented here.

---

## v1.0.0 (2026-04-12)

Initial public release of StardropHost — a full rebuild of `puppy-stardew-server` (v1.0.77) around a web-panel-first workflow.

---

### Architecture

- **5-container design**: `stardrop-server` (game + web panel), `stardrop-manager` (sidecar control), `stardrop-init` (one-shot permission init), `stardrop-steam-auth` (optional Steam login sidecar), `stardrop-gog-downloader` (ephemeral GOG download sidecar)
- Custom Docker bridge network (172.30.0.0/24) — containers communicate internally, no host network exposure for sidecars
- Init container runs once as root to fix volume permissions (UID 1000:1000) before the game container starts
- Resource limiting: CPU and memory caps configurable per container via `.env`
- Multi-instance support: run multiple StardropHost servers on the same host on different ports

---

### Web Panel

A full browser-based control panel served from inside the game container on port 18642.

**First-Run Setup Wizard**
- 5-step guided setup: admin password → game files → resource limits → server settings → confirm
- Game files can be provided as a local copy, Steam download (via `stardrop-steam-auth`), or GOG download (via `stardrop-gog-downloader`)
- Headless new farm creation — no VNC or xdotool required (`FarmAutoCreate` mod)

**Dashboard**
- Live server status: running/stopped, uptime, player count, game version, SMAPI version
- CPU and RAM usage in real time
- Backed by `StardropDashboard` SMAPI mod writing `live-status.json` every 10 seconds

**Farm Tab**
- Live in-game data: current season, day, time, weather
- Player positions, health, and energy
- Community Center completion progress
- Crop and animal overview from save file parsing

**Players Tab**
- Live player list with names, positions, health, and farm stats
- Kick and ban players
- Security: dual-mode blocklist/allowlist (block specific players, or restrict to an allowlist)
- Player history and name-to-IP mapping

**Saves Tab**
- Browse all save files with farm name and playtime
- Select the active save loaded on next server start
- Upload save archives (ZIP) from local machine
- Create and download manual backups
- Full backup history with timestamps

**Mods Tab**
- List all installed SMAPI mods with version and author
- Upload custom mods as ZIP or folder
- Delete custom mods
- Distinguishes bundled mods from user-uploaded mods

**Logs Tab**
- Live SMAPI log streaming via WebSocket
- Filtered views: All / Errors / Mods / Server / Game events
- Download current log file directly from the panel

**Console Tab**
- Full in-browser terminal via WebSocket PTY
- Send SMAPI console commands directly
- Download log files for bug reports
- 5-minute idle timeout for security

**Config Tab**
- VNC toggle, password, and display resolution (800×600 to 2560×1440)
- CPU and RAM limit adjustment without rebuilding
- Crash restart toggle and threshold
- Auto-backup frequency
- Server name, password, and public IP
- Delete Farm & Restart Setup — wipes all saves and returns to wizard

**Host Controls**
- Start, stop, restart the game server
- Trigger an update (pulls latest from GitHub and rebuilds)
- System health check

---

### API

All endpoints require JWT authentication except wizard endpoints (pre-setup) and the instance registration endpoint.

- `POST /api/auth/login` / `POST /api/auth/change-password`
- `GET /api/status` — server state, uptime, CPU/RAM, player count
- `POST /api/server/start|stop|restart|update`
- `GET/POST /api/logs` — log streaming and filtered views
- `GET /api/players` / `POST /api/players/kick|ban`
- `GET /api/saves` / `POST /api/saves/backup|upload` / `PUT /api/saves/select`
- `GET /api/mods` / `POST /api/mods/upload` / `DELETE /api/mods/:id`
- `GET|PUT /api/config` — read/write runtime environment
- `GET /api/vnc/status` / `POST /api/vnc/enable|disable`
- `GET /api/farm/live` — live in-game data from `StardropDashboard`
- `GET /api/farm/overview` — save file metadata (Community Center, crops, animals)
- `GET /api/chat` / `POST /api/chat/send` — in-game chat log and send messages
- `GET /api/game-update/status` / `POST /api/game-update/trigger` — Steam update checks
- `GET /api/instances` / `POST /api/instances/register` — multi-instance peer registry
- WebSocket `/ws` — real-time log streaming and live status

---

### Custom Mods (built from source at container startup)

Mods are compiled inside the running container after game files are mounted — never baked into the image — so they always compile against the installed game version.

**StardropHost.Dependencies**
Replaces the 4 separate mods from `puppy-stardew-server` (AlwaysOnServer, AutoHideHost, ServerAutoLoad, SkillLevelGuard) with a single consolidated mod:
- Headless server mode — keeps the server running with no players online
- Auto-sleep at 2:00 AM each in-game day
- Automatic save loading on startup (via `SAVE_NAME` env var)
- Host player hiding — teleports the host character off-screen, stacks into a cabin
- Event skipping — passout, ready checks, offline mode events handled silently
- Building move permissions management
- Chat logging to JSON file (read by web panel Chat tab)
- Security config reader — enforces blocklist/allowlist from web panel settings
- Minimum skill level enforcement for joining players

**StardropDashboard**
- Writes `live-status.json` every 10 seconds with live player data, season, day, time, weather
- Tracks Community Center completion progress
- Feeds the Farm tab in the web panel

**FarmAutoCreate**
- Reads `new-farm.json` from the web panel when the title screen appears
- Creates a new multiplayer farm programmatically via Stardew's C# API
- No VNC or mouse automation required

---

### Container Scripts

- **entrypoint.sh** — main startup: Xvfb virtual display, SMAPI install, mod build and deploy, game launch
- **init-container.sh** — one-shot permission and directory setup (runs as root before the game container)
- **crash-monitor.sh** — wraps the game process; rate-limited auto-restart on crash (max 5 restarts per 5-minute window)
- **auto-backup.sh** — scheduled save backups with ZIP compression; maintains a rolling 7-day history
- **log-monitor.sh** — real-time SMAPI log categorisation into `errors.log`, `mods.log`, `server.log`, `game.log`
- **event-handler.sh** — monitors SMAPI logs for game events and dispatches responses with cooldown logic
- **game-update-check.sh** — polls Steam for available game updates; writes availability status for the web panel
- **status-reporter.sh** — Prometheus metrics on port 9090 and JSON status file
- **save-selector.sh** — writes `saveFolderName` to `startup_preferences` from the `SAVE_NAME` env var
- **vnc-monitor.sh** / **set-resolution.sh** — VNC lifecycle management and Xvfb resolution control
- **log-manager.sh** — log rotation

---

### Sidecars

**stardrop-manager**
- Docker Compose lifecycle control (start/stop/restart containers) without giving the game container Docker socket access
- Manages `docker-compose.override.yml` for remote tunnel configuration (e.g. playit.gg)
- Handles update flow: spawns an Alpine container to `git pull` and rebuild

**stardrop-steam-auth**
- Isolated Node.js service for Steam login — handles 2FA/Guard codes
- Credentials are memory-only, never written to any volume
- Container has `restart: no` — exits after the wizard download completes, wiping all in-memory state

**stardrop-gog-downloader**
- Isolated GOG Galaxy OAuth login and game download
- OAuth tokens are ephemeral (container filesystem only, never mounted to host)
- Container has `restart: no` — tokens are gone when the container exits
- Users re-authenticate each time they download or update

---

### Host Scripts

- **quick-start.sh** — one-command install; auto-detects distro (Ubuntu/Debian/CentOS/RHEL/Fedora/Arch); installs Docker if not present; sets up firewall rules; enables Docker at boot; supports multiple instances on the same host
- **update.sh** — pulls latest code from GitHub, incremental Docker rebuild, SMAPI version check, multi-instance sibling detection
- **scripts/backup.sh** — manual save backup with ZIP compression and 7-backup rotation
- **scripts/rebuild-fresh.sh** — full clean rebuild discarding all cached layers (10–20 min)
- **scripts/health-check.sh** — host-level container health check (Docker, container status, SMAPI, mods, ports, resources, disk)
- **scripts/verify-deployment.sh** — post-deploy smoke test across 10 checks
- **scripts/uninstall.sh** — removes containers, images, firewall rules, game files, and optionally Docker itself

---

### Configuration

| Variable | Default | Description |
|---|---|---|
| `CONTAINER_PREFIX` | `stardrop` | Prefix for all container names (multi-instance) |
| `PANEL_PORT` | `18642` | Web panel port |
| `GAME_PORT` | `24642` | Stardew Valley game server port (UDP) |
| `ENABLE_VNC` | `false` | Start x11vnc on port 5900 |
| `VNC_PASSWORD` | `stardew1` | VNC password (truncated to 8 chars) |
| `ENABLE_AUTO_BACKUP` | `false` | Enable timed save backups |
| `ENABLE_CRASH_RESTART` | `false` | Auto-restart game on crash |
| `MAX_CRASH_RESTARTS` | `5` | Max restarts per 5-minute window |
| `ENABLE_LOG_MONITOR` | `false` | Enable log categorisation |
| `LOW_PERF_MODE` | `false` | Xvfb + GC tuning for low-resource hosts |
| `USE_GPU` | `false` | Enable hardware GPU via modesetting driver |
| `SAVE_NAME` | _(none)_ | Auto-select this save folder on startup |
| `SERVER_PASSWORD` | _(none)_ | In-game server password |
| `PUBLIC_IP` | _(none)_ | Shown in web panel for connection info |
| `METRICS_PORT` | `9090` | Prometheus metrics port |

---

### Ports

| Port | Protocol | Purpose |
|---|---|---|
| 24642 | UDP | Stardew Valley game server |
| 18642 | TCP | Web panel |
| 5900 | TCP | VNC (optional) |
| 9090 | TCP | Prometheus metrics (optional) |
| 3001 | TCP | Manager sidecar (internal only) |
| 3000 | TCP | Steam auth sidecar (internal only) |
