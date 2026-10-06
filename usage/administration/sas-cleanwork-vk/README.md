# SAS Viya Cleanwork Utility

These files were created to facilitate identifing unused paths in the WORK library directory, removing any that do not have an associated pod running.

## Alternatives
- When using preformatted and pre-mounted local storage (such as Azure's Temp disks), [Rancher's local path provisioner](https://github.com/rancher/local-path-provisioner) along with [Generic Ephemeral Volumes](https://kubernetes.io/docs/concepts/storage/ephemeral-volumes/#generic-ephemeral-volumes) can be used, removing the need for a separate cleanwork utility as Kubernetes would remove the volume when the pod ends.
- When using cloud provider managed ephemeral storage solutions, the native provisioning and mounting mechanisms provided by the cloud platform (along with Generic Ephemeral Volumes) could be leveraged instead of this provisioner and the separate cleanwork utility. For example:
  - For Azure SKUs with NVME disks (e.g. L-series SKUs), [Azure Container Storage v2](https://learn.microsoft.com/en-us/azure/storage/container-storage/container-storage-introduction) can provide a provisioner for these local NVME disks.
  - For AWS EKS instance store volumes, the native EC2 instance store provisioning ([EKS CSI](https://docs.aws.amazon.com/eks/latest/userguide/lis-csi.html)) driver can be used.
  - For GCP GKE, when using a [Local SSD](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/persistent-volumes/local-ssd) machine type it will use these for ephemeral storage (emptyDir) by default.

Have a look at [Project-Mountpoint](https://github.com/sassoftware/project-mountpoint) for more.

## Files

There are 7 files provided:
- README.md - This readme file
- sas-cleanwork.sh - This is the script that is run in the sas-cleanwork container.
- sas-cleanwork-configmap.yaml - ConfigMapGenerator definition file to make a ConfigMap using the sas-cleanwork.sh script.
- sas-cleanwork-cronjob.yaml - This resource object creates a cronJob that runs the cleanwork script. Its usage is appropriate if the WORK path is shared among all nodes, or if only a single node is in use.
- sas-cleanwork-cronjob-patch.yaml - When using the CronJob, this patch defines the WORK volume to use, sets the schedule and whether or not the cronjob is suspended, as well as the maximum age of WORK paths in minutes (default 10080).
- sas-cleanwork-ds.yaml - This resource object creates a DaemonSet that runs on each compute node. Its usage is appropraite if the WORK path is local to each node and multiple nodes are present.
- sas-cleanwork-ds-patch.yaml - When using the Daemonset, this patch file allows you to specify the volume for the WORK library and how long the process should sleep between running the cleanup script, as well as the maximum age of WORK paths in minutes (default 10080).

## Usage -- Non-DAC (deployment as code)

### Initial Steps

1. Create a new directory called sas-cleanwork in your site-config. 
2. Copy these files into that directory.
3. In your kustomization.yaml file in your configMapGenerator section, add the following block to create the sas-cleanwork-script configmap:
```
configMapGenerator:
...
- name: sas-cleanwork-script
  files:
  - site-config/sas-cleanwork/sas-cleanwork.sh
```
### CronJob

To add the cronjob resource type, Perform the following stesp:

1. Edit the sas-cleanwork-cronjob-patch.yaml file with your desired WORK volume definition and schedule, and if you want the job to be suspended or not.
2. In your kustomization.yaml file at the end of your transformers section, add a reference to the customization patch file:
```
transformers:
...
- site-config/sas-cleanwork/sas-cleanwork-cronjob-patch.yaml
``` 

3. Add this reference to the end of your kustomization.yaml's resources section:

```
resources:
...
- site-config/sas-cleanwork/sas-cleanwork-cronjob.yaml
```

### DaemonSet

To add the DaemonSet resource type, perform the following steps:

1. Edit the sas-cleanwork-ds-patch.yaml file with your desired WORK volume definition and cycle time.
2. In your kustomization.yaml file at the end of your transformers section, add a reference to the customization patch file:
```
transformers:
...
- site-config/sas-cleanwork/sas-cleanwork-ds-patch.yaml
``` 

3. Add this reference to the end of your kustomization.yaml's resources section:

```
resources:
...
- site-config/sas-cleanwork/sas-cleanwork-ds.yaml
```

## Usage (DAC)

### Initial Steps
1. Create a new directory called sas-cleanwork in your site-config. 
2. Copy the files used by both Cronjob and DaemonSet options into that directory:
- `sas-cleanwork.sh`
- `sas-cleanwork-configmap.yaml`

### Cronjob
To add the cronjob resource type, Perform the following stesp:

1. Copy the cronjob specific files into the site-config/sas-cleanwork directory.
- `sas-cleanwork-cronjob.yaml`
- `sas-cleanwork-cronjob-patch.yaml`
2. Edit the sas-cleanwork-cronjob-patch.yaml file with your desired WORK volume definition and schedule, and if you want the job to be suspended or not.

### DaemonSet

To add the DaemonSet resource type, perform the following steps:

1. Copy the daemonset specific files into the site-config/sas-cleanwork directory.
- `sas-cleanwork-ds.yaml`
- `sas-cleanwork-ds-patch.yaml`
2. Edit the sas-cleanwork-ds-patch.yaml file with your desired WORK volume definition and cycle time.