# StardropHost — Included Mods

## Mod List

### 1. Always On Server
- **Author**: funny-snek & Zuberii
- **Version**: 1.20.3-unofficial.5-mikkoperkele
- **Description**: Enables headless 24/7 server operation
- **Unique ID**: mikko.Always_On_Server
- **License**: GPL-3.0
- **Nexus**: https://www.nexusmods.com/stardewvalley/mods/2677

### 2. AutoHideHost
- **Author**: truman-world
- **Version**: 1.2.2
- **Description**: Hides the host player and provides seamless day-night transitions with instant sleep
- **Unique ID**: AIdev.AutoHideHost
- **License**: MIT

### 3. ServerAutoLoad
- **Author**: StardropHost
- **Version**: 1.2.1
- **Description**: Automatically loads the most recent save on startup, eliminating the need for VNC after first setup
- **Unique ID**: stardrop.ServerAutoLoad
- **License**: MIT
- **Features**:
  - Auto-detects and loads most recent save
  - Supports specific save selection via `SAVE_NAME` env var
  - Save monitoring and logging

### 4. SkillLevelGuard
- **Author**: StardropHost
- **Version**: 1.4.0
- **Description**: Prevents Always On Server from forcing host to Level 10, restores real XP-based skill levels
- **Unique ID**: stardrop.SkillLevelGuard
- **License**: MIT
- **Features**:
  - Blocks Always On Server forced skill upgrades
  - Restores accurate levels based on actual XP
  - Prevents unwanted LevelUpMenu popups
  - Enables Always On Server auto mode on save load

### 5. ServerDashboard ⭐ NEW
- **Author**: StardropHost
- **Version**: 1.0.0
- **Description**: Writes live game state to `live-status.json` every 10 seconds for the web panel
- **Unique ID**: stardrop.ServerDashboard
- **License**: MIT
- **Features**:
  - Real-time player data (health, energy, position, money)
  - In-game time, date, weather and festival status
  - Cabin information
  - Console command `dashboard_status` for immediate write
  - Configurable update interval

---

## Requirements
- **SMAPI**: 4.0.0 or higher
- **Stardew Valley**: 1.6.0 or higher
- All mods are server-side only — farmhand clients do NOT need them

---

## Configuration

All mods are pre-installed and pre-configured. Settings can be adjusted via the web panel or by editing config files in `./data/game/Mods/<ModName>/config.json`.

### Save Selection
Leave `SAVE_NAME` blank in `.env` to auto-load the most recent save, or set it to a specific save folder name.

### Update Interval (ServerDashboard)
Edit `ServerDashboard/config.json`:
```json
{
  "UpdateIntervalSeconds": 10
}
```