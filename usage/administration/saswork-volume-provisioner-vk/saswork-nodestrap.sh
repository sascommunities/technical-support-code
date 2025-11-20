#!/usr/bin/env bash

# This script is designed to be run through a daemonset on Compute or CAS nodes
# in Viya to perform the necessary steps to have the SASWORK volume
# provisioned and ready for use. 

# Edit 06JUN2025 -- Rewrite the script to perform a better check of whether the block device is unused.

# The script is passed the following environment variables:
# - mountpath: The path to mount the SASWORK volume on the node. Default is /mnt/saswork.
# - subpaths: An array of subpaths to create under the mount path. If provided, the script will create a subdirectory for each subpath.
# - filesystem: The file system to use when formatting the new block device. Default is ext4.
# - blocksize: The block size to use when formatting with ext4. Default is 4096.
# - raiddev: The RAID device to create when striping multiple block devices together. Default is /dev/md0.
# - raidchunk: The chunk size to use when creating the RAID device. Default is 512.

## Customizations
# Mount path for the SASWORK volume on the node. If you change this you must also change the saswork-pv.yaml.
# Note that this must begin with /mnt when using an Azure SKU provided Temp disk, as these come pre-mounted to /mnt.
# mountpath=/mnt/saswork

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

# The script performs the following actions:
# - Check if the mount path already exists and has the correct permissions and see if it is mounted directly to a block device, as would occur if the script was already run.
# - If the mount path exists:
# - - If the mount path is mounted to a block device (e.g. /dev/md0 or /dev/nvme0n1), it assumes the volume is already provisioned and exits.
# - - If the mount path is not mounted to a block device, it will perform its normal checks as if the mount path was not found to see if this path was not created by this script.
# - - If the checks determine that the mount path should not be mounted to a block device, it will correct the permissions to 777 and exit.
# - If the mount path does not exist:
# - - It will check for unused NVMe block devices
# - - - If it finds one, it will:
# - - - - format the device with the specified file system
# - - - - create the mount path
# - - - - mount the device to the mount path
# - - - - set the permissions of the mount path to 777
# - - - If it finds multiple unused NVMe block devices, it will:
# - - - - create a RAID device of the unused NVMe block devices
# - - - - format the RAID device with the specified file system
# - - - - create the mount path
# - - - - mount the RAID device to the mount path
# - - - - set the permissions of the mount path to 777
# - - If it does not find any unused NVMe block devices, it will check for unused non-NVMe block devices.
# - - - If it finds one, it will:
# - - - - format the device with the specified file system
# - - - - create the mount path
# - - - - mount the device to the mount path
# - - - - set the permissions of the mount path to 777
# - - - If it finds multiple unused non-NVMe block devices, it will:
# - - - - create a RAID device of the unused non-NVMe block devices
# - - - - format the RAID device with the specified file system
# - - - - create the mount path
# - - - - mount the RAID device to the mount path
# - - - - set the permissions of the mount path to 777
# - - If it does not find any unused block devices, it will create the mount path directory and set the permissions to 777.

# This script is being developed based on aks-nvme-ssd-provisioner.sh from 
# https://github.com/ams0/aks-nvme-ssd-provisioner

## Begin script execution ##

# Set bash options:
# Any command with a non-zero exit code to cause the script to fail.
set -o errexit
# Any reference to an undefined variable causes the script to fail.
set -o nounset
# Any command in a pipe that returns non-zero causes that pipeline to return the same non-zero
# triggering script failure from errexit.
set -o pipefail

# Define the path to mount the volume
mountpath=${mountpath:-/mnt/saswork}

# Define the file system you'd like to deploy on the volume. Options are ext4 or xfs.
filesystem=${filesystem:-ext4}

# Operational function definitions

# Define a function to check for and install missing packages.
function commandcheck {
    # Check if we've been passed an argument.
    if [[ -z "$1" ]]; then
        echo "ERROR: No argument supplied."
        exit 1
    # Check if that argument is a command already available.
    elif command -v "$1" &>/dev/null; then
        echo "Command $1 is available."
    else
    # If not, try to install the command.
        echo "Command $1 is not available. Attempting to install."
        # Figure out if our host OS uses apt (Debian) or yum (RHEL)
        if command -v apt &> /dev/null; then
            echo "Found Debian apt package installer."
            installcmd=apt
        elif command -v apt-get &> /dev/null; then
            echo "Found Debian apt-get package installer."
            installcmd=apt-get
        elif command -v dnf &> /dev/null; then
            echo "Found RHEL dnf package installer."
            installcmd=dnf
        elif command -v yum &> /dev/null; then
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
            echo "ERROR: unexpected command name: $1 - should be mkfs.xfs, mkfs.ext4 or mdadm"
        fi
        $installcmd install "$package" -y
    fi
}

# Define a function to return a list of unused block devices of the specified prefix (nvme or sd).
# The function will return a list of block devices that are not mounted and not in use.

function get_unused_block_devices {
    local prefix="$1"
    local devices=()
    
    # Check for block devices matching the prefix
    for devpath in /sys/block/"${prefix}"*; do

        [[ -e "$devpath" ]] || continue  # Skip if the path does not exist (glob expansion failure)

        devname=${devpath##*/}  # Extract the device name from the path
        device="/dev/$devname"

        # Skip if the raw device has a filesystem or partition table
        if blkid "$device" &> /dev/null; then
        # Write the next output to stderr so it doesn't interfere with the function's output.
            echo "Device $device has a filesystem or partition table." >&2
            continue
        fi

        # If we reach here, the device is unused
        devices+=("$device")

    done

    echo "${devices[@]}"  # Return the list of unused devices
}

# Define a function to set up the storage either by raiding multiple devices and formatting the raid device or formatting a single device.
function setup_storage {
    local devices=("$@")

    if [[ ${#devices[@]} -eq 0 ]]; then
        echo "No unused block devices found."
        return 1
    fi

    # Define the RAID device to create when striping multiple block devices together.
    raiddev=${raiddev:-/dev/md0}

    if [[ ${#devices[@]} -gt 1 ]]; then
        # More than one device, create a RAID array

        # Define the chunk size to use when creating the RAID device. Default is 512.
        raidchunk=${raidchunk:-512}

        echo "Creating RAID array with devices: ${devices[*]}"
        commandcheck mdadm
        mdadm --create --verbose "$raiddev" --level=0 -c "${raidchunk}" --raid-devices=${#devices[@]} "${devices[@]}"

        while  mdadm --detail "$raiddev" | grep -qioE 'State :.*resyncing' ; do
            echo "Raid is resyncing.."
            sleep 1
        done
        
        echo "RAID array created at $raiddev."
        devices=("$raiddev")  # Use the RAID device for further processing
    fi

    # Format the device(s)
    if [[ "$filesystem" == "ext4" ]]; then
        commandcheck mkfs.ext4
        # Set the block size to use when formatting with ext4. Default is 4096.
        blocksize=${blocksize:-4096}
        
        # If we are using RAID (devices array = raiddev), we need to calculate stride and stripe width.
        if [[ "${devices[0]}" == "$raiddev" ]]; then
            stride=$(( raidchunk * 1024 / blocksize ))
            stripe=$(( ${#devices[@]} * stride ))
            mkfs.ext4 -b "$blocksize" -E stride=$stride,stripe-width=$stripe "${devices[0]}"
        else
            # If we are not using RAID, just format the single device.
            mkfs.ext4 -b "$blocksize" "${devices[0]}"
        fi
        mountopts="defaults,noatime,discard,nobarrier"
    elif [[ "$filesystem" == "xfs" ]]; then
        commandcheck mkfs.xfs
        mkfs.xfs "${devices[0]}"
        mountopts="defaults,discard"
    else
        echo "Unsupported filesystem: $filesystem"
        return 1
    fi

    # Now devices[0] contains the device to mount, either the RAID device or a single device.
    echo "Formatted device ${devices[0]} with filesystem $filesystem."

    # Get the UUID for the device
    uuid=$(blkid -s UUID -o value "${devices[0]}")
    echo "UUID for device ${devices[0]} is $uuid."
    # Create the mount point, mount the device, and set permissions
    mkdir -p "$mountpath" && mount -o ${mountopts} --uuid "$uuid" "$mountpath" && chmod 777 "$mountpath"
    # Add the mount to /etc/fstab to make it persistent
    echo "UUID=$uuid $mountpath $filesystem ${mountopts} 0 2" >> /etc/fstab
    echo "Mounted device ${devices[0]} to $mountpath with permissions 777."

    # If subpaths are provided, create them under the mount path
    if [[ -n "${subpaths:-}" ]]; then
        for subpath in "${subpaths[@]}"; do
            mkdir -p "$mountpath/$subpath" && chmod 777 "$mountpath/$subpath"
            echo "Created subpath $mountpath/$subpath with permissions 777."
        done
    fi
}

# Define the main function to orchestrate the script execution.
function main {
    # If the mount path already exists...
    if [[ -d "$mountpath" ]]; then
        echo "Mount path $mountpath already exists."
        # Check if the mountpath is the direct mount point.
        if mount | grep -qE "on $mountpath type .*"; then

            # If it is mounted to a block device, assume the volume is already provisioned.
            echo "Mount path $mountpath is already mounted directly to a device."
            # Check if the mount point has the correct permissions
            if [[ $(stat -c "%a" "$mountpath") -eq 777 ]]; then
                echo "Mount path $mountpath has correct permissions (777). Exiting."
                exit 0
            else
                echo "Mount path $mountpath does not have correct permissions but is mounted to a block device."
                echo "Correcting permissions to 777."
                chmod 777 "$mountpath"
                exit 0
            fi
        else
            # If it is not mounted to a block device, we need to check if we have any unused block devices.
            # If we do, we should remove the existing mount path and then let setup_storage recreate it
            # If not, we should just confirm the permissions are correct and exit.
            echo "Mount path $mountpath exists but is not mounted to a block device."

            # Check if we have any unused block devices that should be mounted here.
            unused_nvme_devices=($(get_unused_block_devices nvme))
            unused_sd_devices=($(get_unused_block_devices sd))

            # If we found any, let the rest of the script handle the setup as if we hadn't found the mount path.
            if [[ ${#unused_nvme_devices[@]} -gt 0 || ${#unused_sd_devices[@]} -gt 0 ]]; then
                echo "Unused block devices found. Proceeding to set up storage."
            # If we don't find any unused block devices, just confirm our permissions are 777.
            elif [[ $(stat -c "%a" "$mountpath") -eq 777 ]]; then
                echo "No unused block devices to prepare. Mount path $mountpath has correct permissions (777). Exiting."
                exit 0
            # If the permissions are not correct, we need to correct them.
            else
                echo "Mount path $mountpath exists but does not have correct permissions. Setting permissions to 777."
                chmod 777 "$mountpath"
                exit 0
            fi
        fi
    fi

    # Check for unused NVMe block devices first
    unused_nvme_devices=($(get_unused_block_devices nvme))
    if [[ ${#unused_nvme_devices[@]} -gt 0 ]]; then
        setup_storage "${unused_nvme_devices[@]}"
        exit $?
    fi

    # If no unused NVMe devices, check for unused non-NVMe block devices
    unused_sd_devices=($(get_unused_block_devices sd))
    if [[ ${#unused_sd_devices[@]} -gt 0 ]]; then
        setup_storage "${unused_sd_devices[@]}"
        exit $?
    fi

    # If we reach here, no unused block devices were found.
    echo "No unused block devices found. Creating mount point $mountpath with permissions 777."

    # We need to check if /mnt/resource exists. If it does, we should create a subdirectory there and then link it to the mount path.
    if [[ -d "/mnt/resource" ]]; then
        echo "Found existing path /mnt/resource. Assuming this is the temp drive's mount point."
        echo "Creating directory $mountpath."
        mkdir -p "$mountpath"
        echo "Creating directory /mnt/resource/saswork, setting permissions to 777 and creating a link from this to $mountpath"
        mkdir -p /mnt/resource/saswork && chmod 777 /mnt/resource/saswork && ln -s /mnt/resource/saswork "$mountpath"
        exit 0
    else
    mkdir -p "$mountpath" && chmod 777 "$mountpath"
    fi

    # If subpaths are provided, create them under the mount path
    if [[ -n "${subpaths:-}" ]]; then
        for subpath in "${subpaths[@]}"; do
            mkdir -p "$mountpath/$subpath" && chmod 777 "$mountpath/$subpath"
            echo "Created subpath $mountpath/$subpath with permissions 777."
        done
    fi
}
# Call the main function to start the script execution.
main 
