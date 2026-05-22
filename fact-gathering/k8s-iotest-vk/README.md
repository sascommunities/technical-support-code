# K8S I/O Test

A Bash script to manage Kubernetes resources for performing IO tests against nodes in a Viya 4 environment.

## 📦 Overview

This script automates the setup, execution, and teardown of IO tests in Kubernetes clusters. It supports building and pushing container images, configuring test environments, running tests, and retrieving results.

## 🛠️ Features

- Build and push `k8s-iotest` container images to private container registries
- Create and remove Kubernetes resources for IO testing
- Run IO tests across multiple compute or cas nodes
- Retrieve and display test results
- Support for various volume types (e.g., `hostPath`, `PVC`, `NFS`, `ephemeral`, `emptyDir`)

## ✅ Prerequisites

Before using this script, ensure the following tools and environment are set up:

- **Kubernetes Cluster** with nodes labeled for Viya workloads  
  The script targets nodes labeled with:

  ```yaml
  workload.sas.com/class={{ WORKLOAD }}
  ```

  The value of {{ WORKLOAD }} is determined by the -w or --workload option.
 
  This label is used by Viya to identify the nodes, and the script relies on it to schedule IO test pods appropriately. Make sure your cluster nodes are correctly labeled before running `setup` or `run`.

- **kubectl** installed and configured to access the cluster
- **Docker** or compatible container engine
- Access to a **container registry** (e.g., Docker Hub, Azure Container Registry)
- Permissions to create resources in the target namespace

### 📌 Note on Default Container Image

If you run the `setup` command **without specifying** a value for the `--containerimageurl` option, the script will use a **public image** hosted on the author's personal GitHub Container Registry:

```text
ghcr.io/sbralg/k8s-iotest:latest
```

> ⚠️ **Security Warning**  
> This default image is publicly accessible and maintained by the script author. While it is intended for convenience, using a public image in production or sensitive environments may pose security risks.  
> It is strongly recommended to build and push your own image using `docker` or the `push` command, and then explicitly provide its container address to the tool via the `--containerimageurl` option.

### 🧭 Namespace Recommendation

The `k8s-iotest-manager.sh` script can be run in any namespace, but choosing the **right namespace** depends on what you're testing:

- If you're testing a **Persistent Volume Claim (PVC) that exists in the Viya namespace**, you **must deploy `k8s-iotest` in the same namespace** to ensure proper access to the PVC.
  
  > ⚠️ Running the test in a different namespace will prevent access to PVCs scoped to Viya.

- If you're **not testing a Viya PVC**, it is **strongly recommended** to create and use a **dedicated Kubernetes namespace** for running the script.

  > ✅ This helps ensure that the script does **not interfere with existing Viya resources**, especially those in the official Viya namespace.

For example:

```bash
kubectl create namespace k8s-iotest
./k8s-iotest-manager.sh setup --namespace k8s-iotest --volume 'emptyDir: {}'
```

Using a separate namespace provides a clean environment for testing and simplifies cleanup with the `remove` command. It also avoids accidental modifications to production workloads.

## 📋 Usage

```bash
./k8s-iotest-manager.sh [command] [options]
```

### Available Commands

| Command   | Description                                                  |
|-----------|--------------------------------------------------------------|
| `push`    | Build and push the container image to a registry             |
| `setup`   | Create Kubernetes resources for IO testing                   |
| `run`     | Execute IO tests                                             |
| `report`  | Display results from the last IO test                        |
| `remove`  | Delete all IO test resources                                 |
| `show`    | Show current configuration and resource status               |
| `version` | Display script version                                       |

### Options

- `-n`, `--namespace` (Required): Target Kubernetes namespace
- `-v`, `--volume` (Required for `setup`): YAML definition of the volume
- `-w`, `--workload` (Required for `setup`): Selects the node group to target, using the workload.sas.com/class=<value> label.  
  Valid values are `compute`, `cas`, `cascontroller`, and `casworker`.
- `-i`, `--containerimageurl`: Container image URL
- `-u`, `--cruser`: Container registry username
- `-p`, `--crpass`: Container registry password
- `-s`, `--imagepullsecret`: Pre-existing imagePullSecret name
- `-N`, `--nodes`: Number of nodes to run the test  
  If not specified, the script will **create and run a `k8s-iotest` pod in each node labeled with**:

  ```yaml
  workload.sas.com/class={{ WORKLOAD }}
  ```
- `-c`, `--custom-args`: Arguments for legacy `iotest.sh` script
- `-r`, `--wait`: Wait for test completion and show results
- `-d`, `--debug`: Enables debug messages  
- `-h`, `--help`, `--usage`: Show usage information

### Volume YAML Examples

```bash
--volume 'hostPath: {path: /mnt/work, type: Directory}'
--volume 'persistentVolumeClaim: {claimName: myclaim}'
--volume 'nfs: {server: my.nfs.server, path: /nfspath/work}'
--volume 'ephemeral: {volumeClaimTemplate: {spec: {accessModes: [ "ReadWriteOnce" ], storageClassName: "managed-csi-premium", resources: {requests: {storage: 128Gi}}}}}'
--volume 'emptyDir: {}'
```

## 🚀 Examples

```bash
# Push image and setup resources in one step by including --volume
./k8s-iotest-manager.sh push --containerimageurl my.cr.io/myuser/k8s-iotest:latest --cruser mycruser --crpass mycrpass --volume 'nfs: {server: myserver, path: /nfs/export}'

# Setup resources
./k8s-iotest-manager.sh setup --namespace k8s-iotest --workload compute --volume 'hostPath: {path: /mnt/work, type: Directory}'

# Run test and wait for results
./k8s-iotest-manager.sh run --namespace k8s-iotest --wait

# Run test on specific number of nodes
./k8s-iotest-manager.sh run --namespace k8s-iotest --nodes 2

# Run test using legacy script
./k8s-iotest-manager.sh run --namespace k8s-iotest --custom-args '-i 3 -s 64 -b 10240'
```

## 🔄 Workflow Diagram

```text
+---------------------+
|  User Executes CLI  |
+---------+-----------+
          |
          v
+---------------------+
|  Build & Push Image |
| (push command)      |
+---------+-----------+
          |
          v
+---------------------+
|  Create Resources   |
| (setup command)     |
+---------+-----------+
          |
          v
+---------------------+
|  Run IO Tests       |
| (run command)       |
+---------+-----------+
          |
          v
+---------------------+
|  Collect Results    |
| (report command)    |
+---------+-----------+
          |
          v
+---------------------+
|  Cleanup Resources  |
| (remove command)    |
+---------------------+
```

## 🧯 Troubleshooting

- **Image pull errors**: Ensure the container image URL is correct and credentials are valid.
- **Permission denied**: Verify that your Kubernetes context has sufficient privileges in the target namespace.
- **Volume mount issues**: Double-check your `--volume` YAML syntax and ensure the backing storage is available.

If pods appear to be hung during an I/O test, consider the following:

- **Slow Storage Performance**: The I/O test may be actively running, and slow storage can cause delays.  
  To verify this, you can `exec` into the pod and run the `top` command to inspect active processes and CPU timings.

  ```bash
  kubectl exec -it <pod-name> -- top
  ```

  Look for processes in a `D` (uninterruptible sleep) state or high `wa` (I/O wait) percentages in the CPU summary.  
  These are indicators that the pod is waiting on disk I/O and the underlying storage may be struggling.

## 📝 Acknowledgments

The I/O test scripts used by this tool were adapted to run in Kubernetes environments. Their original sources are:

- [SAS Support – Tool to test I/O throughput on UNIX platforms](https://sas.service-now.com/csm?id=kb_article_view&sysparm_article=KB0036262)
- [SAS Support – Tool to test I/O throughput for RHEL systems (`rhel_iotest.sh` script)](https://sas.service-now.com/csm?id=kb_article_view&sysparm_article=KB0039548)

## License

SPDX-License-Identifier: Apache-2.0

Copyright © 2026, SAS Institute Inc., Cary, NC, USA. All Rights Reserved.

## 👤 Author

Alexandre Gomes  
Date: May 21, 2026  
[GitHub Repository](https://github.com/sascommunities/technical-support-code/tree/main/fact-gathering/k8s-iotest-vk)