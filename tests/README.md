# Tests

## test-new-features.sh

Comprehensive offline test suite for StardropHost scripts. Runs without Docker or the game — tests logic, syntax, and behavior using temporary directories.

**Usage:**
```bash
bash tests/test-new-features.sh
```

**What it tests:**
1. Syntax validation (`bash -n`) on all scripts in `docker/scripts/`
2. `crash-monitor.sh` — `can_restart()` rate-limiting logic
3. `init-container.sh` — directory creation logic
4. `save-selector.sh` — `SAVE_NAME` env var selection logic
5. `status-reporter.sh` — metric collection, Prometheus format, JSON status
6. `entrypoint.sh` — VNC password truncation, resolution defaults
7. `event-handler.sh` — cooldown logic
8. `auto-backup.sh` — backup rotation logic

## test-steam-guard.sh

Tests the `stardrop-steam-auth` sidecar REST API. Requires the container to be running.

**Usage:**
```bash
# Start the sidecar first:
docker compose up stardrop-steam-auth

# Then run the tests (defaults to http://localhost:3000):
bash tests/test-steam-guard.sh

# Or specify a custom URL:
bash tests/test-steam-guard.sh http://localhost:3000
```

**What it tests:**
- `GET /health` returns 200
- `GET /status` returns structured JSON
- `POST /guard-code` with an invalid code returns structured JSON
- `POST /guard-code` with empty body returns 400
- Unknown routes return 404

## cleanup-tests.sh

Removes test containers and temporary data.

```bash
bash tests/cleanup-tests.sh
```
