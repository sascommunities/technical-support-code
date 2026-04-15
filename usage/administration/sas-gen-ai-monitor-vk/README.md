# Viya GenAIMonitor

A lightweight, browser-based dashboard for monitoring **SAS Viya Copilot** chats—live and historical data. Runs entirely on your machine, with no cloud services and no installation beyond Python.

*Your browser never talks directly to Viya4. The local Python proxy handles authentication, SSL, and pagination.*

## File Structure

```shell
# Once the repository is cloned, you should see the following structure:
genaiproject/
├── liveGenAiMonitoring.py    # Python proxy server
├── viya4_dashboard.html      # Single-page dashboard
├── gen-ai-monitor-start.bat  # Windows: double-click to start
├── gen-ai-monitor-stop.bat   # Windows: double-click to stop
├── gen-ai-monitor.sh         # Linux / macOS: start / stop / status / logs
└── README.md

# Files created automatically at runtime:
├── .venv/                    # Python virtual environment
├── .genai-monitor.pid        # PID of the running server
└── genai-monitor.log         # Server log
```

## Quick Start

On first run this automatically:
- Create an isolated `.venv/` virtual environment automatically (no root needed)
- Start the proxy in the background on port **8899**
- Opens your browser at `http://localhost:8899` on Windows, or print the access URLs for both local and network access on Linux.

### Prerequisites (all platforms)

- Python 3.8 or later (3.10+ recommended)
- Git
- A modern browser (Chrome, Edge, Firefox, Safari)

#### Verify Python is available:

```shell
python --version
# or
python3 --version
```
#### Get the code

```shell
git clone <repository-url>
cd viya-genai-monitor
```

### Windows

1. Ensure Python is installed and **added to PATH**
2. To start the server, double‑click **gen-ai-monitor-start.bat**
3. To stop the server, double‑click **gen-ai-monitor-stop.bat**

### Linux / macOS

1. Ensure Python is installed
2. Make the script executable:

```bash
chmod +x genai-monitor.sh
```
3. Start the server as a background process:

```bash
# Start on default port
./genai-monitor.sh start
```

#### Additional commands

```bash
./genai-monitor.sh start [--port PORT]    Start in the background (default: 8899)
./genai-monitor.sh stop                   Stop the server
./genai-monitor.sh restart [--port PORT]  Stop then start
./genai-monitor.sh status                 Show state, PID, uptime, and access URLs
./genai-monitor.sh logs [--lines N]       Tail the log file (default: 50 lines)
./genai-monitor.sh help                   Show all options
```
#### Additional content

- *You can delete `.venv/` at any time to force a clean rebuild on the next start.*
- *By default, the script binds to `0.0.0.0` so the dashboard is reachable from the network. Use a firewall rule if you want to restrict access to specific IPs.*

# Users Guide

## Profiles

When you open the dashboard at first you will see the profile picker. To add an environment click **+ New Profile**:

| Field | What to enter |
|---|---|
| **Profile Name** | A friendly label, e.g. `Production`, `Lab`, `Dev` |
| **Icon** | Click the avatar to choose an emoji and accent colour (Optional) |
| **Viya4 Ingress URL** | External HTTPS URL, e.g. `https://viya4-lab.example.com` |
| **Username** | Your SAS Viya username |
| **Password** | Your Viya password — held in memory only, never stored |
| **Poll interval** | Seconds between refreshes (minimum 3, default 5) |

Than, click **Connect ->**. The proxy authenticates via OAuth2 and the dashboard begins polling.

> Each profile represents one cluster + user combination. You can have as many as you need — including multiple profiles for the same cluster;

## Managing Profiles

> Passwords are never stored anywhere — you always re-enter the password when connecting.

### Exporting

Click **⬇ Export All** in the sidebar footer (or hover a profile card and click **⬇** for a single profile). The `.json` file includes:
- All profile settings
- All saved prompt favorites (every user, every cluster)
- The full chat message cache — so the first fetch on a new browser is as fast as if you had been using it for days

### Importing

Click **⬆ Import** in the sidebar footer or drag the `.json` file onto the login screen.

Import is always a **safe merge** — existing profiles and favorites are never overwritten. The confirmation toast shows what was imported:

```
⬆ Imported: 2 new profile(s), 47 favorite(s), 312 chats cached
```

# Dashboard

## View Modes

| Mode | What it shows |
|---|---|
| **● Active** | Chats modified within the active window (default: last 10 minutes). In Active mode, you can adjust the window size to widen or narrow the time range. |
| **◎ All** | Every chat from the API |
| **📋 History** | Manual fetch only—polling is paused. In History mode, use the period dropdown to filter chats by date (Last 3 / 7 / 15 / 30 days, or All time), with instant re-filtering from cache and no additional network requests. |
| **📊 Graphs** | Analytics view — see the [Graphs](#graphs) section below. |

## Filters

All filters combine with each other. Use the **✕ Clear** button to reset all at once.

| Filter | Description |
|---|---|
| **Chat ID** | Paste a specific chat UUID to show only that conversation |
| **User** | Filter to one user's chats (populated automatically from live data) |
| **App** | Filter by application, e.g. `SAS Visual Analytics`, `SAS Landing` |
| **Search** | Full-text search across all message content — highlights matches, auto-expands cards, shows match count with next/previous navigation |

## Chat Cards

Cards are collapsed by default and can be expanded individually from the header or globally using Expand All / Collapse All.

The header shows application, user, timestamps, status badge, message count, and an ⬇ export button. Messages are ordered chronologically (oldest first) and display role, timestamp, message ID, full Markdown content, status flags, and a ⭐ bookmark option.

## Toolbar Controls

| Control | Description |
|---|---|
| **▶ Fetch** | Manually trigger a fetch (also resets the poll countdown) |
| **⏸ Pause / ▶ Resume** | Pause or resume automatic polling |
| **↓ Newest / ↑ Oldest** | Sort chat cards by modified timestamp |
| **Expand All / Collapse All** | Expand or collapse all visible chat cards |

## Status Bar

```
● Authenticated as sasboot @ viya4-lab.example.com   Cycle: 12   Checked: 10:42 AM   Changed: 10:41 AM   Next: 4s    [39 chats] [44 total]
```

| Item | Meaning |
|---|---|
| Cycle | How many fetch cycles have run this session |
| Checked | When the last fetch completed |
| Changed | When data last actually changed |
| Next | Countdown to next fetch (`...` while fetching, `paused` in History mode) |
| Chats | Chats currently shown after all filters |
| Total | Total non-embedding chats from the server (only shown when filters reduce the count) |

## Saved Prompts (Favorites)

Save useful prompts and messages for future reuse.

### Saving

Click **⭐** next to any message. You will be asked for optional tags (comma-separated, e.g. `ldap, fix, authentication`). Press Enter or leave blank and confirm.

### Viewing

Click **⭐** in the top-right header to open the Saved Prompts panel. From there you can:

- **Search** across content and tags
- **Filter by tag** using the tag chips
- **Copy** content to clipboard (⎘)
- **Edit tags** (🏷)
- **Jump to the original message** — click the card or the ↗ button to scroll directly to the message in the chat view, highlighted in amber
- **Delete** a saved prompt (🗑)
- **Export all saved chats as HTML** using the **⬇ Export** button in the panel header

## Exporting Chats as HTML

Export any conversation as a standalone, formatted HTML file — useful for sharing with SAS Technical Support.

**Export a single chat:** Click **⬇** in the chat card header.

**Export all chats that contain saved prompts:** Click **⬇ Export** in the Saved Prompts panel header.

Filename format:
```
viya4-sas-visual-analytics-a1b2c3d4-2026-03-25.html
```
The exported file:
- Is fully **self-contained** — works offline with no external dependencies
- Renders full **Markdown** (code blocks, tables, lists, links)
- Respects your **current light/dark theme**
- Marks bookmarked messages with ⭐
- Includes chat metadata: application, user, copilot version, timestamps

> The chat must be loaded in memory (fetched in All or History mode). If not yet cached, a toast will prompt you to fetch first.

## Settings

Click **⚙** in the top-right header while connected to open the Settings panel. You can update the **poll interval** without disconnecting. Click **Apply** to save.

Click **Disconnect** to return to the profile picker. To change the Viya URL, username, or password, disconnect and reconnect using the profile picker.

## Theme

Click **☀️ / 🌙** in the top-right to toggle between light and dark themes. The preference is saved automatically and persists across sessions.

## Graphs

The **📊 Graphs** tab provides a visual analytics overview of all GenAI activity on the cluster. It is accessible to **SAS Administrators only** — non-admin users will not see the tab.

When you enter Graphs mode, the dashboard fetches the complete chat history from the server (all apps, all users, no date filter) and loads all message content into the local cache before rendering.

> Embedding and expression chats are automatically excluded from all graphs — they are background system calls, not real user conversations.

### Stat Panel

Six summary bars are displayed at the top of the Graphs panel:

| Panel | Description |
|---|---|
| **Total Chats** | Number of chats that passed all current filters |
| **Total Prompts** | Total user messages (userRequest + userPromptRequest types) |
| **Est. Tokens ≈** | Estimated token usage — counts every word (space-separated) in both user prompts and copilot responses as one token. Hover for the full tooltip. |
| **Applications** | Number of distinct SAS applications used |
| **Busiest Month** | The calendar month with the highest prompt count |
| **Top App** | The application with the most prompts. Long names are abbreviated using initial capitals, e.g. `SAS Visual Analytics` → `SAS VA`. Hover to see the full name. |

All charts will update instantly when you change the **User** filter.

### Prompts / Chats by Period

A bar chart showing activity over time. Two dropdowns in the chart header let you control what is displayed:

**Period** (left dropdown):

| Option | What it shows |
|---|---|
| **Monthly** | Last 12 calendar months |
| **Weekly** | Last 8 weeks, each bucket starting on Monday |
| **Daily** | Last 7 days |

**Type** (right dropdown):

| Option | What it shows |
|---|---|
| **Prompts** | Count of user messages per period |
| **Chats** | Count of new chats created per period (by `creationTimeStamp`) |


### Usage by Application (Donut Chart)

Shows the share of total prompts per SAS application. Up to 8 applications are shown individually; any remaining ones are grouped as **Other**. Hover over a slice to see the exact count and percentage.

### Word Cloud — Top 30 Terms

Displays the 30 most frequent words found across all user prompt text, after removing common stop-words (the, and, is, etc.).

- **Size** reflects frequency — larger words appear more often
- **Color** indicates the application where the word appears most
- **Hover** over any word to see which application it is associated with
- A color legend at the bottom maps each color to its application

A **Filter by app** dropdown in the chart header lets you narrow the word cloud to a single application's prompts. Select **All applications** to restore the full cross-app view.

### User Filter

The **User** dropdown in the sticky nav bar filters all three charts and all six stat chips simultaneously to show data for a single user. Select **all users** to restore the full view. The dropdown is populated automatically from the loaded chat data.

### Refresh

Click **↺ Refresh** to re-fetch the full chat history from the server and re-render all charts with fresh data.

# Troubleshooting

## Server does not start

Check `genai-monitor.log` in the same folder. The start script also prints the last 20 log lines directly in the console window if the server exits immediately.

## Authentication error (401 / 403)

- Confirm the Viya4 Ingress URL starts with `https://` and has no trailing slash
- Check the username and password are correct
- Verify the account has access to the GenAI Gateway service in Viya4

## No chats appear after connecting

- Switch to **◎ All** mode — the Active window filter may be hiding older chats
- Confirm the GenAI Gateway service is running in the cluster

## Chat counts do not match expectations

The dashboard permanently hides embedding chats and does not include them in any counts. This is by design — they are background system calls, not real user conversations.

## venv creation fails on Windows

The start script tries three methods in order:
1. `python -m venv .venv`
2. `python -m venv .venv --without-pip` (Microsoft Store Python workaround)
3. `pip install virtualenv && virtualenv .venv`

To create manually:
```bat
python -m venv .venv
.venv\Scripts\python.exe -m pip install --upgrade pip
```

## Port 8899 already in use

Run `stop-genai-monitor.bat`, or free it manually:
```bat
netstat -ano | findstr :8899
taskkill /PID <pid> /F
```
# 

## Security Notes

| Item | Behaviour |
|---|---|
| Passwords | Session memory only — never written to disk, `localStorage`, or logs |
| Bearer tokens | Session memory only — never persisted |
| Profile data | Stored in `localStorage` — does not include passwords or tokens |
| Chat cache | Stored in `localStorage` and included in exports — treat the export file as internal data |
| SSL | Certificate verification disabled to support self-signed Viya4 certificates |
| Network binding | Default `127.0.0.1` (local only). Use `--server` only on trusted internal networks |

## License

SPDX-License-Identifier: Apache-2.0

Copyright © 2026, SAS Institute Inc., Cary, NC, USA. All Rights Reserved.

## Contributors

- **Helisson Mota** — Core development
  helisson.mota@sas.com

- **Vitor Lima** — Core development
  vitor.lima@sas.com
