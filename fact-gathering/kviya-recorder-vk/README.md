# kviya-recorder

`kviya-recorder` is a Bash script that continuously captures a snapshot of a SAS Viya Kubernetes deployment — nodes, pods, events, and resource usage — and saves everything into a compressed playback archive (`.tgz`) that can later be replayed with [kviya](https://gitlab.sas.com/sbralg/tools-and-scripts/-/blob/main/kviya).

Optionally, the script can also collect live logs from selected pods during the capture session.

---

## Requirements

- `kubectl` or `oc` must be installed and available in `$PATH`.
- A valid kubeconfig must be in place: either the `KUBECONFIG` environment variable is set, or `~/.kube/config` exists.
- The user running the script must have sufficient Kubernetes RBAC permissions to `get`/`describe` nodes and pods, `get` events, and run `kubectl top`.
- `curl` is required for the automatic update check at startup.

---

## Installation

Download the script and make it executable:

```bash
curl -O https://raw.githubusercontent.com/sascommunities/technical-support-code/main/fact-gathering/kviya-recorder-vk/kviya-recorder
chmod +x kviya-recorder
```

The script checks for a newer version each time it runs and offers to update itself automatically.

---

## Usage

```
kviya-recorder [OPTIONS]...
```

### Options

| Option | Argument | Description |
|--------|----------|-------------|
| `-n`   | `<namespace>` | Kubernetes namespace of the Viya deployment. Defaults to the namespace set in the current kubeconfig context. |
| `-s`   | _(none)_ | Take a single snapshot and exit instead of running continuously. |
| `-l`   | `<label-selectors>` | Capture pod logs. Accepts a comma-separated list of label selectors (see [Log Monitoring](#log-monitoring) below). |
| `-i`   | `<interval>` | How often snapshots are taken while running continuously. Accepts `sleep`-compatible values such as `2`, `30s`, `1m`, `1h`. Defaults to `0s` (as fast as possible). |
| `-t`   | `<seconds>` | Stop capturing after this many seconds. Defaults to running indefinitely until interrupted with Ctrl+C. |
| `-o`   | `<path>` | Path for the output playback file. Can be a directory (the file will be named `kviya-playback.tgz` inside it) or a full file path. Defaults to `./kviya-playback.tgz`. |
| `-v`   | _(none)_ | Print the script version and exit. |
| `-h`   | _(none)_ | Print usage help and exit. |

---

## Examples

**Capture continuously from the `viya` namespace:**
```bash
kviya-recorder -n viya
```

**Take a single snapshot from the namespace set in the current context:**
```bash
kviya-recorder -s
```

**Capture for one hour at one-minute intervals:**
```bash
kviya-recorder -n viya -t 3600 -i 1m
```

**Capture for 30 minutes and save the playback file to a specific path:**
```bash
kviya-recorder -n viya -t 1800 -o /tmp/captures/my-capture.tgz
```

**Capture continuously and also collect logs from pods with the label `app=sas-logon-app`:**
```bash
kviya-recorder -n viya -l sas-logon-app
```

**Collect logs from multiple label selectors at once:**
```bash
kviya-recorder -n viya -l sas-launcher,sas-logon-app,app.kubernetes.io/name=sas-cas-server
```

---

## Output

When the capture ends (either via Ctrl+C or because `-t` was reached), the script saves a `.tgz` archive containing all collected data.

### Snapshot data (collected every interval)

Each snapshot is a subdirectory named by timestamp (`YYYYDmmDdd_HHTMMTss`) containing:

| File | Command |
|------|---------|
| `getnodes.out` | `kubectl get node` |
| `nodes-describe.out` | `kubectl describe node` |
| `getpod.out` | `kubectl get pod -o wide` |
| `podevents.out` | `kubectl get events` |
| `nodesTop.out` | `kubectl top node` |
| `podsTop.out` | `kubectl top pod` |

Each snapshot directory is compressed into its own `.tgz` as it is collected, keeping disk usage low during long captures.

### Log data (when `-l` is used)

Pod logs are saved under a `logs/` directory inside the archive. Each log file is named:

```
<pod-name>_<container-name>_<instance>.log
```

The `<instance>` counter increments each time log collection restarts for that pod (due to log rotation or pod recreation), so no data is overwritten. Completed log files are compressed to `.tgz` automatically.

A `describe/` directory contains the output of `kubectl describe pod` for each monitored pod, captured at the start of each pod instance.

An internal log file, `logs/kviya-recorder_logmon.log`, records timestamped events from the log monitoring subsystem (see [Troubleshooting](#troubleshooting)).

---

## Log Monitoring

The `-l` option accepts a comma-separated list of label selectors. For each selector, the script resolves the matching pods at startup and watches them throughout the session.

**Label selector formats accepted:**

| Input | Interpreted as |
|-------|---------------|
| `sas-logon-app` | `app=sas-logon-app` (bare values default to the `app` key) |
| `app=sas-logon-app` | `app=sas-logon-app` |
| `app.kubernetes.io/name=sas-cas-server` | `app.kubernetes.io/name=sas-cas-server` |

For each pod and container (including init containers), the script runs `kubectl logs -f` in the background to stream logs to disk in real time.

### Log rotation handling

Kubernetes container runtimes rotate log files on the node. `kviya-recorder` detects and handles this in two ways:

1. **kubectl process exits while the container is still running** — the script queries the container's `state.running` field. If the container is still up, the exit is treated as an unexpected termination caused by log rotation: the collector is marked for restart and begins capturing again on the next loop iteration.

2. **kubectl process is still running but the log file has not been updated for more than one minute** — the script compares the last line written to disk against the current last line reported by `kubectl logs --tail=1`. If they differ, the log has rolled over: the stale process is killed and collection restarts. If they match, the pod is simply quiet and monitoring continues.

### Pod recreation handling

If a pod is deleted and recreated with the same name (e.g., due to a Kubernetes rollout or crash loop), the script detects the pod's return and automatically resumes log collection under a new instance number, preserving all previously collected data.

---

## Stopping the capture

Press **Ctrl+C** at any time. The script will:

1. Stop all background log collector processes.
2. Compress any in-progress log files.
3. Move logs and pod descriptions into the archive structure.
4. Save the final `.tgz` playback file to the path specified by `-o`.

If `-t` is used, the script stops automatically when the target time is reached and performs the same cleanup.

---

## Troubleshooting

### Log monitor activity log

When `-l` is used, a timestamped log of all log-monitoring events is written to `logs/kviya-recorder_logmon.log` inside the playback archive. This file is useful for diagnosing gaps in collected logs. Events recorded include:

- Log collection started for a pod/container
- Log collector exited because the container stopped
- Log collector exited unexpectedly (possible log rotation) — restart scheduled
- Log file stale for more than one minute — checking for roll-over
- Log roll-over confirmed — stale collector killed, restart scheduled
- Log file stale but matches latest pod log — no roll-over, monitoring continues
- Pod no longer available — log collection stopped
- Pod available again — log collection restarted

Example entries:

```
[2024-03-15 10:22:01] INFO: Starting log collection for pod 'sas-cas-server-default-worker-0', container 'sas-cas-server' (instance 0).
[2024-03-15 10:45:17] WARNING: Log file for pod 'sas-cas-server-default-worker-0', container 'sas-cas-server' (instance 0) has not been updated for more than a minute. Checking for log roll-over.
[2024-03-15 10:45:18] WARNING: Log roll-over detected for pod 'sas-cas-server-default-worker-0', container 'sas-cas-server' (instance 0). Most recent log line differs from last captured line. Killing stale collector (PID 18432) and scheduling restart.
[2024-03-15 10:45:19] INFO: Pod 'sas-cas-server-default-worker-0' is available again (instance 0 -> 1). Restarting log collection for all containers.
[2024-03-15 10:45:19] INFO: Starting log collection for pod 'sas-cas-server-default-worker-0', container 'sas-cas-server' (instance 1).
```

### Common issues

**`ERROR: No namespace set on the current context.`**
No `-n` option was provided and the current kubeconfig context has no default namespace. Either add `-n <namespace>` or update your context with `kubectl config set-context --current --namespace=<namespace>`.

**`ERROR: Unable to create the output file`**
The path given to `-o` is not writable. Check permissions or choose a different path.

**`ERROR: Playback directory is empty.`**
The script was interrupted before any snapshot completed. Run for a longer period or use `-s` to take a single snapshot.

**Gaps in collected logs**
Check `logs/kviya-recorder_logmon.log` inside the playback archive. Look for `WARNING` entries indicating log roll-over events or unexpected collector exits to identify when and why a gap occurred.

---

## License

Copyright © 2023, SAS Institute Inc., Cary, NC, USA. All Rights Reserved.  
SPDX-License-Identifier: Apache-2.0