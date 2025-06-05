# SAS Viya Cleanwork Utility

These files were created to facilitate identifing unused paths in the WORK library directory, removing any that do not have an associated compute pod running.

There are 7 files provided:
- README.md - This readme file
- sas-cleanwork.sh - This is the script that is run in the sas-cleanwork container.
- sas-cleanwork-configmap.yaml - ConfigMapGenerator definition file to make a ConfigMap using the sas-cleanwork.sh script.
- sas-cleanwork-cronjob.yaml - This resource object creates a cronJob that runs the cleanwork script. Its usage is appropriate if the WORK path is shared among all nodes, or if only a single node is in use.
- sas-cleanwork-cronjob-patch.yaml - When using the CronJob, this patch defines the WORK volume to use, sets the schedule and whether or not the cronjob is suspended.
- sas-cleanwork-ds.yaml - This resource object creates a DaemonSet that runs on each compute node. Its usage is appropraite if the WORK path is local to each node and multiple nodes are present.
- sas-cleanwork-ds-patch.yaml - When using the Daemonset, this patch file allows you to specify the volume for the WORK library and how long the process should sleep between running the cleanup script.

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