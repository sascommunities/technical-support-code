# Cloud Disk Provisioner

This project is built to facilitate making use of secondary local storage attached to nodes for use as the WORK library or CAS DISK CACHE.

Cloud providers ofter instance types or SKUs that include one or more attached local storage devices that are ephemeral, or exist only for the life of the instance.

These disks are ideal for use as the WORK or CAS DISK CACHE locations as they are typically highly performant and as separate disks from the OS disk removes the risk of the volume becoming full and causing issues at the node level.

In some cases, these volumes are already mounted on the node, as with Azure's Temp disk, which is pre-mounted to /mnt/ or /mnt/resource when present.

In other cases, these disks must be manually formatted and mounted to be usable.

The script provided here performs the preparation actions necessary to make use of these temporary disks.

The daemonset runs on nodes tagged with the workload.sas.com/class label of compute or cas.

## Functionality

The daemonset runs a script that performs the following actions on each node with the configured labels:

1. Check if the mountpath already exists on the node, and if so whether it is already mounted to a block device and has the correct permissions.
2. Check if there are any unused/unpartitioned NVMe devices. (/sys/block/nvme*)
3. If there is one NVMe device:
- Create an ext4 or xfs file system on the device
- Mount it to the supplied mount path (e.g. /mnt/saswork)
4. If there are multiple NVMe devices:
- Stripe them (RAID 0) to a single device ID (/dev/md0)
- Create an ext4 or xfs file system on the RAID device
- Mount it to the mount path.
5. If there are no NVMe devices:
- Check if there are any unused/unpartitioned SSD devices (/sys/block/sd*)
- If so, perform same actions as 2 and 3 for them.
- If not, check if /mnt/resource exists (sometimes this is where Azure mounts its Temp disk).
- If so, create /mnt/resource/saswork and link to /mnt/saswork
- If not, create /mnt/saswork
- Make /mnt/saswork globally writable

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

```
$ kubectl -n namespace logs saswork-nodestrap-xxxxx -c saswork-nodestrap
+ cp /saswork-nodestrap-script/saswork-nodestrap.sh /node-local-script-dir/
+ /usr/bin/nsenter -m/proc/1/ns/mnt -- chmod u+x /mnt/saswork-nodestrap.sh
+ /usr/bin/nsenter -m/proc/1/ns/mnt /mnt/saswork-nodestrap.sh
Device /dev/sda has a filesystem or partition table.
Device /dev/sdb has a filesystem or partition table.
No unused block devices found. Creating mount point /mnt/saswork with permissions 777.
```