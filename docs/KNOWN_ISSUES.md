# Known Issues

StardropHost has been thoroughly tested prior to release. No major bugs or issues are currently known.

Bug testing is ongoing — issues will be documented here as they are found, and fixes will be pushed as updates.

---

## Reporting a Bug

If you encounter an issue, please open a report at:
**https://github.com/tomomotto/StardropHost/issues**

Include the following with your report:

**Log files** — The easiest way to get logs is from the web panel **Console** tab, which lets you download them directly. Attach the file to your issue rather than pasting inline.

If you need to retrieve logs manually over SSH:

| Log | Host path | SSH command |
|-----|-----------|-------------|
| SMAPI (game) | `data/saves/ErrorLogs/SMAPI-latest.txt` | `cat data/saves/ErrorLogs/SMAPI-latest.txt` |
| Setup / entrypoint | `data/logs/setup.log` | `cat data/logs/setup.log` |
| Container output | _(Docker)_ | `docker logs stardrop` |

To save a log to a file for attaching:
```bash
docker logs stardrop > stardrop.log
cat data/saves/ErrorLogs/SMAPI-latest.txt > smapi.log
```

**Environment details:**
- Host OS and Docker version
- How StardropHost was installed (quick-start, manual)
- Steps to reproduce the issue
- What you expected to happen vs. what actually happened

---

**Last Updated:** 2026-04-12
**Version:** v1.0.0
