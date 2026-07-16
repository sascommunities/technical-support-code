# Cloud Disk Provisioner

This project is built to facilitate making use of secondary local storage attached to nodes for use as the WORK library or CAS DISK CACHE.

Cloud providers ofter instance types or SKUs that include one or more attached local storage devices that are ephemeral, or exist only for the life of the instance.

These disks are ideal for use as the WORK or CAS DISK CACHE locations as they are typically highly performant and as separate disks from the OS disk removes the risk of the volume becoming full and causing issues at the node level.

In some cases, these volumes are already mounted on the node, as with Azure's Temp disk, which is pre-mounted to /mnt/ or /mnt/resource when present.

In other cases, these disks must be manually formatted and mounted to be usable.

The script provided here performs the preparation actions necessary to make use of these temporary disks.

The daemonset runs on nodes tagged with the workload.sas.com/class label of compute, cas, cascontroller, or casworker.

## Functionality

The daemonset runs a script that performs the following actions on each node with the configured labels:

1. Check if there are any unused/unpartitioned NVMe devices. (/sys/block/nvme*)
2. Check if there are any unused/unpartitioned SSD devices (/sys/block/sd*)
3. Check if there are any formatted but unmounted NVMe or SSD devices.
4. If there are multiple unused devices, create a RAID 0 array with the devices and mount it to the configured mount path.
5. If there is a single unused device, format it and mount it to the configured mount path.
6. If there is a single formatted but unmounted device (RAID, NVMe, or SSD), mount it to the configured mount path.
7. If there are no unused or unmounted devices, create the mount path directly or as a symlink to /mnt/<mountpath> if /mnt exists (or /mnt/resource/<mountpath> if /mnt/resource exists).

The end result is our defined mountpath is available on the node making use of the instance's temp storage whether it is preformatted and mounted, unformatted and unmounted, or not present at all.

The project consists of 8 files:
- README.md - this readme file
- Files to deploy the daemonset
  - saswork-nodestrap-ds.yaml
  - saswork-ds-target-patch.yaml
  - saswork-nodestrap-configmap.yaml (This file is used instead of the ConfigMapGenerators section in kustomization.yaml when using Deployment as Code)
  - saswork-nodestrap.sh
- Files to create a local storage class, PV and PVC, and patches to make use of the storage provisioned. 
  - local-storage-sc.yaml
  - saswork-pv.yaml
  - saswork-pvc.yaml
  - saswork-volume-patch.yaml
  - change-viya-volume-storage-class.yaml
  - cas-disk-cache-config.yaml

## Implementation

### Step 1. Stage files

1. Create a directory in your $deploy to house the files, in these examples we will use $deploy/site-config/saswork-provisioner.
2. Stage the files in your newly created directory.
2. Edit the patch file saswork-volume-patch with the appropriate destination (compute, cas or both) and the size for the volume and volume claim that matches the size of the space provided by your node SKU.
3. Edit the saswork-ds-target-patch to match your target for your PV.
4. (Optional) Edit the saswork-nodestrap.sh "Customizations" section if you want to use xfs instead of ext4, create subpaths, set alternate node mount path (/mnt/saswork), raid device names (/dev/md0), block or chunk sizes. If you change the node mount path or are using subpaths, you would also need to modify saswork-pv.yaml with the desired path on the host to mount.

### Step 2. Edit kustomization.yaml (Non-DAC)

1. To your resources section, add references to:
 - local-storage-sc.yaml
 - saswork-pv.yaml
 - saswork-pvc.yaml
 - saswork-nodestrap-ds.yaml

```
resources:
...
- site-config/saswork-provisioner/local-storage-sc.yaml
- site-config/saswork-provisioner/saswork-pv.yaml
- site-config/saswork-provisioner/saswork-pvc.yaml
- site-config/saswork-provisioner/saswork-nodestrap-ds.yaml
```

2. To your transformers section, add references to:
 - saswork-ds-target-patch.yaml
 - saswork-volume-patch.yaml
 - change-viya-volume-storage-class.yaml (if using for compute)
 - cas-disk-cache-config.yaml (if using for CAS DISK CACHE)

```
transformers:
...
- site-config/saswork-provisioner/saswork-ds-target-patch.yaml
- site-config/saswork-provisioner/saswork-volume-patch.yaml
- site-config/saswork-provisioner/change-viya-volume-storage-class.yaml
- site-config/saswork-provisioner/cas-disk-cache-config.yaml
```

3. To your configMapGenerators section, add a configMapGenerator for the script the daemonset will run:

```
configMapGenerators:
...
- name: saswork-nodestrap-script
  files:
  - site-config/saswork-provisioner/saswork-nodestrap.sh
```
### Step 3. Build and deploy the assets

This is done using whatever method you chose for initial deployment:
- Manual kubectl commands
- SAS Deployment Operator
- SAS Orchestration command

## Validation

Once applied, you can run kubectl commands to see the operation of the daemonset.

```
$ kubectl -n namespace get po -l app=saswork-nodestrap
NAME                      READY   STATUS    RESTARTS   AGE
saswork-nodestrap-8qjml   1/1     Running   0          2d21h
saswork-nodestrap-fmssw   1/1     Running   0          2d21h
```

You can use the kubectl logs command to see the operation of the script. You must specify the container "saswork-nodestrap" in this command as the script runs in the initContainer of the pod. The main container, pause, performs no actions.

### Example Log Output 
#### Multiple NVMe devices and RAID 0 creation

```
$ kubectl -n namespace logs saswork-nodestrap-xxxxx -c saswork-nodestrap
Creating RAID array with devices: /dev/nvme0n1 /dev/nvme1n1
Command mdadm is available.
mdadm: Defaulting to version 1.2 metadata
mdadm: array /dev/md0 started.
RAID array created at /dev/md0.
Command mkfs.ext4 is available.
mke2fs 1.46.5 (30-Dec-2021)
Discarding device blocks: done                            
Creating filesystem with 937620992 4k blocks and 234405888 inodes
Filesystem UUID: fab40925-3b42-4ac4-9f5e-906510d6c850
Superblock backups stored on blocks: 
        32768, 98304, 163840, 229376, 294912, 819200, 884736, 1605632, 2654208, 
        4096000, 7962624, 11239424, 20480000, 23887872, 71663616, 78675968, 
        102400000, 214990848, 512000000, 550731776, 644972544

Allocating group tables: done                            
Writing inode tables: done                            
Creating journal (262144 blocks): done
Writing superblocks and filesystem accounting information: done       

Formatted device /dev/md0 with filesystem ext4.
UUID for device /dev/md0 is fab40925-3b42-4ac4-9f5e-906510d6c850.
Ensured /etc/fstab entry for UUID=fab40925-3b42-4ac4-9f5e-906510d6c850 on /saswork.
```

#### Single NVMe device

```
$ kubectl -n namespace logs saswork-nodestrap-xxxxx -c saswork-nodestrap
Command mkfs.ext4 is available.
mke2fs 1.46.5 (30-Dec-2021)
Discarding device blocks: done                            
Creating filesystem with 468843606 4k blocks and 117211136 inodes
Filesystem UUID: 2828d0ad-3d76-480a-9ad1-21e84ce7c21d
Superblock backups stored on blocks: 
        32768, 98304, 163840, 229376, 294912, 819200, 884736, 1605632, 2654208, 
        4096000, 7962624, 11239424, 20480000, 23887872, 71663616, 78675968, 
        102400000, 214990848

Allocating group tables: done                            
Writing inode tables: done                            
Creating journal (262144 blocks): done
Writing superblocks and filesystem accounting information: done       

Formatted device /dev/nvme0n1 with filesystem ext4.
UUID for device /dev/nvme0n1 is 2828d0ad-3d76-480a-9ad1-21e84ce7c21d.
Ensured /etc/fstab entry for UUID=2828d0ad-3d76-480a-9ad1-21e84ce7c21d on /saswork.
```

#### No unmounted NVMe or SSD devices

```
Device /dev/nvme0n1 has a filesystem or partition table.
No unused block devices found. Creating mount point /saswork with permissions 777.
Found existing path /mnt. Using /mnt/saswork as fallback backing storage.
```