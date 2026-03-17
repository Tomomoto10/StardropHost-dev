# Development Guide

---

## Repository Layout

```
StardropHost/
├── docker/
│   ├── Dockerfile                  # Main game server image
│   ├── config/
│   │   ├── startup_preferences     # Template for Stardew launch prefs
│   │   └── 10-monitor.conf         # Xorg modesetting config
│   ├── mods/                       # Pre-built SMAPI mods (copied into image)
│   │   ├── AlwaysOnServer/
│   │   ├── AutoHideHost/
│   │   ├── ServerAutoLoad/
│   │   └── SkillLevelGuard/
│   ├── mods-source/
│   │   ├── AutoHideHost_v1.0.1/    # C# source for AutoHideHost
│   │   └── ServerDashboard/        # C# source — built at image build time
│   ├── scripts/
│   │   ├── entrypoint.sh           # Container startup (main logic)
│   │   ├── init-container.sh       # One-shot: permissions + directory setup
│   │   ├── crash-monitor.sh        # Rate-limited auto-restart
│   │   ├── status-reporter.sh      # Prometheus metrics + JSON status
│   │   ├── save-selector.sh        # SAVE_NAME → startup_preferences
│   │   ├── auto-backup.sh          # Timed save backups + rotation
│   │   ├── log-manager.sh          # Log rotation
│   │   ├── log-monitor.sh          # Live log tailing
│   │   ├── event-handler.sh        # Game event dispatch with cooldowns
│   │   ├── vnc-monitor.sh          # VNC lifecycle management
│   │   └── set-resolution.sh       # Xvfb resolution control
│   ├── manager/
│   │   └── server.js               # Manager sidecar (port 3001)
│   ├── steam-auth/
│   │   └── server.js               # Steam auth sidecar (port 3000)
│   └── web-panel/
│       ├── server.js               # Express entry point (port 18642)
│       ├── auth.js                 # JWT + bcrypt auth
│       └── api/
│           ├── wizard.js           # 5-step first-run wizard
│           ├── status.js           # Live server status
│           ├── logs.js             # Log streaming
│           ├── mods.js             # Mod management
│           ├── saves.js            # Save management
│           ├── farm.js             # Farm/player info
│           ├── players.js          # Player list
│           ├── config.js           # Runtime config
│           ├── vnc.js              # VNC control
│           ├── terminal.js         # WebSocket terminal
│           └── steam.js            # Steam status relay
├── tests/
│   ├── test-new-features.sh        # Offline script logic tests
│   ├── test-steam-guard.sh         # steam-auth API tests (needs container)
│   ├── cleanup-tests.sh            # Remove test containers + tmp dirs
│   └── README.md
├── Docs/
├── docker-compose.yml
├── verify-deployment.sh
└── backup.sh
```

---

## Container Architecture

```
┌──────────────────────────────────────────────┐
│  stardrop-init  (one-shot, exits 0)           │
│  init-container.sh: mkdir, chown data volumes │
└─────────────────────┬────────────────────────┘
                      │ completes successfully
                      ▼
┌──────────────────────────────────────────────┐
│  stardrop-server  (main game container)       │
│  entrypoint.sh → Xvfb → SMAPI → game         │
│  web-panel on :18642                          │
│  Prometheus on :9090 (optional)               │
│  VNC on :5900 (optional)                      │
└──────────────┬───────────────────────────────┘
               │ REST calls
               ▼
┌──────────────────────────────────────────────┐
│  stardrop-manager  (sidecar)                  │
│  Accepts start/stop/restart from web panel    │
│  :3001                                        │
└──────────────────────────────────────────────┘

┌──────────────────────────────────────────────┐
│  stardrop-steam-auth  (optional sidecar)      │
│  Isolated Steam login + guard code relay      │
│  :3000                                        │
└──────────────────────────────────────────────┘
```

---

## Startup Sequence

```
entrypoint.sh
  Phase 1 (root):  GPU Xorg config → switch to steam user
  Phase 2 (steam): Detect game files
  Phase 3:         Install SMAPI (skip if already installed)
  Phase 4:         Deploy mods (preinstalled + custom)
  Phase 5:         Write startup_preferences (SAVE_NAME, resolution)
  Phase 6:         Start Xvfb
  Phase 7:         Start x11vnc (if ENABLE_VNC=true)
  Phase 8:         Start background services
                     crash-monitor.sh  (if ENABLE_CRASH_RESTART=true)
                     auto-backup.sh    (if ENABLE_AUTO_BACKUP=true)
                     log-monitor.sh    (if ENABLE_LOG_MONITOR=true)
                     status-reporter.sh (always)
  Phase 9:         Launch StardewModdingAPI --server
```

---

## Key Design Decisions

### ServerDashboard mod (built at image build time)

The web panel reads live status from `/home/steam/web-panel/data/live-status.json`, written by the `ServerDashboard` C# mod. The mod is built from source during `docker build` using `dotnet-sdk-6.0`, so the DLL is always in sync with the target game/SMAPI version. The build step in `Dockerfile` copies `ServerDashboard.dll` and `manifest.json` separately — there is no `ServerDashboard/` subdirectory under `net6.0/`.

### Player ID regex

SMAPI logs player IDs as large negative integers (e.g. `-123456789012345`). All player-count parsing uses `[-0-9]+`, not `[0-9]+`.

### CPU percentage

`ps` reports per-core CPU. `status-reporter.sh` divides by `$(nproc)` to get a host-normalised percentage.

### Atomic status writes

`ServerDashboard` and `status-reporter.sh` write files via a `.tmp` + `mv` pattern to prevent the web panel reading a partial file mid-write.

### `/api/vnc/connected` — no auth

This endpoint is called by `vnc-monitor.sh` running inside the container and does not go through the JWT middleware. This is intentional.

### steam-auth isolation

Steam credentials are only ever present in the `stardrop-steam-auth` container. The game container never sees them. The steam-auth sidecar writes a refresh token to a shared volume so subsequent startups don't require re-authentication.

---

## Local Development

### Build the image

```bash
docker build -t stardrop-server:dev -f docker/Dockerfile docker/
```

### Start with a local game copy

```bash
# Put Stardew Valley files in ./data/game/
docker compose up
```

### Run script tests (no Docker needed)

```bash
bash tests/test-new-features.sh
```

### Watch web panel logs

```bash
docker logs -f stardrop
```

### Exec into the running container

```bash
docker exec -it stardrop bash
```

### Check SMAPI log

```bash
docker exec stardrop cat /home/steam/.config/StardewValley/ErrorLogs/SMAPI-latest.txt
```

---

## Common Troubleshooting

### Game doesn't start

```bash
docker logs stardrop | grep -i "error\|failed\|not found"
```

Check: game files present at `/home/steam/stardewvalley`, SMAPI installed, mods copied.

### Mods not loading

```bash
docker exec stardrop ls /home/steam/stardewvalley/Mods/
docker exec stardrop cat /home/steam/stardewvalley/Mods/AlwaysOnServer/manifest.json
```

### Web panel unreachable

```bash
docker exec stardrop pgrep -f "node.*server.js"
curl -s http://localhost:18642/api/auth/status
```

### Permission errors on data volumes

```bash
sudo chown -R 1000:1000 ./data/
```

---

## Release Checklist

- [ ] Update `version` label in `docker/Dockerfile`
- [ ] Update `Docs/CHANGELOG.md`
- [ ] Run `bash tests/test-new-features.sh`
- [ ] `docker build` succeeds cleanly
- [ ] Setup wizard completes end-to-end
- [ ] Game launches and players can connect
- [ ] `./verify-deployment.sh` passes

---

## Performance Notes

Typical resource usage:

| Resource | Idle | 4 players |
|---|---|---|
| RAM | ~1.5 GB | ~2.2 GB |
| CPU | 1–5% | 15–40% |
| Disk | ~2.5 GB image | +save files |
| Upload | — | ~50–100 Kbps/player |

See `Docs/CPU-OPTIMIZATION.md` for `LOW_PERF_MODE` details.

---

**Last Updated:** 2026-03-17
**Version:** v1.0.0
