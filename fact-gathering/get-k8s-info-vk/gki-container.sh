#!/usr/bin/env bash
# =============================================================================
# gki-container.sh
#
# Optional companion for running SAS Technical Support's get-k8s-info.sh inside
# a container on hosts that cannot run the script natively, such as macOS.
#
# get-k8s-info.sh remains unchanged. This separate launcher builds an image, 
# handles container mounts, optionally mints an exec-plugin credential on the 
# host, and launches the container.
#
# Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# =============================================================================

set -eu

LAUNCHER_VERSION='1.0.0'
GKI_CAPS='deploy,tfvars,ansiblevars'
DEFAULT_UPDATE_URL='https://raw.githubusercontent.com/sascommunities/technical-support-code/main/fact-gathering/get-k8s-info-vk/get-k8s-info.sh'
DEFAULT_LAUNCHER_UPDATE_URL='https://raw.githubusercontent.com/sascommunities/technical-support-code/main/fact-gathering/get-k8s-info-vk/gki-container.sh'

SELF="$0"
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_FILE="$SELF_DIR/get-k8s-info.sh"
# Bare filename only (no directory), kept for display / URL-matching purposes.
LAUNCHER_SCRIPT_FILE=$(echo "$0" | rev | cut -d '/' -f1 | rev)
# Full, absolute path to this launcher's own file.
LAUNCHER_FILE="$SELF_DIR/$LAUNCHER_SCRIPT_FILE"

CPATH_DEPLOY='/gki/deploy'
CPATH_OUT='/gki/out'
CPATH_TFVARS='/gki/terraform.tfvars'
CPATH_ANSIBLE='/gki/ansible-vars.yaml'

# Public base image options offered in the base-selection menu. Both are the
# same GNU/bash userland already validated for get-k8s-info.sh (bash 5, GNU
# coreutils incl. csplit, GNU awk), freely pullable, with any missing packages
# installed at build time. UBI9-minimal is RHEL-family (dnf/microdnf); Ubuntu
# is Debian-family (apt) and produces a smaller final image.
UBI_BASE_IMAGE='registry.access.redhat.com/ubi9-minimal:latest'
UBUNTU_BASE_IMAGE='ubuntu:24.04'

log()  { printf 'INFO:  %s\n' "$*"; }
warn() { printf 'WARN:  %s\n' "$*" >&2; }
err()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'GKI_USAGE'
gki-container.sh - run get-k8s-info.sh inside a container

USAGE
  ./gki-container.sh build [options]
  ./gki-container.sh run [options] [-- <get-k8s-info.sh options>]

Launcher options:
  -h | --help | --usage
        Show this help.
  -v | --version
        Show the launcher version.
  -u | --no-update
        Do not check for newer gki-container.sh or get-k8s-info.sh scripts.
  --rebuild
        Force an image rebuild.
  --dockerfile <directory>
        Generate an inspectable Dockerfile build context in the directory and
        exit without building an image. Valid only with the build subcommand.
  --base <image[:tag]>
        Use this base image without prompting for a base-image choice.
  --kubectl-version <X.Y.Z|X.Y>
        Pin the kubectl version installed when the base image does not already
      provide one (UBI9-minimal, Ubuntu, a custom base, or --base). A bare
        minor version (e.g. 1.33) resolves to the latest patch release.
        Skips the interactive prompt / cluster-version detection below.
  --image <name>
        Override the image used for execution.
  --engine <docker|podman>
        Force the container engine.

Unless --base is given, the launcher asks you to choose a base image: a locally
available sas-orchestration image (~900 MB), the public UBI9-minimal image
(~230 MB), Ubuntu 24.04 LTS (~165 MB), or a custom image. The public images are
pulled during the first build and cached afterward. Missing tools are installed
automatically for the UBI9-minimal, Ubuntu, and custom-image choices.

Launcher-owned get-k8s-info options:
  -p | --deploypath <path|unavailable>
        Host path to the Viya $deploy directory. If omitted, prompts with the
        current host directory as the default. It is mounted at /gki/deploy.
        The literal 'unavailable' is passed through without creating a mount.
  -o | --out <path>
        Host output directory. If omitted, prompts with the current host
        directory as the default. It is mounted at /gki/out.
  -i | --tfvars <path|unavailable>
        Optional terraform.tfvars file. Mounted read-only at
        /gki/terraform.tfvars.
  -a | --ansiblevars <path|unavailable>
        Optional ansible-vars.yaml file. Mounted read-only at
        /gki/ansible-vars.yaml.
  --kubeconfig <path>
        Kubeconfig path. Defaults to $KUBECONFIG or ~/.kube/config.

During 'run', any option not recognized by this launcher is forwarded to
get-k8s-info.sh unchanged. 
Case, namespace, workers, disable tags, SASTSDrive, and
their native aliases all work directly, e.g.:
  ./gki-container.sh run --case CS1234567 --namespaces viya --workers 10

Examples:
  ./gki-container.sh build
  ./gki-container.sh build --dockerfile ./gki-build-context --base <image:tag>
  ./gki-container.sh run
  ./gki-container.sh run --deploypath /path/to/deploy --out ./output \
      --case CS1234567 --namespaces viya
  ./gki-container.sh run --deploypath unavailable --tfvars ./terraform.tfvars
GKI_USAGE
}

SUBCMD=''
DO_UPDATE='true'
UPDATE_CHECKED='false'
UPDATE_DECLINED='false'
FORCE_REBUILD='false'
DOCKERFILE_DIR=''
BASE_OVERRIDE=''
KUBECTL_VERSION_FLAG=''
IMAGE_OVERRIDE=''
ENGINE=''
KUBECONFIG_SRC="${KUBECONFIG:-$HOME/.kube/config}"
DEPLOY_SRC=''
DEPLOY_GIVEN='false'
TFVARS_SRC=''
ANSIBLE_SRC=''
OUT_SRC=''
OUT_GIVEN='false'

# Snapshot the arguments before the parsing loop shifts them away, so they can
# be passed to the new launcher after an accepted update.
originalArgs=("$@")

[ $# -ge 1 ] || { usage; exit 1; }
case "$1" in
    build|run) SUBCMD="$1"; shift ;;
    -h|--help|--usage) usage; exit 0 ;;
    -v|--version) printf 'gki-container.sh v%s\n' "$LAUNCHER_VERSION"; exit 0 ;;
    *) err "unknown subcommand '$1' (expected 'build' or 'run'; see --help)" ;;
esac

set +u
PT=()
set -u
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help|--usage) usage; exit 0 ;;
        -v|--version) printf 'gki-container.sh v%s\n' "$LAUNCHER_VERSION"; exit 0 ;;
        -u|--no-update) DO_UPDATE='false'; shift ;;
        --rebuild) FORCE_REBUILD='true'; shift ;;
        --dockerfile) [ $# -ge 2 ] || err "$1 requires a value"; [ "$SUBCMD" = 'build' ] || err "$1 is valid only with the build subcommand"; DOCKERFILE_DIR="$2"; shift 2 ;;
        --base) [ $# -ge 2 ] || err "$1 requires a value"; BASE_OVERRIDE="$2"; shift 2 ;;
        --kubectl-version) [ $# -ge 2 ] || err "$1 requires a value"; KUBECTL_VERSION_FLAG="$2"; shift 2 ;;
        --image) [ $# -ge 2 ] || err "$1 requires a value"; IMAGE_OVERRIDE="$2"; shift 2 ;;
        --engine) [ $# -ge 2 ] || err "$1 requires a value"; ENGINE="$2"; shift 2 ;;
        --kubeconfig) [ $# -ge 2 ] || err "$1 requires a value"; KUBECONFIG_SRC="$2"; shift 2 ;;
        -p|--deploypath) [ $# -ge 2 ] || err "$1 requires a value"; DEPLOY_SRC="$2"; DEPLOY_GIVEN='true'; shift 2 ;;
        -o|--out) [ $# -ge 2 ] || err "$1 requires a value"; OUT_SRC="$2"; OUT_GIVEN='true'; shift 2 ;;
        -i|--tfvars) [ $# -ge 2 ] || err "$1 requires a value"; TFVARS_SRC="$2"; shift 2 ;;
        -a|--ansiblevars) [ $# -ge 2 ] || err "$1 requires a value"; ANSIBLE_SRC="$2"; shift 2 ;;
        --)
            shift
            while [ $# -gt 0 ]; do PT[${#PT[@]}]="$1"; shift; done
            break
            ;;
        *)
            if [ "$SUBCMD" = 'run' ]; then
                # Not a launcher option: forward it unchanged to get-k8s-info.sh.
                # This lets native script options (--case, --namespaces,
                # --workers, --disabletags, --sastsdrive, etc.) be passed
                # directly to `run` without requiring '--' first. get-k8s-info.sh
                # remains the authority on validating these options.
                PT[${#PT[@]}]="$1"
                shift
            else
                err "unknown build option '$1'"
            fi
            ;;
    esac
done

if [ -z "$ENGINE" ]; then
    if command -v docker >/dev/null 2>&1; then ENGINE='docker'
    elif command -v podman >/dev/null 2>&1; then ENGINE='podman'
    elif [ -z "$DOCKERFILE_DIR" ] || [ -z "$BASE_OVERRIDE" ]; then
        err "neither 'docker' nor 'podman' was found in PATH"
    fi
fi
[ -z "$ENGINE" ] || command -v "$ENGINE" >/dev/null 2>&1 || err "engine '$ENGINE' was not found in PATH"
[ -f "$SCRIPT_FILE" ] || err "get-k8s-info.sh was not found next to this launcher: $SCRIPT_FILE"

version_is_newer() {
    local candidate="$1" installed="$2" candidate_part installed_part index max_parts
    local -a candidate_parts installed_parts

    [[ "$candidate" =~ ^[0-9]+(\.[0-9]+)*$ && "$installed" =~ ^[0-9]+(\.[0-9]+)*$ ]] || return 1
    IFS='.' read -r -a candidate_parts <<< "$candidate"
    IFS='.' read -r -a installed_parts <<< "$installed"
    max_parts=${#candidate_parts[@]}
    [ ${#installed_parts[@]} -gt "$max_parts" ] && max_parts=${#installed_parts[@]}

    for ((index = 0; index < max_parts; index++)); do
        candidate_part=${candidate_parts[index]:-0}
        installed_part=${installed_parts[index]:-0}
        if ((10#$candidate_part > 10#$installed_part)); then return 0; fi
        if ((10#$candidate_part < 10#$installed_part)); then return 1; fi
    done
    return 1
}

maybe_update() {
    [ "$UPDATE_CHECKED" = 'false' ] || return 0
    UPDATE_CHECKED='true'
    [ "$DO_UPDATE" = 'true' ] || { log 'autoupdate disabled (--no-update); using local launcher and get-k8s-info.sh scripts'; return 0; }
    command -v curl >/dev/null 2>&1 || { warn 'curl was not found; skipping autoupdate'; return 0; }

    launcher_update_url="$(grep -oE 'https?://[^ "'\''\`]*gki-container\.sh' "$LAUNCHER_FILE" | head -1 || true)"
    [ -n "${launcher_update_url:-}" ] || launcher_update_url="$DEFAULT_LAUNCHER_UPDATE_URL"
    update_url="$(grep -oE 'https?://[^ "'\''\`]*get-k8s-info\.sh' "$SCRIPT_FILE" | head -1 || true)"
    [ -n "${update_url:-}" ] || update_url="$DEFAULT_UPDATE_URL"

    # Fetch both candidates before changing either local file so the user gets
    # one decision for the complete launcher/script update.
    launcher_candidate=''
    script_candidate=''
    launcher_local_version="$LAUNCHER_VERSION"
    script_local_version="$(grep -m1 '^version=' "$SCRIPT_FILE" | cut -d "'" -f2 | sed 's/^get-k8s-info v//')"

    log 'checking for latest gki-container.sh ...'
    if curl -fsSL "$launcher_update_url" -o "$LAUNCHER_FILE.new" 2>/dev/null && grep -q '^LAUNCHER_VERSION' "$LAUNCHER_FILE.new"; then
        launcher_remote_version="$(sed -n "s/^LAUNCHER_VERSION=['\"]\([0-9][0-9.]*\)['\"]$/\1/p" "$LAUNCHER_FILE.new" | head -1)"
        if version_is_newer "$launcher_remote_version" "$launcher_local_version"; then
            launcher_candidate="$LAUNCHER_FILE.new"
        fi
    else
        warn 'could not fetch the latest gki-container.sh; using the local copy'
    fi

    log 'checking for latest get-k8s-info.sh ...'
    if curl -fsSL "$update_url" -o "$SCRIPT_FILE.new" 2>/dev/null && grep -q '^version=' "$SCRIPT_FILE.new"; then
        script_remote_version="$(grep -m1 '^version=' "$SCRIPT_FILE.new" | cut -d "'" -f2 | sed 's/^get-k8s-info v//')"
        if version_is_newer "$script_remote_version" "$script_local_version"; then
            script_candidate="$SCRIPT_FILE.new"
        fi
    else
        warn 'could not fetch latest script; using the local copy'
    fi

    if [ -n "$launcher_candidate" ] || [ -n "$script_candidate" ]; then
        warn 'A new version is available! It is highly recommended to use the latest version.'
        [ -n "$launcher_candidate" ] && warn "gki-container.sh: v$launcher_local_version -> v$launcher_remote_version"
        [ -n "$script_candidate" ] && warn "get-k8s-info.sh: v$script_local_version -> v$script_remote_version"
        if [ -n "$DOCKERFILE_DIR" ]; then update_action='generate the Dockerfile build context'
        else update_action='rebuild the image'
        fi
        update_answer=''
        read -r -p "Do you want to update the scripts and $update_action? (y/n) " update_answer || true
        if [ "$update_answer" = 'y' ] || [ "$update_answer" = 'Y' ]; then
            launcher_updated='false'
            if [ -n "$launcher_candidate" ]; then
                if ! mv "$LAUNCHER_FILE.new" "$LAUNCHER_FILE" || ! chmod +x "$LAUNCHER_FILE"; then
                    rm -f "$LAUNCHER_FILE.new" "$SCRIPT_FILE.new" 2>/dev/null || true
                    err "failed to update gki-container.sh. Update it manually from https://github.com/sascommunities/technical-support-code/tree/main/fact-gathering/get-k8s-info-vk"
                fi
                launcher_updated='true'
            fi
            if [ -n "$script_candidate" ]; then
                if ! mv "$SCRIPT_FILE.new" "$SCRIPT_FILE" || ! chmod +x "$SCRIPT_FILE"; then
                    rm -f "$LAUNCHER_FILE.new" "$SCRIPT_FILE.new" 2>/dev/null || true
                    err "failed to update get-k8s-info.sh. Update it manually from https://github.com/sascommunities/technical-support-code/tree/main/fact-gathering/get-k8s-info-vk"
                fi
            fi
            if [ "$launcher_updated" = 'true' ]; then
                rm -f "$LAUNCHER_FILE.new" "$SCRIPT_FILE.new" 2>/dev/null || true
                log "scripts updated; restarting gki-container.sh v$launcher_remote_version to $update_action"
                exec "$LAUNCHER_FILE" "${originalArgs[0]}" --no-update --rebuild "${originalArgs[@]:1}"
            fi
            FORCE_REBUILD='true'
            log "updated get-k8s-info.sh; continuing to $update_action"
        else
            UPDATE_DECLINED='true'
            log 'using the local scripts and existing image; no updates applied'
        fi
    fi

    rm -f "$LAUNCHER_FILE.new" "$SCRIPT_FILE.new" 2>/dev/null || true
}

read_version() {
    VERSION="$(grep -m1 '^version=' "$SCRIPT_FILE" | cut -d "'" -f2 | sed 's/^get-k8s-info v//')"
    [ -n "${VERSION:-}" ] || err "could not parse the version from get-k8s-info.sh"
    IMAGE_TAG='get-k8s-info'
    IMAGE="${IMAGE_OVERRIDE:-$IMAGE_TAG}"
}

resolve_base() {
    # NEEDS_TOOLS='true' means kubectl/jq/tar/openssl/ssh/tput/procps are not
    # guaranteed present in the resolved base and the Dockerfile must
    # ensure/install them. It stays 'false' only for the two auto-detected
    # sas-orchestration cases, which we already know provide everything.
    NEEDS_TOOLS='false'

    if [ -n "$BASE_OVERRIDE" ]; then
        BASE_IMAGE="$BASE_OVERRIDE"
        NEEDS_TOOLS='true'
        return 0
    fi
    sas_base=''
    if "$ENGINE" image inspect sas-orchestration >/dev/null 2>&1; then
        sas_base='sas-orchestration'
    else
        sas_base="$("$ENGINE" images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep '/sas-orchestration:' | grep -v '<none>' | head -1 || true)"
    fi
    if [ -n "$sas_base" ]; then sas_status="available locally as $sas_base"
    else sas_status='not available locally'
    fi

    while true; do
        printf '\nSelect the container base image:\n' >&2
        printf '  [1] sas-orchestration (~900 MB) - %s\n' "$sas_status" >&2
        printf '  [2] Red Hat UBI9-minimal (~230 MB) - pulled on first build (requires internet access), cached afterward\n' >&2
        printf '  [3] Canonical Ubuntu 24.04 LTS (~165 MB) - pulled on first build (requires internet access), cached afterward\n' >&2
        printf '  [4] Custom image specified by you - It must provide Bash 5+ and GNU coreutils; missing tools are installed automatically (requires internet access)\n' >&2
        printf '  [5] Cancel\n\n' >&2
        base_choice=''
        read -r -p ' -> Select an option (1/2/3/4/5): ' base_choice || err 'unable to read a base-image choice; use --base <image:tag> for non-interactive execution'

        case "$base_choice" in
            1)
                if [ -z "$sas_base" ]; then
                    warn 'sas-orchestration is not available locally; See the docker pull/docker tag commands in sas-bases/examples/kubernetes-tools/README.md.'
                    continue
                fi
                BASE_IMAGE="$sas_base"
                NEEDS_TOOLS='false'
                return 0
                ;;
            2)
                BASE_IMAGE="$UBI_BASE_IMAGE"
                NEEDS_TOOLS='true'
                return 0
                ;;
            3)
                BASE_IMAGE="$UBUNTU_BASE_IMAGE"
                NEEDS_TOOLS='true'
                return 0
                ;;
            4)
                custom_base=''
                read -r -p ' -> Specify the custom base image (image[:tag]): ' custom_base || err 'unable to read a custom base image; use --base <image:tag> for non-interactive execution'
                if [ -z "$custom_base" ]; then
                    warn 'no custom base image was specified.'
                    continue
                fi
                BASE_IMAGE="$custom_base"
                NEEDS_TOOLS='true'
                return 0
                ;;
            5)
                log 'base-image selection canceled; no image was built.'
                exit 0
                ;;

            *) warn "invalid base-image option '$base_choice'; enter 1, 2, 3, 4, or 5." ;;
        esac
    done
}

# ----- Resolve which kubectl version to install ------------------------------
# Sets KUBECTL_VERSION_RESOLVED (always non-empty on return). Only called when
# NEEDS_TOOLS='true'.
resolve_kubectl_version() {
    if [ -n "$KUBECTL_VERSION_FLAG" ]; then
        KUBECTL_VERSION_RESOLVED="$(normalize_kubectl_version "$KUBECTL_VERSION_FLAG")"
        return 0
    fi

    # Mirror get-k8s-info.sh's own kubectl-vs-oc / OpenShift detection so the
    # same logic decides which client to query on this host.
    detect_kcmd=''
    if command -v kubectl >/dev/null 2>&1 && command -v oc >/dev/null 2>&1; then
        if oc version -o yaml 2>/dev/null | grep -q openshift; then detect_kcmd='oc'; else detect_kcmd='kubectl'; fi
    elif command -v kubectl >/dev/null 2>&1; then detect_kcmd='kubectl'
    elif command -v oc >/dev/null 2>&1; then detect_kcmd='oc'
    fi

    detected_version=''
    if [ -n "$detect_kcmd" ]; then
        raw="$("$detect_kcmd" version -o yaml 2>/dev/null | grep serverVersion -A9 | grep gitVersion | cut -d ' ' -f4 | cut -d '+' -f1 | cut -d '-' -f1 2>/dev/null || true)"
        detected_version="${raw#v}"
    fi

    ans=''
    if [ -n "$detected_version" ]; then
        read -p " -> Detected Kubernetes API server version $detected_version. Specify the kubectl version to install ($detected_version): " ans || true
        [ -n "$ans" ] || ans="$detected_version"
    else
        warn "could not detect the cluster's Kubernetes API server version from this host (no working kubectl/oc, or the cluster is unreachable)."
        while [ -z "$ans" ]; do
            read -p " -> Specify the kubectl version to install (e.g. 1.33 or 1.33.2): " ans || true
        done
    fi
    KUBECTL_VERSION_RESOLVED="$(normalize_kubectl_version "$ans")"
}

# ----- Normalize a user-supplied version to a concrete release tag -----------
# Accepts "1.33.2", "v1.33.2" (used as-is) or "1.33" (resolved to the latest
# patch via the official Kubernetes stable-release pointer).
normalize_kubectl_version() {
    v="${1#v}"
    dots="$(printf '%s' "$v" | tr -cd '.' | wc -c | tr -d ' ')"
    if [ "$dots" = '1' ]; then
        resolved="$(curl -fsSL "https://dl.k8s.io/release/stable-${v}.txt" 2>/dev/null || true)"
        [ -n "$resolved" ] || err "could not resolve the latest patch release for kubectl ${v}.x (check network access or the version number)."
        printf '%s' "${resolved#v}"
    else
        printf '%s' "$v"
    fi
}

write_entrypoint() {
    cat > "$1" <<'WRAP'
#!/bin/bash
set -eu
ORIG_KCFG="${KUBECONFIG:-/home/sas/.kube/config}"
CRED_FILE='/home/sas/.gki/execcred.json'

if [ -f "$CRED_FILE" ]; then
    command -v jq >/dev/null 2>&1 || { echo 'gki-entrypoint: ERROR: jq not found in image' >&2; exit 1; }
    token="$(jq -r '.status.token // empty' "$CRED_FILE")"
    [ -n "$token" ] || { echo 'gki-entrypoint: ERROR: no token in credential file' >&2; exit 1; }

    config_json="$(kubectl --kubeconfig "$ORIG_KCFG" config view --minify --raw -o json)"
    server="$(printf '%s' "$config_json" | jq -r '.clusters[0].cluster.server // empty')"
    insecure="$(printf '%s' "$config_json" | jq -r '.clusters[0].cluster["insecure-skip-tls-verify"] // empty')"
    ns="$(printf '%s' "$config_json" | jq -r '.contexts[0].context.namespace // empty')"
    cadata="$(kubectl --kubeconfig "$ORIG_KCFG" config view --minify --flatten -o json 2>/dev/null | jq -r '.clusters[0].cluster["certificate-authority-data"] // empty')"
    [ -n "$server" ] || { echo 'gki-entrypoint: ERROR: could not read cluster server' >&2; exit 1; }

    umask 077
    dest="$(mktemp "${TMPDIR:-/tmp}/gki-kubeconfig.XXXXXX")"
    {
        echo 'apiVersion: v1'
        echo 'kind: Config'
        echo 'clusters:'
        echo '- name: gki'
        echo '  cluster:'
        echo "    server: $server"
        if [ -n "$cadata" ]; then echo "    certificate-authority-data: $cadata"
        elif [ "$insecure" = 'true' ]; then echo '    insecure-skip-tls-verify: true'; fi
        echo 'contexts:'
        echo '- name: gki'
        echo '  context:'
        echo '    cluster: gki'
        echo '    user: gki'
        [ -n "$ns" ] && echo "    namespace: $ns"
        echo 'current-context: gki'
        echo 'users:'
        echo '- name: gki'
        echo '  user:'
        echo "    token: $token"
    } > "$dest"
    export KUBECONFIG="$dest"
else
    export KUBECONFIG="$ORIG_KCFG"
fi

exec /usr/local/bin/get-k8s-info.sh "$@"
WRAP
}

do_build() {
    maybe_update
    read_version
    resolve_base
    [ -z "$DOCKERFILE_DIR" ] && log "engine            = $ENGINE"
    log "base image        = $BASE_IMAGE"
    log "script version = $VERSION"
    [ -z "$DOCKERFILE_DIR" ] && log "image tag         = $IMAGE_TAG"

    # Capture the image ID the tag currently points at (if any) so it can be
    # removed after a successful rebuild, instead of being left dangling.
    old_image_id=''
    if [ -z "$DOCKERFILE_DIR" ]; then
        old_image_id="$("$ENGINE" image inspect --format '{{.Id}}' "$IMAGE_TAG" 2>/dev/null || true)"
    fi

    KUBECTL_VERSION_RESOLVED=''
    if [ "$NEEDS_TOOLS" = 'true' ]; then
        resolve_kubectl_version
        log "kubectl version   = $KUBECTL_VERSION_RESOLVED (installed only if not already present in the base)"
    fi

    if [ -n "$DOCKERFILE_DIR" ]; then
        DOCKERFILE_DIR="${DOCKERFILE_DIR/#\~/$HOME}"
        mkdir -p "$DOCKERFILE_DIR" || err "could not create Dockerfile directory: $DOCKERFILE_DIR"
        bctx="$(cd "$DOCKERFILE_DIR" && pwd)"
        for generated_file in Dockerfile get-k8s-info.sh gki-entrypoint.sh; do
            [ ! -e "$bctx/$generated_file" ] || err "refusing to overwrite existing build-context file: $bctx/$generated_file"
        done
    else
        bctx="$(mktemp -d "${TMPDIR:-/tmp}/gki-build.XXXXXX")"
        # Expand $bctx NOW so the literal directory is baked into the cleanup trap.
        # $bctx was just assigned and is never changed; eager expansion therefore
        # guarantees that this exact temporary directory is removed on exit.
        # shellcheck disable=SC2064
        trap "rm -rf \"$bctx\"" EXIT
    fi

    cp "$SCRIPT_FILE" "$bctx/get-k8s-info.sh"
    write_entrypoint "$bctx/gki-entrypoint.sh"
    cat > "$bctx/Dockerfile" <<EOF_DOCKER
FROM ${BASE_IMAGE}
USER root
ARG KUBECTL_VERSION=""
LABEL gki.script.version="${VERSION}"
LABEL gki.base.image="${BASE_IMAGE}"

# Ensure kubectl, jq, and the small set of CLI tools get-k8s-info.sh relies on
# are present, regardless of base image. This is a no-op on sas-orchestration
# (already provides everything). On any other base (public UBI9-minimal
# fallback, a customer-supplied image, or --base):
#   - kubectl and jq are installed as arch-aware static binaries (works with
#     or without a package manager in the base).
#   - gawk (GNU awk), tar, openssl, ssh/sftp (openssh-client(s)), tput
#     (ncurses), and ps/top (procps) are installed via whichever package
#     manager is present. RHEL-family (dnf/microdnf/yum) and Debian-family
#     (apt-get) package names are both handled; other package managers are
#     unsupported and the base must already provide the tools.
# Requires internet access on the build host.
RUN set -eu; \\
    arch="\$(uname -m)"; \\
    case "\$arch" in x86_64) barch=amd64 ;; aarch64|arm64) barch=arm64 ;; *) echo "Unsupported arch: \$arch" >&2; exit 1 ;; esac; \\
    need=""; \\
    command -v curl    >/dev/null 2>&1 || need="\$need curl"; \\
    command -v gawk    >/dev/null 2>&1 || need="\$need gawk"; \\
    command -v tar     >/dev/null 2>&1 || need="\$need tar"; \\
    command -v openssl >/dev/null 2>&1 || need="\$need openssl"; \\
    if command -v dnf >/dev/null 2>&1 || command -v microdnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then \\
        command -v ssh  >/dev/null 2>&1 || need="\$need openssh-clients"; \\
        command -v tput >/dev/null 2>&1 || need="\$need ncurses"; \\
        command -v ps   >/dev/null 2>&1 || need="\$need procps-ng"; \\
    else \\
        command -v ssh  >/dev/null 2>&1 || need="\$need openssh-client"; \\
        command -v tput >/dev/null 2>&1 || need="\$need ncurses-bin"; \\
        command -v ps   >/dev/null 2>&1 || need="\$need procps"; \\
    fi; \\
    if [ -n "\$need" ]; then \\
        echo "installing packages:\$need"; \\
        if command -v dnf >/dev/null 2>&1; then dnf install -y \$need && dnf clean all; \\
        elif command -v microdnf >/dev/null 2>&1; then microdnf install -y \$need && microdnf clean all; \\
        elif command -v yum >/dev/null 2>&1; then yum install -y \$need && yum clean all; \\
        elif command -v apt-get >/dev/null 2>&1; then apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \$need && rm -rf /var/lib/apt/lists/*; \\
        else echo "no supported package manager (dnf/microdnf/yum/apt-get) found to install:\$need" >&2; exit 1; \\
        fi; \\
    else \\
        echo "curl, gawk, tar, openssl, ssh, tput, ps already present; skipping package install"; \\
    fi; \\
    if command -v kubectl >/dev/null 2>&1; then \\
        echo "kubectl already present in the base image; skipping install"; \\
    else \\
        if [ -z "\$KUBECTL_VERSION" ]; then echo "kubectl is missing from the base image and no KUBECTL_VERSION was provided" >&2; exit 1; fi; \\
        echo "installing kubectl v\${KUBECTL_VERSION} (\$barch)"; \\
        curl -fL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/v\${KUBECTL_VERSION}/bin/linux/\${barch}/kubectl"; \\
        chmod 0755 /usr/local/bin/kubectl; \\
    fi; \\
    if command -v jq >/dev/null 2>&1; then \\
        echo "jq already present in the base image; skipping install"; \\
    else \\
        echo "installing jq (\$barch)"; \\
        curl -fL -o /usr/local/bin/jq "https://github.com/jqlang/jq/releases/latest/download/jq-linux-\${barch}"; \\
        chmod 0755 /usr/local/bin/jq; \\
    fi;

COPY get-k8s-info.sh /usr/local/bin/get-k8s-info.sh
COPY gki-entrypoint.sh /usr/local/bin/gki-entrypoint.sh
RUN chmod 0755 /usr/local/bin/get-k8s-info.sh /usr/local/bin/gki-entrypoint.sh
USER 1001
ENTRYPOINT ["/usr/local/bin/gki-entrypoint.sh"]
EOF_DOCKER

    if [ -n "$DOCKERFILE_DIR" ]; then
        build_engine="${ENGINE:-docker}"
        build_command="$(quote_arg "$build_engine") build --build-arg $(quote_arg "KUBECTL_VERSION=$KUBECTL_VERSION_RESOLVED") -t $(quote_arg "$IMAGE_TAG") $(quote_arg "$bctx")"
        log "generated Dockerfile build context: $bctx"
        log "inspect it, then build with: $build_command"
        return 0
    fi

    "$ENGINE" build \
        --build-arg "KUBECTL_VERSION=${KUBECTL_VERSION_RESOLVED}" \
        -t "$IMAGE_TAG" "$bctx"
    rm -rf "$bctx"
    trap - EXIT

    # If the rebuild produced a different image, remove the now-untagged
    # previous one so old builds don't accumulate as <none> images.
    new_image_id="$("$ENGINE" image inspect --format '{{.Id}}' "$IMAGE_TAG" 2>/dev/null || true)"
    if [ -n "$old_image_id" ] && [ "$old_image_id" != "$new_image_id" ]; then
        "$ENGINE" rmi "$old_image_id" >/dev/null 2>&1 || true
    fi

    log "built image: $IMAGE_TAG (script v$VERSION)"
}

ensure_image() {
    # Check for updates before deciding whether to rebuild. maybe_update is
    # idempotent within this launcher process, so do_build will not perform a
    # second network check.
    maybe_update
    read_version
    if [ "$FORCE_REBUILD" = 'true' ]; then do_build; return 0; fi

    # Single rolling image: rebuild only when it's missing or its baked-in
    # script-version label doesn't match the current get-k8s-info.sh version.
    existing_version="$("$ENGINE" image inspect --format '{{ index .Config.Labels "gki.script.version" }}' "$IMAGE_TAG" 2>/dev/null || true)"
    [ "$existing_version" = '<no value>' ] && existing_version=''
    if [ "$existing_version" = "$VERSION" ]; then
        log "image $IMAGE_TAG already present for script v$VERSION; skipping build (use --rebuild to force)"
    elif [ -n "$existing_version" ]; then
        warn "image $IMAGE_TAG is for script v$existing_version but current is v$VERSION."
        if [ "$UPDATE_DECLINED" = 'true' ]; then
            log "using image $IMAGE_TAG with script v$existing_version"
            return 0
        fi
        rebuild_answer=''
        read -r -p 'Do you want to rebuild the image now? (y/n) ' rebuild_answer || true
        if [ "$rebuild_answer" = 'y' ] || [ "$rebuild_answer" = 'Y' ]; then
            do_build
        else
            log "using image $IMAGE_TAG with script v$existing_version"
        fi
    else
        log "image $IMAGE_TAG not found; building ..."
        do_build
    fi
}

img_kubectl() {
    "$ENGINE" run --rm -i -v "$KUBECONFIG_SRC:/kc:ro${MNTLBL}" \
        --entrypoint kubectl "$IMAGE" --kubeconfig /kc "$@"
}

secure_delete() {
    for f in "$@"; do
        [ -n "$f" ] && [ -f "$f" ] || continue
        if command -v shred >/dev/null 2>&1; then shred -u "$f" 2>/dev/null || rm -f "$f"
        elif command -v gshred >/dev/null 2>&1; then gshred -u "$f" 2>/dev/null || rm -f "$f"
        else rm -f "$f"
        fi
    done
}

mint_execcred() {
    log 'exec credential kubeconfig detected; minting a token on the host ...'
    EXECCMD="$(img_kubectl config view --minify -o jsonpath='{.users[0].user.exec.command}' 2>/dev/null || true)"
    [ -n "${EXECCMD:-}" ] || err 'could not read the exec command from kubeconfig'
    command -v "$EXECCMD" >/dev/null 2>&1 || err "kubeconfig requires '$EXECCMD' on the host"

    set +u
    EXECARGS=()
    set -u
    while IFS= read -r a; do [ -n "$a" ] && EXECARGS[${#EXECARGS[@]}]="$a"; done <<EOF_ARGS
$(img_kubectl config view --minify -o jsonpath='{range .users[0].user.exec.args[*]}{@}{"\n"}{end}' 2>/dev/null || true)
EOF_ARGS

    set +eu
    EC_JSON="$("$EXECCMD" "${EXECARGS[@]}" 2>/dev/null)"
    rc=$?
    set -eu
    [ $rc -eq 0 ] && [ -n "${EC_JSON:-}" ] || err "failed to mint a token with '$EXECCMD'"

    CRED_FILE_HOST="$TMPDIR_RUN/execcred.json"
    ( umask 077; printf '%s' "$EC_JSON" > "$CRED_FILE_HOST" )
    chmod 600 "$CRED_FILE_HOST"
    log 'token minted; raw credential will be parsed inside the container'
}

quote_arg() {
    case "$1" in
        *[!A-Za-z0-9_./:=,@%+-]*) printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\''/g")" ;;
        *) printf '%s' "$1" ;;
    esac
}

print_rerun() {
    case "$1" in
        tfvars) add=' --tfvars <path-to-terraform.tfvars>' ;;
        ansiblevars) add=' --ansiblevars <path-to-ansible-vars.yaml>' ;;
        both) add=' --tfvars <path-to-terraform.tfvars> --ansiblevars <path-to-ansible-vars.yaml>' ;;
    esac

    keep=" --deploypath $(quote_arg "$DEPLOY_SRC") --out $(quote_arg "$OUT_SRC")"
    [ -n "$TFVARS_SRC" ] && keep="$keep --tfvars $(quote_arg "$TFVARS_SRC")"
    [ -n "$ANSIBLE_SRC" ] && keep="$keep --ansiblevars $(quote_arg "$ANSIBLE_SRC")"

    set +u
    pt_str=''
    if [ ${#PT[@]} -gt 0 ]; then
        # No '--' needed: unrecognized options are forwarded automatically.
        i=0
        while [ $i -lt ${#PT[@]} ]; do pt_str="$pt_str $(quote_arg "${PT[$i]}")"; i=$((i+1)); done
    fi
    set -u

    echo >&2
    warn 'get-k8s-info detected deployment asset file(s) that were not provided to the container'
    warn 'To include them, re-run using the long option(s) below:'
    printf '\n    %s run%s%s%s\n\n' "$SELF" "$keep" "$add" "$pt_str" >&2
    warn 'Or run again and choose to skip those files when prompted'
}

prompt_host_paths() {
    host_pwd="$(pwd)"

    if [ "$DEPLOY_GIVEN" != 'true' ]; then
        read -p " -> Specify the path of the viya \$deploy directory ($host_pwd): " DEPLOY_SRC || true
        DEPLOY_SRC="${DEPLOY_SRC/#\~/$HOME}"
        [ -n "$DEPLOY_SRC" ] || DEPLOY_SRC="$host_pwd"
        DEPLOY_GIVEN='true'
    fi

    if [ "$OUT_GIVEN" != 'true' ]; then
        read -p " -> Specify the path where the script output file will be saved ($host_pwd): " OUT_SRC || true
        OUT_SRC="${OUT_SRC/#\~/$HOME}"
        [ -n "$OUT_SRC" ] || OUT_SRC="$host_pwd"
        OUT_GIVEN='true'
    fi
}

reject_owned_pass_through() {
    set +u
    i=0
    while [ $i -lt ${#PT[@]} ]; do
        case "${PT[$i]}" in
            -p|--deploypath|-o|--out|-i|--tfvars|-a|--ansiblevars)
                err "do not pass '${PT[$i]}' after '--'; pass it to gki-container.sh instead"
                ;;
        esac
        i=$((i+1))
    done
    set -u
}

do_run() {
    reject_owned_pass_through
    prompt_host_paths

    case "$DEPLOY_SRC" in
        [Uu][Nn][Aa][Vv][Aa][Ii][Ll][Aa][Bb][Ll][Ee]) DEPLOY_IS_UNAVAILABLE='true' ;;
        *) DEPLOY_IS_UNAVAILABLE='false'
           [ -d "$DEPLOY_SRC" ] || err "deployment path is not a directory: $DEPLOY_SRC (or specify 'unavailable')"
           DEPLOY_SRC="$(cd "$DEPLOY_SRC" && pwd)" ;;
    esac
    case "$TFVARS_SRC" in
        [Uu][Nn][Aa][Vv][Aa][Ii][Ll][Aa][Bb][Ll][Ee]) TFVARS_IS_UNAVAILABLE='true' ;;
        *) TFVARS_IS_UNAVAILABLE='false'
           [ -z "$TFVARS_SRC" ] || [ -f "$TFVARS_SRC" ] || err "tfvars file not found: $TFVARS_SRC"
           [ -z "$TFVARS_SRC" ] || TFVARS_SRC="$(cd "$(dirname "$TFVARS_SRC")" && pwd)/$(basename "$TFVARS_SRC")"
    esac
    case "$ANSIBLE_SRC" in
        [Uu][Nn][Aa][Vv][Aa][Ii][Ll][Aa][Bb][Ll][Ee]) ANSIBLE_IS_UNAVAILABLE='true' ;;
        *) ANSIBLE_IS_UNAVAILABLE='false'
           [ -z "$ANSIBLE_SRC" ] || [ -f "$ANSIBLE_SRC" ] || err "ansible-vars file not found: $ANSIBLE_SRC"
           [ -z "$ANSIBLE_SRC" ] || ANSIBLE_SRC="$(cd "$(dirname "$ANSIBLE_SRC")" && pwd)/$(basename "$ANSIBLE_SRC")"
    esac

    [ -d "$OUT_SRC" ] || err "output path does not exist: $OUT_SRC"
    OUT_SRC="$(cd "$OUT_SRC" && pwd)"

    ensure_image
    MNTLBL=''
    [ "$ENGINE" = 'podman' ] && MNTLBL=':Z'

    [ -f "$KUBECONFIG_SRC" ] || err "kubeconfig not found: $KUBECONFIG_SRC"
    KUBECONFIG_SRC="$(cd "$(dirname "$KUBECONFIG_SRC")" && pwd)/$(basename "$KUBECONFIG_SRC")"

    TMPDIR_RUN="$(mktemp -d "${TMPDIR:-/tmp}/gki-run.XXXXXX")"
    chmod 700 "$TMPDIR_RUN" 2>/dev/null || true
    CRED_FILE_HOST=''
    # Single quotes defer expansion until the trap fires. CRED_FILE_HOST is
    # assigned later by mint_execcred, so deferred expansion is required to
    # shred the actual credential file rather than its current empty value.
    trap 'printf "\033[?25h"; secure_delete "$CRED_FILE_HOST"; rm -rf "$TMPDIR_RUN" 2>/dev/null' EXIT INT TERM HUP

    if grep -q 'exec:' "$KUBECONFIG_SRC" 2>/dev/null; then
        ec="$(img_kubectl config view --minify -o jsonpath='{.users[0].user.exec.command}' 2>/dev/null || true)"
        [ -n "$ec" ] && mint_execcred
    fi

    BASE="$("$ENGINE" image inspect --format '{{ index .Config.Labels "gki.base.image" }}' "$IMAGE" 2>/dev/null || true)"

    set +u
    RUN_ARGS=()
    APP_ARGS=()
    set -u

    RUN_ARGS[${#RUN_ARGS[@]}]='run'
    RUN_ARGS[${#RUN_ARGS[@]}]='--rm'
    if [ -t 0 ]; then RUN_ARGS[${#RUN_ARGS[@]}]='-it'; else RUN_ARGS[${#RUN_ARGS[@]}]='-i'; fi
    RUN_ARGS[${#RUN_ARGS[@]}]='--user'; RUN_ARGS[${#RUN_ARGS[@]}]="$(id -u):$(id -g)"
    RUN_ARGS[${#RUN_ARGS[@]}]='-e'; RUN_ARGS[${#RUN_ARGS[@]}]='GKI_CONTAINER=1'
    RUN_ARGS[${#RUN_ARGS[@]}]='-e'; RUN_ARGS[${#RUN_ARGS[@]}]="GKI_CONTAINER_VERSION=$LAUNCHER_VERSION"
    RUN_ARGS[${#RUN_ARGS[@]}]='-e'; RUN_ARGS[${#RUN_ARGS[@]}]="GKI_BASE_IMAGE=$BASE"
    RUN_ARGS[${#RUN_ARGS[@]}]='-e'; RUN_ARGS[${#RUN_ARGS[@]}]="GKI_CAPS=$GKI_CAPS"
    RUN_ARGS[${#RUN_ARGS[@]}]='-e'; RUN_ARGS[${#RUN_ARGS[@]}]="GKI_OUT_HOST_PATH=$OUT_SRC"
    RUN_ARGS[${#RUN_ARGS[@]}]='-e'; RUN_ARGS[${#RUN_ARGS[@]}]='KUBECONFIG=/home/sas/.kube/config'
    RUN_ARGS[${#RUN_ARGS[@]}]='-v'; RUN_ARGS[${#RUN_ARGS[@]}]="$KUBECONFIG_SRC:/home/sas/.kube/config:ro${MNTLBL}"
    RUN_ARGS[${#RUN_ARGS[@]}]='-v'; RUN_ARGS[${#RUN_ARGS[@]}]="$OUT_SRC:$CPATH_OUT${MNTLBL}"
    RUN_ARGS[${#RUN_ARGS[@]}]='-w'; RUN_ARGS[${#RUN_ARGS[@]}]="$CPATH_OUT"

    if [ -n "$CRED_FILE_HOST" ]; then
        RUN_ARGS[${#RUN_ARGS[@]}]='-v'; RUN_ARGS[${#RUN_ARGS[@]}]="$CRED_FILE_HOST:/home/sas/.gki/execcred.json:ro${MNTLBL}"
    fi
    if [ "$DEPLOY_IS_UNAVAILABLE" != 'true' ]; then
        RUN_ARGS[${#RUN_ARGS[@]}]='-e'; RUN_ARGS[${#RUN_ARGS[@]}]="GKI_DEPLOY_HOST_PATH=$DEPLOY_SRC"
        RUN_ARGS[${#RUN_ARGS[@]}]='-v'; RUN_ARGS[${#RUN_ARGS[@]}]="$DEPLOY_SRC:$CPATH_DEPLOY:ro${MNTLBL}"
    fi
    if [ -n "$TFVARS_SRC" ] && [ "$TFVARS_IS_UNAVAILABLE" != 'true' ]; then
        RUN_ARGS[${#RUN_ARGS[@]}]='-e'; RUN_ARGS[${#RUN_ARGS[@]}]="GKI_TFVARS_HOST_PATH=$TFVARS_SRC"
        RUN_ARGS[${#RUN_ARGS[@]}]='-v'; RUN_ARGS[${#RUN_ARGS[@]}]="$TFVARS_SRC:$CPATH_TFVARS:ro${MNTLBL}"
    fi
    if [ -n "$ANSIBLE_SRC" ] && [ "$ANSIBLE_IS_UNAVAILABLE" != 'true' ]; then
        RUN_ARGS[${#RUN_ARGS[@]}]='-e'; RUN_ARGS[${#RUN_ARGS[@]}]="GKI_ANSIBLE_HOST_PATH=$ANSIBLE_SRC"
        RUN_ARGS[${#RUN_ARGS[@]}]='-v'; RUN_ARGS[${#RUN_ARGS[@]}]="$ANSIBLE_SRC:$CPATH_ANSIBLE:ro${MNTLBL}"
    fi
    RUN_ARGS[${#RUN_ARGS[@]}]="$IMAGE"

    APP_ARGS[${#APP_ARGS[@]}]='--deploypath'
    if [ "$DEPLOY_IS_UNAVAILABLE" = 'true' ]; then APP_ARGS[${#APP_ARGS[@]}]='unavailable'
    else APP_ARGS[${#APP_ARGS[@]}]="$CPATH_DEPLOY"
    fi
    APP_ARGS[${#APP_ARGS[@]}]='--out'; APP_ARGS[${#APP_ARGS[@]}]="$CPATH_OUT"
    
    if [ -n "$TFVARS_SRC" ]; then
        APP_ARGS[${#APP_ARGS[@]}]='--tfvars'
        if [ "$TFVARS_IS_UNAVAILABLE" = 'true' ]; then APP_ARGS[${#APP_ARGS[@]}]='unavailable'
        else APP_ARGS[${#APP_ARGS[@]}]="$CPATH_TFVARS"
        fi
    fi

    if [ -n "$ANSIBLE_SRC" ]; then
        APP_ARGS[${#APP_ARGS[@]}]='--ansiblevars'
        if [ "$ANSIBLE_IS_UNAVAILABLE" = 'true' ]; then APP_ARGS[${#APP_ARGS[@]}]='unavailable'
        else APP_ARGS[${#APP_ARGS[@]}]="$CPATH_ANSIBLE"
        fi
    fi

    set +u
    i=0
    have_no_update='false'
    while [ $i -lt ${#PT[@]} ]; do
        APP_ARGS[${#APP_ARGS[@]}]="${PT[$i]}"
        case "${PT[$i]}" in -u|--no-update) have_no_update='true' ;; esac
        i=$((i+1))
    done
    set -u
    [ "$have_no_update" = 'true' ] || APP_ARGS[${#APP_ARGS[@]}]='--no-update'

    echo
    log "image         = $IMAGE"
    log "kubeconfig    = $KUBECONFIG_SRC -> /home/sas/.kube/config (ro)"
    [ -n "$CRED_FILE_HOST" ] && log 'auth          = exec token minted on host; parsed in container'
    if [ "$DEPLOY_IS_UNAVAILABLE" = 'true' ]; then log 'deploy path   = unavailable'
    else log "deploy path   = $DEPLOY_SRC -> $CPATH_DEPLOY (ro)"
    fi
    if [ -n "$TFVARS_SRC" ]; then
        if [ "$TFVARS_IS_UNAVAILABLE" = 'true' ]; then log 'tfvars        = unavailable'
        else log "tfvars        = $TFVARS_SRC -> $CPATH_TFVARS (ro)"
        fi
    fi
    
    if [ -n "$ANSIBLE_SRC" ]; then
        if [ "$ANSIBLE_IS_UNAVAILABLE" = 'true' ]; then log 'ansiblevars   = unavailable'
        else log "ansiblevars   = $ANSIBLE_SRC -> $CPATH_ANSIBLE (ro)"
        fi
    fi
    log "output path   = $OUT_SRC -> $CPATH_OUT"

    set +u; log "script args   = ${APP_ARGS[*]}"; set -u
    echo

    set +e
    "$ENGINE" "${RUN_ARGS[@]}" "${APP_ARGS[@]}"
    run_rc=$?
    set -e

    case "$run_rc" in
        3) print_rerun tfvars ;;
        4) print_rerun ansiblevars ;;
        5) print_rerun both ;;
        0) log "Container executed successfully!" ;;
        *) warn "get-k8s-info.sh exited with status $run_rc" ;;
    esac
    tput cnorm 2>/dev/null || printf '\e[?25h'
    return "$run_rc"
}

case "$SUBCMD" in
    build) do_build ;;
    run) do_run ;;
esac
