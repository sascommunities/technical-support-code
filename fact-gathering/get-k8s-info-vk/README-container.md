## Running get-k8s-info.sh in a Container (gki-container.sh)

`gki-container.sh` is an **optional** companion script for running [`get-k8s-info.sh`](README.md) inside a container, for jumpboxes that don't meet the native prerequisites documented in [README.md](README.md) — most commonly **macOS**, **Windows**, or any host with an old Bash version or non-GNU userland.

`get-k8s-info.sh` itself is **not modified** by this method. It remains a single, read-only, self-contained script that only queries the cluster and packages a `.tgz` file — the same script you'd run natively. `gki-container.sh` is deliberately a **separate** file because it does things the script never does on its own: it builds a container image and launches a container. You only need `gki-container.sh` if you choose to use the container method.

### Requirements
- **Docker** or **Podman** installed on the jumpbox
- `gki-container.sh` and `get-k8s-info.sh` in the same directory
- Your kubeconfig (defaults to `$KUBECONFIG` or `~/.kube/config`)
- Internet access at **build** time only when the selected base image or required tools are not already available locally (see [Base Image](#base-image) below)

### Base Image

`gki-container.sh` builds an image that runs `get-k8s-info.sh` in a known-good Linux environment. Unless `--base` is supplied, it checks local availability and asks you to select one of three bases:

1. **Private `sas-orchestration` image (~900 MB)**. This option is usable when the image is already available locally. It includes the required tools and is useful for restricted or offline environments. See the `docker pull`/`docker tag` commands in `$deploy/sas-bases/examples/kubernetes-tools/README.md`.
2. **Public Red Hat UBI9-minimal image (~230 MB)**. Downloaded during the build; requires internet access at build time. The resulting image is considerably smaller; required tools (`kubectl`, `jq`, `tar`, `openssl`, `openssh-clients`, `ncurses`, `procps-ng`) are installed during the build.
3. **A custom image specified by you**. It must provide Bash 5+ and GNU coreutils; other missing tools (`kubectl`, `jq`, `gawk`, `tar`, `openssl`, an SSH client, `ncurses`, and `procps`) are installed automatically for RHEL-family (dnf/microdnf/yum) and Debian-family (apt-get) base images (requires internet access). Base images that use a different package manager must already provide these tools.

Unavailable choices do not silently fall back to another image. The launcher explains the problem and asks again. Use `--base <image:tag>` to skip the selection prompt for automation or a pre-approved image.

### Usage

```
./gki-container.sh build [options]
./gki-container.sh run [options] [get-k8s-info.sh options]
```

- **`build`** creates (or rebuilds) the container image only.
- **`run`** builds the image only if it doesn't already exist, then runs the script. This is the command you'll use for everyday collections.

#### Command-line Mode Example

```
./gki-container.sh run --deploypath /home/user/viyadeployments/prod --out /tmp --case CS0000000
```

Any option that `get-k8s-info.sh` itself accepts — `--case`, `--namespaces`, `--workers`, `--disabletags`, `--sastsdrive`, and so on — can be passed directly to `run`, in any order. Options this launcher owns (below) are handled locally; everything else is forwarded to `get-k8s-info.sh` unchanged.

#### Launcher-Owned Options

These mirror the native `get-k8s-info.sh` option names and mount the corresponding host paths into the container:

- **-p | --deploypath \<path\|unavailable\>**<br>Path to the Viya `$deploy` directory. If omitted, you'll be prompted (same wording as the native script), defaulting to the current directory. The literal `unavailable` skips deployment-asset collection, same as the native script.
- **-o | --out \<path\>**<br>Host output directory. If omitted, you'll be prompted, defaulting to the current directory. The final `.tgz` is written here, owned by your host user.
- **-i | --tfvars \<path\|unavailable\>**<br>Path to the `terraform.tfvars` file used by the IaC project. Mounted read-only into the container. The literal `unavailable` skips IaC-file collection, same as the native script.
- **-a | --ansiblevars \<path\|unavailable\>**<br>Path to the `ansible-vars.yaml` file used by the DaC project. Mounted read-only into the container. The literal `unavailable` skips DaC-file collection, same as the native script.
- **--kubeconfig \<path\>**<br>Kubeconfig to use. Defaults to `$KUBECONFIG` or `~/.kube/config`.

#### Build-Only Options

- **--base \<image[:tag]\>**<br>Use a specific base image without displaying the base-image selection prompt.
- **--kubectl-version \<X.Y.Z\|X.Y\>**<br>Pin the kubectl version installed when the resolved base doesn't already provide one. A bare minor version (e.g. `1.33`) resolves to the latest patch release. Skips the interactive prompt / cluster-version detection described below.
- **--rebuild**<br>Force a rebuild even if a matching image already exists.
- **--dockerfile \<directory\>**<br>Generate the exact build context without building an image. The directory receives `Dockerfile`, `get-k8s-info.sh`, and `gki-entrypoint.sh` for inspection. Existing generated files are never overwritten. When no container engine is installed, provide `--base <image:tag>` because automatic base-image detection is unavailable.
- **--image \<name\>**<br>Override the built/executed image name (advanced).
- **--engine \<docker\|podman\>**<br>Force a specific container engine instead of auto-detecting.
- **-u | --no-update**<br>Do not check for newer `gki-container.sh` or `get-k8s-info.sh` versions.
- **-v | --version**<br>Show the launcher version.
- **-h | --help | --usage**<br>Show usage information.

### kubectl Version Detection

When the resolved base image doesn't already provide `kubectl` (i.e. the public-image or custom-base path), `gki-container.sh` tries to detect your cluster's Kubernetes API server version from the jumpbox's own `kubectl`/`oc` client (the same detection logic `get-k8s-info.sh` itself uses), and offers it as the default when prompting for which kubectl version to install:
```
 -> Detected Kubernetes API server version 1.33.2. Specify the kubectl version to install (1.33.2):
```
Press ENTER to accept the detected version, or type a different one. If the cluster can't be reached from the jumpbox, you'll be asked to provide a version manually. Use `--kubectl-version` to skip this prompt entirely.

### Authentication

No extra steps are needed for most kubeconfigs (certificate- or token-based). If your kubeconfig authenticates via an **exec-based** credential plugin (for example, Azure AD/`kubelogin`), `gki-container.sh` mints the token **on the jumpbox** — where the plugin and its cache already exist — and hands the container only the resulting credential. This happens automatically; no additional options are required.

### If Deployment Asset Files Are Needed But Not Provided

If `get-k8s-info.sh` detects that IaC (`terraform.tfvars`) or DaC (`ansible-vars.yaml`) files were used for the deployment but they were not supplied via `--tfvars`/`--ansiblevars`, it will offer to skip collecting them or ask you to re-run with the file(s) provided. If you choose to re-run, `gki-container.sh` prints a ready-to-use command with the missing option(s) added, for example:
```
./gki-container.sh run --deploypath /home/user/viyadeployments/prod --out /tmp --tfvars <path-to-terraform.tfvars>
```

### Examples

```
# Build the image (reports local availability and prompts for the base image)
./gki-container.sh build

# Generate the build context for inspection without building the image
./gki-container.sh build --dockerfile ./gki-build-context \
    --base my-registry/my-ubi9:latest --kubectl-version 1.31

# Run interactively (prompts for deploy path, output path, case number, etc.)
./gki-container.sh run

# Run non-interactively
./gki-container.sh run --deploypath /home/user/viyadeployments/prod --out /tmp \
    --case CS0000000 --namespaces viya

# No local deployment assets available
./gki-container.sh run --deploypath unavailable --out /tmp --case CS0000000

# Force a specific base image and kubectl version
./gki-container.sh build --base my-registry/my-ubi9:latest --kubectl-version 1.31
```

### Notes
- The launcher checks both scripts before a build or run. If either has a newer version, it lists all available updates and asks once whether to update the scripts and rebuild the image.
- The rolling `get-k8s-info` image stores its script version in a label. A matching image is reused; a mismatch prompts before rebuilding, and `--rebuild` forces a fresh build.
- OpenShift's `oc` client is not required inside the container; the script falls back to `kubectl` automatically, same as it does natively.
- On Podman/RHEL with SELinux, bind mounts are labeled automatically.
