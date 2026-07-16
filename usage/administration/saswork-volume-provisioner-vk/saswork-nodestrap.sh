#!/usr/bin/env bash

# This script is designed to be run through a daemonset on Compute or CAS nodes
# in Viya to perform the necessary steps to have the SASWORK volume
# provisioned and ready for use.
#
# Edit 06JUN2025 -- Rewrite the script to perform a better check of whether the block device is unused.
# Edit 21APR2026 -- Remove early false-loop + make mount idempotent (mountpoint guard)
# Edit 15JUL2026 -- Persist mount in /etc/fstab and recover formatted-but-unmounted volumes

# The script is passed the following environment variables:
# - mountpath: The path to mount the SASWORK volume on the node. Default is /saswork.
# - subpaths: An array of subpaths to create under the mount path. If provided, the script will create a subdirectory for each subpath.
# - filesystem: The file system to use when formatting the new block device. Default is ext4.
# - blocksize: The block size to use when formatting with ext4. Default is 4096.
# - raiddev: The RAID device to create when striping multiple block devices together. Default is /dev/md0.
# - raidchunk: The chunk size to use when creating the RAID device. Default is 512.

## Customizations
# Mount path for the SASWORK volume on the node. If you change this you must also change the saswork-pv.yaml.
# Note: This should not be set to /mnt/<something> on Azure unless you intend to use the ephemeral disk for SASWORK, as this can break 
# /etc/fstab mount recovery following a restart if /mnt is not available at boot time. The default value is /saswork.
# mountpath=/saswork

# Subpaths: if this volume is being shared among multiple deployments (i.e. DEV and PROD on the same cluster),
# you can provide an array of subpaths so this provisioner will create a subdirectory in the mount path for each subpath.
# subpaths=( "dev" "prod" )

# File system to use when formatting the new block device. Can be ext4 or xfs.
# filesystem=ext4
# When formatting with ext4, which block size to use. The default value is 4096.
# blocksize=4096
# RAID device to create when striping multiple block devices together.
# raiddev=/dev/md0
# Chunk size to use when creating the RAID device. The default value is 512.
# raidchunk=512
## End Customizations

# Set bash options to fail immediately on error, treat unset variables as errors, and fail on pipe errors.
set -o errexit
set -o nounset
set -o pipefail

# Define the path to mount the volume
mountpath=${mountpath:-/saswork}

# Define the file system you'd like to deploy on the volume. Options are ext4 or xfs.
filesystem=${filesystem:-ext4}

# Define a function to check for and install missing packages.
function commandcheck {
    local installcmd
    local package

    if [[ -z "${1:-}" ]]; then
        echo "ERROR: No argument supplied."
        exit 1
    elif command -v "$1" >/dev/null 2>&1; then
        echo "Command $1 is available."
    else
        echo "Command $1 is not available. Attempting to install."

        if command -v apt &>/dev/null; then
            echo "Found Debian apt package installer."
            installcmd=apt
        elif command -v apt-get &>/dev/null; then
            echo "Found Debian apt-get package installer."
            installcmd=apt-get
        elif command -v dnf &>/dev/null; then
            echo "Found RHEL dnf package installer."
            installcmd=dnf
        elif command -v yum &>/dev/null; then
            echo "Found RHEL yum package installer."
            installcmd=yum
        else
            echo "ERROR: Could not determine installation command."
            exit 1
        fi

        if [[ "$1" = "mkfs.ext4" ]]; then
            package=e2fsprogs
        elif [[ "$1" = "mkfs.xfs" ]]; then
            package=xfsprogs
        elif [[ "$1" = "mdadm" ]]; then
            package=mdadm
        else
            echo "ERROR: unexpected command name: $1 - should be mkfs.ext4 or mkfs.xfs or mdadm"
            exit 1
        fi

        "$installcmd" install "$package" -y
    fi
}

function get_mount_options {
    local fs="$1"

    if [[ "$fs" == "ext4" ]]; then
        echo "defaults,noatime,discard"
    elif [[ "$fs" == "xfs" ]]; then
        echo "defaults,discard"
    else
        echo "defaults"
    fi
}

function is_supported_mount_filesystem {
    local fs="$1"

    [[ "$fs" == "ext4" || "$fs" == "xfs" ]]
}

function is_uuid_mounted {
    local uuid="$1"
    local by_uuid_path="/dev/disk/by-uuid/$uuid"
    local resolved_device

    if [[ -e "$by_uuid_path" ]]; then
        resolved_device=$(readlink -f "$by_uuid_path" 2>/dev/null || true)

        if [[ -n "$resolved_device" ]] && findmnt -rn -S "$resolved_device" >/dev/null 2>&1; then
            return 0
        fi

        if findmnt -rn -S "$by_uuid_path" >/dev/null 2>&1; then
            return 0
        fi
    fi

    return 1
}

function ensure_fstab_entry {
    local uuid="$1"
    local mpath="$2"
    local fs="$3"
    local mopts="$4"
    local tmpfile

    if [[ -z "$uuid" || -z "$mpath" || -z "$fs" || -z "$mopts" ]]; then
        echo "ERROR: ensure_fstab_entry requires uuid, mount path, filesystem, and mount options."
        return 1
    fi

    tmpfile=$(mktemp)

    # Keep comments and unrelated lines, but replace any prior entry for this UUID or mount path.
    awk -v uuid="UUID=$uuid" -v mpath="$mpath" '
        /^[[:space:]]*#/ { print; next }
        NF < 2 { print; next }
        $1 == uuid || $2 == mpath { next }
        { print }
    ' /etc/fstab > "$tmpfile"

    printf "UUID=%s %s %s %s 0 2\n" "$uuid" "$mpath" "$fs" "$mopts" >> "$tmpfile"
    cat "$tmpfile" > /etc/fstab
    rm -f "$tmpfile"

    echo "Ensured /etc/fstab entry for UUID=$uuid on $mpath."
}

function ensure_mount_from_uuid {
    local device="$1"
    local uuid
    local devfs
    local mountopts

    uuid=$(blkid -s UUID -o value "$device" 2>/dev/null || true)
    devfs=$(blkid -s TYPE -o value "$device" 2>/dev/null || true)

    if [[ -z "$uuid" || -z "$devfs" ]]; then
        echo "Device $device is missing UUID or filesystem type; cannot mount safely."
        return 1
    fi

    if [[ "$devfs" == "linux_raid_member" ]]; then
        echo "Device $device is a linux_raid_member and is not directly mountable."
        return 1
    fi

    if ! is_supported_mount_filesystem "$devfs"; then
        echo "Device $device has unsupported filesystem $devfs for this script."
        return 1
    fi

    mountopts=$(get_mount_options "$devfs")
    mkdir -p "$mountpath"

    ensure_fstab_entry "$uuid" "$mountpath" "$devfs" "$mountopts"

    if mountpoint -q "$mountpath" 2>/dev/null; then
        echo "$mountpath is already mounted."
    else
        mount "$mountpath"
    fi

    chmod 777 "$mountpath"

    # Subpaths (if provided as array)
    if declare -p subpaths >/dev/null 2>&1; then
        if [[ "$(declare -p subpaths 2>/dev/null)" =~ "declare -a" ]]; then
            for subpath in "${subpaths[@]}"; do
                mkdir -p "$mountpath/$subpath" && chmod 777 "$mountpath/$subpath"
                echo "Created subpath $mountpath/$subpath with permissions 777."
            done
        fi
    fi
}

function get_formatted_unmounted_devices {
    local prefix="$1"
    local devices=()
    local devpath
    local devname
    local device
    local uuid
    local fstype

    for devpath in /sys/block/"${prefix}"*; do
        [[ -e "$devpath" ]] || continue

        devname=${devpath##*/}
        device="/dev/$devname"

        uuid=$(blkid -s UUID -o value "$device" 2>/dev/null || true)
        [[ -n "$uuid" ]] || continue

        fstype=$(blkid -s TYPE -o value "$device" 2>/dev/null || true)
        [[ -n "$fstype" ]] || continue

        # Never attempt to mount member devices from a Linux MD RAID array.
        if [[ "$fstype" == "linux_raid_member" ]]; then
            echo "Skipping RAID member device $device during formatted-device recovery." >&2
            continue
        fi

        # Limit recovery candidates to filesystems this script manages.
        if [[ "$fstype" != "ext4" && "$fstype" != "xfs" ]]; then
            echo "Skipping unsupported formatted device $device with filesystem $fstype." >&2
            continue
        fi

        # Skip any device already mounted somewhere.
        if is_uuid_mounted "$uuid"; then
            continue
        fi

        devices+=("$device")
    done

    echo "${devices[@]}"
}

# Return list of unused block devices of prefix (nvme or sd).
function get_unused_block_devices {
    local prefix="$1"
    local devices=()
    local devpath
    local devname
    local device

    for devpath in /sys/block/"${prefix}"*; do
        [[ -e "$devpath" ]] || continue

        devname=${devpath##*/}
        device="/dev/$devname"

        # Skip if the raw device has a filesystem or partition table
        if blkid "$device" &>/dev/null; then
            echo "Device $device has a filesystem or partition table." >&2
            continue
        fi

        devices+=("$device")
    done

    echo "${devices[@]}"
}

# Setup storage (RAID if multiple, else single disk), format, mount, chmod, subpaths
function setup_storage {
    local devices=("$@")
    local mountopts
    local uuid
    local stride
    local stripe

    if [[ ${#devices[@]} -eq 0 ]]; then
        echo "No unused block devices found."
        return 1
    fi

    raiddev=${raiddev:-/dev/md0}

    # Keep original disk count for stripe-width calculation (only matters if RAID is used)
    local raid_disk_count=${#devices[@]}

    if [[ ${#devices[@]} -gt 1 ]]; then
        raidchunk=${raidchunk:-512}

        echo "Creating RAID array with devices: ${devices[*]}"
        commandcheck mdadm
        mdadm --create --verbose "$raiddev" --level=0 -c "${raidchunk}" --raid-devices=${#devices[@]} "${devices[@]}"

        while mdadm --detail "$raiddev" | grep -qioE 'State :.*resyncing'; do
            echo "Raid is resyncing.."
            sleep 1
        done

        echo "RAID array created at $raiddev."
        devices=("$raiddev")
    fi

    # Format the device(s)
    if [[ "$filesystem" == "ext4" ]]; then
        commandcheck mkfs.ext4
        blocksize=${blocksize:-4096}

        if [[ "${devices[0]}" == "$raiddev" ]]; then
            stride=$(( raidchunk * 1024 / blocksize ))
            stripe=$(( raid_disk_count * stride ))
            mkfs.ext4 -b "$blocksize" -E stride=$stride,stripe-width=$stripe "${devices[0]}"
        else
            mkfs.ext4 -b "$blocksize" "${devices[0]}"
        fi
        mountopts=$(get_mount_options ext4)
    elif [[ "$filesystem" == "xfs" ]]; then
        commandcheck mkfs.xfs
        mkfs.xfs "${devices[0]}"
        mountopts=$(get_mount_options xfs)
    else
        echo "Unsupported filesystem: $filesystem"
        return 1
    fi

    echo "Formatted device ${devices[0]} with filesystem $filesystem."

    uuid=$(blkid -s UUID -o value "${devices[0]}")
    echo "UUID for device ${devices[0]} is $uuid."

    mkdir -p "$mountpath"
    ensure_fstab_entry "$uuid" "$mountpath" "$filesystem" "$mountopts"

    # Mount from fstab entry so restart behavior is consistent with initial setup.
    if mountpoint -q "$mountpath" 2>/dev/null; then
        echo "$mountpath is already mounted. Skipping mount."
    else
        mount "$mountpath"
    fi

    chmod 777 "$mountpath"

    # Subpaths (if provided as array)
    if declare -p subpaths >/dev/null 2>&1; then
        if [[ "$(declare -p subpaths 2>/dev/null)" =~ "declare -a" ]]; then
            for subpath in "${subpaths[@]}"; do
                mkdir -p "$mountpath/$subpath" && chmod 777 "$mountpath/$subpath"
                echo "Created subpath $mountpath/$subpath with permissions 777."
            done
        fi
    fi
}

function main {
    local configured_raiddev
    local raid_uuid
    local formatted_unmounted_md_devices
    local formatted_unmounted_nvme_devices
    local formatted_unmounted_sd_devices
    local unused_nvme_devices
    local unused_sd_devices
    local fallback_root
    local mount_leaf
    local fallback_mount_target

    # If mountpath exists...
    if [[ -d "$mountpath" ]]; then
        echo "Mount path $mountpath already exists."

        # If it is actually mounted, we're done (ensure perms)
        if mountpoint -q "$mountpath" 2>/dev/null; then
            echo "Mount path $mountpath is mounted."
            chmod 777 "$mountpath"
            exit 0
        fi

        # If it's not mounted, continue to discovery and recovery checks.
        echo "Mount path exists but is not mounted. Continuing to device discovery."
    fi

    # Recovery path #1: if the configured RAID device already exists and is formatted,
    # mount it via fstab instead of creating or formatting anything.
    configured_raiddev=${raiddev:-/dev/md0}
    if [[ -b "$configured_raiddev" ]]; then
        raid_uuid=$(blkid -s UUID -o value "$configured_raiddev" 2>/dev/null || true)
        if [[ -n "$raid_uuid" ]] && ! is_uuid_mounted "$raid_uuid"; then
            echo "Found formatted but unmounted RAID device $configured_raiddev. Mounting it."
            ensure_mount_from_uuid "$configured_raiddev"
            exit $?
        fi
    fi

    # Recovery path #2: if there are any formatted md devices, prefer those
    # before probing individual nvme/sd disks.
    formatted_unmounted_md_devices=($(get_formatted_unmounted_devices md))
    if [[ ${#formatted_unmounted_md_devices[@]} -gt 0 ]]; then
        echo "Found formatted but unmounted md device ${formatted_unmounted_md_devices[0]}. Mounting it."
        ensure_mount_from_uuid "${formatted_unmounted_md_devices[0]}"
        exit $?
    fi

    # Recovery path #3: look for pre-formatted but currently unmounted NVMe devices.
    formatted_unmounted_nvme_devices=($(get_formatted_unmounted_devices nvme))
    if [[ ${#formatted_unmounted_nvme_devices[@]} -gt 0 ]]; then
        echo "Found formatted but unmounted NVMe device ${formatted_unmounted_nvme_devices[0]}. Mounting it."
        ensure_mount_from_uuid "${formatted_unmounted_nvme_devices[0]}"
        exit $?
    fi

    # Recovery path #4: look for pre-formatted but currently unmounted sd* devices.
    formatted_unmounted_sd_devices=($(get_formatted_unmounted_devices sd))
    if [[ ${#formatted_unmounted_sd_devices[@]} -gt 0 ]]; then
        echo "Found formatted but unmounted sd device ${formatted_unmounted_sd_devices[0]}. Mounting it."
        ensure_mount_from_uuid "${formatted_unmounted_sd_devices[0]}"
        exit $?
    fi

    # Check NVMe first
    unused_nvme_devices=($(get_unused_block_devices nvme))
    if [[ ${#unused_nvme_devices[@]} -gt 0 ]]; then
        setup_storage "${unused_nvme_devices[@]}"
        exit $?
    fi

    # Then check sd*
    unused_sd_devices=($(get_unused_block_devices sd))
    if [[ ${#unused_sd_devices[@]} -gt 0 ]]; then
        setup_storage "${unused_sd_devices[@]}"
        exit $?
    fi

    # No unused block devices found
    echo "No unused block devices found. Creating mount point $mountpath with permissions 777."

    if [[ -d "/mnt/resource" ]]; then
        fallback_root="/mnt/resource"
    elif [[ -d "/mnt" ]]; then
        fallback_root="/mnt"
    else
        fallback_root=""
    fi

    if [[ -n "$fallback_root" ]]; then
        mount_leaf=${mountpath##*/}
        fallback_mount_target="$fallback_root/$mount_leaf"

        # If mountpath already lives under fallback_root, do not create a self-referential symlink.
        if [[ "$mountpath" == "$fallback_root"/* ]]; then
            mkdir -p "$mountpath" && chmod 777 "$mountpath"
        else
            echo "Found existing path $fallback_root. Using $fallback_mount_target as fallback backing storage."
            mkdir -p "$fallback_mount_target" && chmod 777 "$fallback_mount_target"

            # Ensure mountpath becomes the symlink itself
            if [[ -e "$mountpath" && ! -L "$mountpath" ]]; then
                rmdir "$mountpath" 2>/dev/null || rm -rf "$mountpath"
            fi
            ln -sfn "$fallback_mount_target" "$mountpath"
        fi
    else
        mkdir -p "$mountpath" && chmod 777 "$mountpath"
    fi

    # Subpaths (if provided as array)
    if declare -p subpaths >/dev/null 2>&1; then
        if [[ "$(declare -p subpaths 2>/dev/null)" =~ "declare -a" ]]; then
            for subpath in "${subpaths[@]}"; do
                mkdir -p "$mountpath/$subpath" && chmod 777 "$mountpath/$subpath"
                echo "Created subpath $mountpath/$subpath with permissions 777."
            done
        fi
    fi
}

main
