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
├── troubleshoot.py           # Diagnostics — all the actual checks (see Troubleshooting)
├── troubleshoot.sh           # Linux / macOS: run diagnostics
├── troubleshoot.bat          # Windows: double-click to run diagnostics
├── Dockerfile                # Container image definition
├── docker-compose.yml        # Docker Compose service definition
└── README.md

# Files created automatically at runtime:
├── .venv/                    # Python virtual environment
├── .genai-monitor.pid        # PID of the running server
├── genai-monitor.log         # Server log
└── pii-config.json           # Admin-defined PII keyword list (see PII Detection)
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
### Get the code

```shell
git clone --no-checkout --depth 1 --filter=blob:none https://github.com/sascommunities/technical-support-code.git .
git sparse-checkout init --no-cone
git sparse-checkout set /usage/administration/sas-gen-ai-monitor-vk
git checkout
```

### Windows

1. Ensure Python is installed and **added to PATH**
2. To start the server, double‑click **gen-ai-monitor-start.bat**
3. To stop the server, double‑click **gen-ai-monitor-stop.bat**

### Linux / macOS

1. Ensure Python is installed
2. Make the script executable:

```bash
chmod +x gen-ai-monitor.sh
```
3. Start the server as a background process:

```bash
# Start on default port
./gen-ai-monitor.sh start
```

#### Additional commands

```bash
./gen-ai-monitor.sh start [--port PORT]    Start in the background (default: 8899)
./gen-ai-monitor.sh stop                   Stop the server
./gen-ai-monitor.sh restart [--port PORT]  Stop then start
./gen-ai-monitor.sh status                 Show state, PID, uptime, and access URLs
./gen-ai-monitor.sh logs [--lines N]       Tail the log file (default: 50 lines)
./gen-ai-monitor.sh help                   Show all options
```
#### Additional content

- *You can delete `.venv/` at any time to force a clean rebuild on the next start.*
- *By default, the script binds to `0.0.0.0` so the dashboard is reachable from the network. Use a firewall rule if you want to restrict access to specific IPs.*

### Docker

1. Ensure Docker and Docker Compose are installed
2. From the project folder, build and start the container:

```bash
docker compose up -d --build
```
3. Access the dashboard at `http://localhost:8899`
4. View logs:

```bash
docker compose logs -f
```
5. Stop the container:

```bash
docker compose down
```

> Inside the container, `gen-ai-monitor.sh start` runs automatically and binds to `0.0.0.0` on port 8899 (mapped to the host via `docker-compose.yml`). `.venv/`, `genai-monitor.log`, and `.genai-monitor.pid` are created inside the container's filesystem — since no volume is configured, they are lost when the container is removed. Mount a volume (e.g. `./data:/app`) if you need the log or cache to survive a `docker compose down`.
>
> After changing any source file, rebuild the image with `docker compose up -d --build` — the `Dockerfile` copies the code in at build time, so changes are not picked up automatically.

### Command-line reference

`liveGenAiMonitoring.py` can also be run directly (used internally by all the methods above):

```bash
python3 liveGenAiMonitoring.py [options]
```

| Option | Description |
|---|---|
| `--host HOST` | Bind address. Default: `127.0.0.1` (local only). Use `0.0.0.0` for network access. |
| `--port PORT` | Port to listen on. Default: `8899` |
| `--no-browser` | Do not open the browser automatically |
| `--server` | Server mode: bind to `0.0.0.0` and skip opening the browser (same as `--host 0.0.0.0 --no-browser`) |
| `--launch` | Spawn as a silent background process and exit (used by the Windows `.bat` scripts) |

# Users Guide

## Profiles

When you open the dashboard at first you will see the profile picker. To add an environment click **+ New Profile**:

| Field | What to enter |
|---|---|
| **Profile Name** | A friendly label, e.g. `Production`, `Lab`, `Dev` |
| **Icon** | Click the avatar to choose an emoji and accent colour (Optional) |
| **Viya Ingress URL** | External HTTPS URL, e.g. `https://viya4-lab.example.com` — this is the only thing a profile pins you to; sign-in itself is never tied to one environment |

Then click **Sign in with Viya →**. This opens SAS Logon's own hosted sign-in page in a new tab — authenticate there however your environment requires (plain username/password, SSO, MFA, whatever is configured; the dashboard itself never sees your password). SAS Logon shows a short code on success: copy it, come back to this tab, paste it into **Code from SAS Logon**, and click **Finish Sign-in →**. Your username is read directly from the resulting token, so there's nothing to type for it.

> Each profile represents one cluster. You can have as many as you need — including multiple profiles for the same cluster under different accounts.

## Managing Profiles

> Nothing from sign-in is ever stored — not a password (never collected in the first place), not the access or refresh token. Re-doing the sign-in (new tab → paste code) is always required when you reconnect, even to a profile you've used before.

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

Imported chat cache is restored to the server as soon as you sign in to the matching account — not before, since the server only ever writes a cache file for whichever account you currently hold a valid token for (see [Security Notes](#security-notes)). If the export contains cache for several different accounts, sign in to each one at least once to restore all of it.

# Dashboard

## Access Levels

The dashboard has two access levels, determined **server-side** from your own Viya bearer token — never from anything the browser reports. You get the administrator view if you are:

- **`sasboot`**, or
- a **member of `SASAdministrators` who assumed the group when signing in.** `SASAdministrators` is an assumable group: SAS Logon asks whether to opt in, and only if you choose yes does Viya include the group in your session's token. Answer no and you get the regular-user view for that session — the same as in Viya itself. The dashboard then shows a reminder that you're a member who didn't opt in; to switch, sign in again and opt in (sign out of SAS Logon first if it doesn't ask).

Everyone else gets the regular-user view:

| | Regular user | SAS Administrator |
|---|---|---|
| **Chat visibility** | Only your own chats, across Active / All / History | Every user's chats across the whole environment |
| **Graphs tab** | Not visible | Full cross-user analytics |
| **PII panel / word list** | Not visible | Full read/write access |
| **Function-call / tool-call payloads** | Never sent to the browser (arrives redacted) | Full raw payload, with PII flags |

A regular user's dashboard behaves like a personal activity log; only administrators get the full "monitor everyone" view.

## View Modes

| Mode | What it shows |
|---|---|
| **● Active** | Chats modified within the active window (default: last 10 minutes). In Active mode, you can adjust the window size to widen or narrow the time range. |
| **◎ All** | Every chat from the API |
| **📋 History** | Manual fetch only — polling is paused. Filter chats by date using the period dropdown (Last 3 / 7 / 15 / 30 days, All time, or **Custom…** for a precise from/to date range). Results re-filter instantly from cache with no additional network requests. |
| **📊 Graphs** | Analytics view — see the [Graphs](#graphs) section below. |

## Filters

All filters combine with each other. Use the **✕ Clear** button to reset all at once.

| Filter | Description |
|---|---|
| **Chat ID** | Type or paste any part of a chat UUID — partial matches are supported and results update instantly. Click any chat UUID in a card header to copy it to the clipboard. |
| **User** | Filter to one user's chats (populated automatically from live data). Non-admin viewers have nothing to filter here — every chat you can see is already your own. |
| **App** | Filter by application, e.g. `SAS Visual Analytics`, `SAS Landing`. In History mode the app list always shows every app seen across all time, regardless of the active date range. |
| **Search** | Full-text search across all message content — highlights matches, auto-expands cards, shows match count with next/previous navigation |

## Chat Cards

Cards are collapsed by default and can be expanded individually from the header or globally using Expand All / Collapse All.

The header shows the **application name** as the primary title, the **creator** (`by username`) on the secondary line, followed by creation and modification timestamps. The right side displays the status badge (● ACTIVE / ○ idle), message count chip, and action buttons (📌 pin, ▶ replay, ⬇ export, ⇔ compare, 📝 note).

**Click the grey chat UUID** at the top of any card to copy it to the clipboard.

**Click the username** (`by username`) on any card to open the [User Deep-Dive Panel](#user-deep-dive-panel) for that user.

Messages are ordered chronologically (oldest first) and display role, timestamp, message ID, full Markdown content, status flags, and a ⭐ bookmark option.

### Copilot Backend Badge

Each card shows a purple badge (`<agent> v<version>`, e.g. `gatewayOrchestrator v1`) naming the internal Copilot backend component that handled that chat — **not** the application name, which is the card's title. Most apps route everything through one component; a few use several, so two chats from the same app can show different badges.

> **SAS Model Studio quirk:** opening a new conversation there creates two separate chat records — the real conversation (`gatewayOrchestrator`) and a short internal retrieval call with no real content (`ragServer`, usually just a few seconds). The dashboard hides the `ragServer` one automatically, but **only for Model Studio** — other apps that use `ragServer` as their actual backend (e.g. SAS Environment Manager) are shown normally. Model Studio's application name is also reported inconsistently by Viya ("Model Studio" vs "SAS Model Studio") — the dashboard treats both as the same app automatically.

### Compact Mode

Click **▣ Compact** in the toolbar to toggle compact card density. In compact mode:
- Card padding is reduced, fitting more cards on screen without scrolling
- The chat UUID row is hidden (still accessible from the filter bar)

The preference is saved automatically and persists across sessions.

## PII Detection (SAS Administrators Only)

Function-call/tool-call payloads — the `copilotFunctionResponse` / `functionResult` messages carrying the raw arguments and results behind every Copilot tool call — are hidden from regular users entirely. The server never sends this raw payload to a non-admin browser (it arrives pre-redacted as `{redacted: true}`), regardless of any PII settings.

For **SAS Administrators**, a **🔒 PII's** button appears in the top-right header (same server-side admin check as the [Graphs](#graphs) tab, re-verified against Viya on every request using the identity embedded in your own bearer token — neither a forged client-side admin flag nor an edited username can unlock this).

### Defining PII keywords

Click **🔒 PII's** to open the panel and enter a comma-separated list of words or names to flag as sensitive, e.g.:

```
cpf, email, 'full name', 'social security number'
```

- Multi-word terms must be wrapped in single quotes
- 500-character limit
- Click **Save** — the list is stored server-side (`pii-config.json`) and shared by every admin connected to that server; nothing is built-in or auto-guessed, admins fully control what counts as sensitive

### How flags appear

Once saved, every function-call/result message (already-cached chats included) is re-scanned for the configured words:
- Chats containing at least one match show a **⚠ PII** badge on the chat card header, with a tooltip listing which words matched
- The individual function-call/result message — visible to admins in the expandable audit block — shows its own **⚠ PII: word1, word2** tag
- `search_capability_registry` calls are always excluded from scanning — they only return generic tool/skill documentation, never real user or query data, so flagging them would just be noise

### Security notes

- The word list can only be read or changed by users the server itself confirms are SAS Administrators (checked against the Viya Identities API on every request) — the client's `isAdmin` flag is never trusted, and neither is any username the client reports; your identity is decoded directly from your own bearer token
- Non-admin viewers never receive the raw function-call/result payload at all, so PII flags are meaningless — and invisible — to them regardless of what words are configured

## Pinned Chats

Pin any chat to keep it permanently at the top of the list, regardless of sort order or polling updates.

- Click **📌** in the card header to pin or unpin
- Pinned chats are separated from the rest by a `📌 Pinned above · other chats below` divider
- Pins persist across sessions (stored in `localStorage`, scoped per cluster and user)
- Pinned chats remain at the top even when switching between **↓ New** and **↑ Old** sort order
- Pinned chats are always visible in History mode regardless of the active date range, and expand in place without switching modes

## Chat Comparison

Compare two conversations side by side.

1. Click **⇔** on the first card — the button turns blue and a toast confirms the selection
2. Click **⇔** on any second card — the comparison modal opens immediately

The modal renders both full conversations in scrollable columns, with application name, creator, timestamps, and prompt/response counts in each header. Click the username in either column header to open the User Deep-Dive Panel for that user.

Close with **×**, by clicking the backdrop, or pressing **Escape**.

## User Deep-Dive Panel

Click any username — on a chat card, in global search results, or in the comparison modal — to open a per-user activity summary.

| Section | Content |
|---|---|
| **Stats** | Total chats, prompts sent, number of distinct apps used, average chat duration, first seen date, last active date |
| **Apps Used** | All applications used, sorted by chat count, with a proportional bar showing relative usage |
| **Activity — Last 30 Days** | Daily bar chart for the past 30 days. Hover any bar to see the exact date and count. |
| **Recent Chats** | Last 8 chats, most recent first. Click the chat name / ID to copy the full chat ID to the clipboard — it briefly turns green and shows **✓ Copied!** as confirmation. |

Close with **×** or **Escape**.

## Toolbar Controls

| Control | Description |
|---|---|
| **▶ Fetch** | Manually trigger a fetch (also resets the poll countdown) |
| **⏸ Pause / ▶ Resume** | Pause or resume automatic polling |
| **↓ Newest / ↑ Oldest** | Sort chat cards by modified timestamp. Pinned chats always remain at the top regardless of sort order. |
| **Expand All / Collapse All** | Expand or collapse all visible chat cards |
| **▣ Compact** | Toggle compact card density (see [Compact Mode](#compact-mode)) |

> **Background tab behaviour** — polling is automatically paused when you switch to another browser tab and resumes immediately when you return, triggering an instant fetch. The status bar shows `tab hidden` while paused. This saves CPU and network on machines where the dashboard runs all day in a background tab.

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
| Total | Total non-embedding chats visible to you from the server (only shown when filters reduce the count) — scoped to your own chats if you're not an admin, see [Access Levels](#access-levels) |

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

## Graphs

The **📊 Graphs** tab provides a visual analytics overview of all GenAI activity on the cluster. It is accessible to **SAS Administrators only** — non-admin users will not see the tab.

When you enter Graphs mode, the dashboard fetches the complete chat history from the server (all apps, all users, no date filter) and loads all message content into the local cache before rendering.

> Embedding and expression chats are automatically excluded from all graphs — they are background system calls, not real user conversations. Chat and prompt counts in Graphs always match the counts shown in All and History modes.

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

The legend on the right lists each application with its prompt count and percentage share (`42 | 35%`), vertically aligned for easy scanning.

### Word Cloud — Top 30 Terms

Displays the 30 most frequent words found across all user prompt text, after removing common stop-words (the, and, is, etc.).

- **Size** reflects frequency — larger words appear more often
- **Color** indicates the application where the word appears most
- **Hover** over any word to see which application it is associated with
- A color legend at the bottom maps each color to its application

A **Filter by app** dropdown in the chart header lets you narrow the word cloud to a single application's prompts — all words, sizes, colors, and the legend will reflect only that application. Select **All applications** to restore the full cross-app view.

### User Journey

Click any username in the **User** dropdown to open a weekly activity timeline for that user. The timeline shows each chat as a coloured block positioned by time-of-day across a 7-day grid. Navigate between weeks using the **← Prev** / **Next →** buttons.

### User Filter

The **User** dropdown in the sticky nav bar filters all three charts and all six stat chips simultaneously to show data for a single user. Select **all users** to restore the full view. The dropdown is populated automatically from the loaded chat data.

### Refresh

Click **↺ Refresh** to re-fetch the full chat history from the server and re-render all charts with fresh data.

## Settings

Click **⚙** in the top-right header while connected to open the Settings panel. You can update the **poll interval** without disconnecting. Click **Apply** to save.

Click **Disconnect** to return to the profile picker. To change the Viya URL or sign in as a different user, disconnect and reconnect using the profile picker.

## Theme

Click **☀️ / 🌙** in the top-right to toggle between light and dark themes. The preference is saved automatically and persists across sessions.


# Troubleshooting

## Running diagnostics

Before digging further, run the diagnostics script — it checks the things that explain most issues reported for this app: the Python runtime itself (including `ssl`, which every call to Viya depends on), whether the project files are present and valid, folder write permissions, whether a running server matches what's on disk right now (catches "I edited the file but forgot to restart"), whether your copy matches GitHub's main branch, and — if you're using Docker — whether the container is actually reachable under the Docker context/engine you're currently pointed at.

```bash
# Linux / macOS
./troubleshoot.sh

# Windows — double-click, or from a terminal:
troubleshoot.bat
```

Point it at a different deployment with `--url http://host:port` (useful for a Docker or remote install), or skip a section with `--no-server` / `--no-docker` / `--no-github-check`. It exits non-zero if anything fails, so it's safe to script.

### Support log

Every run also writes a support log, `troubleshoot_<timestamp>.log`, in the project folder (or in the system temp folder if the project folder isn't writable) and prints its path at the end. Attach that file when asking for help. It contains:

- the full console output of the checks above
- environment details: OS, Python and OpenSSL versions, host name, proxy / `GENAI_MONITOR_*` environment variables
- the running server's `/health` response (build versions, start time)
- a listing of the project folder (file names, sizes, dates; folder contents are only counted, never listed)
- the last 200 lines of `genai-monitor.log`, plus `docker logs` for a `gen-ai-monitor` container if one is found

Bearer tokens, JWTs, passwords, authorization codes and proxy credentials are redacted before anything is written. The log still contains host names, Viya URLs, user names and chat IDs, so review it before sharing if that matters. Options: `--log PATH` to choose the file, `--log-lines N` to change how much server log is included, `--no-log` to skip it.

It never contacts Viya and needs no credentials for any of this. It's separate from `tests/` (an internal regression suite for people editing this project's code, not shipped to end users).

### Checking (and updating) against GitHub

The script compares `liveGenAiMonitoring.py` and `viya4_dashboard.html` against the copies on this project's [GitHub repo](https://github.com/sascommunities/technical-support-code/tree/main/usage/administration/sas-gen-ai-monitor-vk) (main branch). A mismatch is only ever reported as "differs" — it cannot tell which side is newer. It's just as likely to mean you have local changes not pushed there yet as it is to mean an update is available, so treat it as a prompt to go look, not a verdict.

If it differs, it asks before doing anything else:

```
2 file(s) differ from GitHub's main branch: liveGenAiMonitoring.py, viya4_dashboard.html
Download and apply the GitHub version of the file(s) above? Your current files are
backed up first. Type 'yes' to confirm, anything else to skip:
```

Nothing is downloaded or overwritten unless you type exactly `yes` — anything else (including just pressing Enter) leaves your files untouched. It always backs up whatever it's about to replace first, to a `backup_<timestamp>/` folder in the project directory, so an update can be undone by copying those files back. Only these two files are ever touched this way; nothing else in the project is downloaded or modified.

Running from a script instead of a terminal? The prompt never fires non-interactively (no stdin to read "yes" from) — pass `--yes` if you specifically want it to apply an update unattended, or `--no-github-check` to skip the comparison entirely (e.g. on an air-gapped network).

## Code changes aren't taking effect

The server only reads `liveGenAiMonitoring.py` once, at startup, and a browser tab only has whatever `viya4_dashboard.html` it was loaded with — editing either file on disk doesn't retroactively change a process or tab that's already running.

- **Already-open tab:** if the file on the server has changed since this tab loaded, a toast appears automatically within a few minutes: *"This tab is running an older version of the dashboard — reload the page to pick up the latest."* You don't have to go looking for this — it's self-reported.
- **Running server process:** `./troubleshoot.sh` (or `.bat`) reports this directly — "server_restart_needed" / "restart it to apply the update" — instead of you having to guess from symptoms.

## Server does not start

Check `genai-monitor.log` in the same folder. The start script also prints the last 20 log lines directly in the console window if the server exits immediately.

## Authentication error (401 / 403)

- Confirm the Viya4 Ingress URL starts with `https://` and has no trailing slash
- If sign-in itself fails: the code from SAS Logon is single-use and short-lived — click **Sign in with Viya** again for a fresh one rather than retrying an old code
- Verify the account has access to the GenAI Gateway service in Viya4

### Capturing sign-in traffic for support (HAR)

Clicking **Sign in with Viya** opens SAS Logon's own page in a **new browser tab** — that's expected, and it's the reason a HAR capture taken on the dashboard's own tab shows nothing for it: a new tab/origin is a separate recording context in every browser's devtools. The dashboard's tab never even makes a network request for that click; it's a plain tab-open.

If you need the authentication handshake itself captured for support:
- Open devtools (and start the Network recording) on the **new SAS Logon tab**, not the dashboard tab — ideally before clicking the button, since the tab opens already navigating.
- The one part of sign-in that *is* visible in the dashboard tab's own HAR is the final step — a `POST` to `/api/token` on this app's own server (the code-for-token exchange). That same exchange is also logged server-side in `genai-monitor.log` (grant type, the Viya URL, success/failure — never the code or token itself) precisely because it's the one step a browser-side HAR can't be relied on to show consistently.

## No chats appear after connecting

- Switch to **◎ All** mode — the Active window filter may be hiding older chats
- Confirm the GenAI Gateway service is running in the cluster

## Chat counts do not match expectations

- The dashboard permanently hides embedding chats and does not include them in any counts. This is by design — they are background system calls, not real user conversations.
- Non-admin users only ever see (and count) their own chats — see [Access Levels](#access-levels). If you're comparing counts with a colleague or an administrator, a mismatch is expected, not a bug.

## A new chat doesn't show up right away

Most apps briefly report a new chat's `modifiedBy` as `anonymous` while the first response is still generating, then switch it to the real username once done — the dashboard hides it for up to 2 minutes while that's the case, to avoid flashing an unattributed chat. **SAS Model Studio** is a known exception: Viya never resolves this field for it at all, so the dashboard skips the wait entirely and shows Model Studio chats as soon as they exist.

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

Run `gen-ai-monitor-stop.bat`, or free it manually:
```bat
netstat -ano | findstr :8899
taskkill /PID <pid> /F
```

## Docker issues

- **Port already allocated** — another process or container is already using 8899 on the host. Stop it, or change the host-side port mapping in `docker-compose.yml` (e.g. `"9000:8899"`).
- **Code changes not showing up** — rebuild the image after editing source files: `docker compose up -d --build`. `./troubleshoot.sh --url http://localhost:8899` confirms whether the running container still predates your edit.
- **Container exits immediately** — check the logs with `docker compose logs -f` for the same errors described in [Server does not start](#server-does-not-start).
- **`docker ps` shows nothing, but the dashboard is reachable** — if more than one Docker engine is installed (e.g. Docker Desktop alongside Rancher Desktop), the container may be running under a different engine/context than the one your `docker` CLI currently points at. `./troubleshoot.sh` calls this out explicitly; otherwise check `docker context ls` and try `docker --context <name> ps`.

## Security Notes

| Item | Behaviour |
|---|---|
| Sign-in | OAuth2 authorization code + PKCE — your password is typed into SAS Logon's own page, never into this dashboard. See [Profiles](#profiles) |
| Bearer / refresh tokens | Session memory only — never persisted; a new sign-in is required every time you reconnect |
| Profile data | Stored in `localStorage` — just the Viya URL, display name, and last-known username, never any token |
| Chat cache | Stored server-side (`cache/` folder), one file per cluster+user, included in exports — treat the export file as internal data. Which file a request can read, write, or clear is decided only by a token Viya itself has accepted, and the cluster part comes from that same Viya URL — one user can never read, poison, or wipe another's cache |
| Chat visibility | Non-admins see only their own chats; SAS Administrators see every user's chats across the environment — enforced server-side on every request, see [Access Levels](#access-levels). Paths are normalized before the check, and non-admins can only reach the two endpoints the dashboard uses, so URL tricks (encoding, `//`, `../`, trailing `/`) can't sidestep it |
| Identity / admin status | Confirmed by Viya itself (`/identities/users/@currentUser`) before it's trusted. Admin = `sasboot`, or a `SASAdministrators` member whose token carries the assumed group (opted in at sign-in) — see [Access Levels](#access-levels). A hand-made token claiming to be `sasboot` or carrying the admin scope is rejected. Never trusted from anything the browser reports |
| Chat content rendering | Message text is rendered as Markdown with raw HTML shown as plain text, and links limited to safe schemes — one user's prompt (or a Copilot reply it steers) can't run script in another user's or an admin's dashboard |
| Function-call / tool payloads | Redacted server-side (`{redacted: true}`) for non-admins — the raw data never leaves the server for them. Admins see the real payload, optionally flagged against the admin-defined PII word list (`pii-config.json`) — see [PII Detection](#pii-detection-sas-administrators-only) |
| Viya URLs | Only `http`/`https`, never link-local addresses (cloud metadata endpoints). For shared deployments, set `GENAI_MONITOR_ALLOWED_HOSTS` (comma-separated, `*.` wildcards allowed, e.g. `viya.example.com,*.corp.example.com`) to restrict which Viya environments can be used at all. Unset = any environment, as before |
| Browser hardening | Same-origin only: no CORS grants, JSON-only POSTs (blocks other websites from firing requests at the server), `X-Frame-Options: DENY`, `nosniff`, `no-referrer`, and `Cache-Control: no-store` on API responses (token responses are never cached) |
| SSL | Certificate verification disabled to support self-signed Viya4 certificates |
| Network binding | Default `127.0.0.1` (local only). Use `--server` only on trusted internal networks — browser-to-dashboard traffic is plain HTTP, so put a TLS reverse proxy in front of any shared deployment |

## License

SPDX-License-Identifier: Apache-2.0

Copyright © 2026, SAS Institute Inc., Cary, NC, USA. All Rights Reserved.

## Contributors

- **Helisson Mota** — Core development
  helisson.mota@sas.com

- **Vitor Lima** — Core development
  vitor.lima@sas.com
