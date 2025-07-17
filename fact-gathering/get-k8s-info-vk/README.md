# get-k8s-info.sh Script 

The get-k8s-info.sh script collects diagnostic and configuration data from various components of a Viya 4 deployment in Kubernetes. This includes:

- Software versions used in the deployment
- Output from kubectl get and kubectl describe for objects in the SAS deployment namespace and related namespaces (e.g., kube-system)
- YAML definition of Kubernetes objects
- Node descriptions and performance metrics (kubectl top)
- Pod logs
- Key-value pairs from Consul
- Deployment assets used to deploy the environment

## User Responsibility for Final Sensitive Data Check

The script scans the collected information for sensitive data and redacts it before packaging the final .tgz file. However, final validation of the contents should be performed manually by the user.

## Prerequisites

- Run the script on the machine or jumpbox used for the original deployment
- Ensure access to deployment files and the Kubernetes cluster via `kubectl`
- Bash Shell

## Usage

**Note**: Some data may be unavailable depending on the permissions granted by the provided `KUBECONFIG`.

### Interactive Mode Example

Run the script without options to enter interactive mode:

```
./get-k8s-info.sh
```

You’ll be prompted to provide:

```
# Case Number:
-> SAS Tech Support case number (leave blank if not known):

# Deployment Assets Directory
-> Specify the path of the viya $deploy directory (<current directory>):

# Output Directory
-> Specify the path where the script output file will be saved (<current directory>):
```

**Note**: Press ENTER to accept the default `<current directory>`

In case the IaC or DaC were used to deploy the environment, the script may also ask for the following:

```
# IaC TFVARS file:
 -> A viya4-iac project was used to create the infrastructure of this environment. Specify the path of the "terraform.tfvars" file that was used (leave blank if not known):

# DaC "ansible-vars.yaml" file:
 -> The viya4-deployment project was used to deploy the environment in the $ns namespace. Specify the path of the "ansible-vars.yaml" file that was used (leave blank if not known):
 ```

### Command-line Mode Example

The following example runs the script providing all required options in the command line, which causes the script to execute without requesting any information:

```
./get-k8s-info.sh --case CS0000000 --deploypath /home/user/viyadeployments/prod --out /tmp 
```

* -c | --case  
    Case number. When not provided, the script uses CS0000000 by default. When --sastsdrive is specified, this option is required.

* -d | --deploypath  
    Path of the directory containing the deployment assets, including the 'site-config' directory and 'kustomization.yaml' file. Deployment asset collection can be supressed by specifying '--deploypath unavailable'.

* -o | --out  
    Path of the directory where the final .tgz file will be created.

### Additional Options

You can specify options to control the script execution or collect additional information.

* -n | --namespace | --namespaces

    Used to specify a namespace or a comma separated list of namespaces from where information should be collected. By default, the script automatically detects namespaces that contains a Viya deployment. 
    
```
./get-k8s-info.sh --namespaces dev,prod,ingressns
```

When a Viya namespace isn't provided and more than one Viya namespace was found, the script will list and ask the user to choose one of the namespaces.

```
Namespaces with a Viya deployment:

[0] dev
[1] prod

 -> Select the namespace where the information should be collected from: 
```

* -d | --disabletags  

    Used to disable specific actions from the script based on a debug tag provided. Available debug tags are:  

    * 'backups': Capture information from backup pvcs and generate reports with status from past backups and restores.  
    * 'config': Dump all key-value pairs currently defined in Consul.
    * 'performance': Collects performance-related data from Kubernetes nodes and designated pods.
    * 'postgres': Collects the 'patronictl list' command output.
    * 'rabbitmq': Collects specific rabbitmq information by running the 'rabbitmqctl report' command on each pod.

**Note**: All debug tags are enabled by default.

```
./get-k8s-info.sh --disabletags 'postgres,config'
```

* -i | --tfvars 

    Used to provide the path for the TFVARS file that was used with the IaC project and include it in the script output file.

* -a | --ansiblevars  

    Used to provide the path for the "ansible-vars.yaml" file that was used with the DaC project and include it in the script output file.

* -w | --workers  

    Used to specify how many workers the script will use to execute 'kubectl' commands in parallel. If not specified, 5 workers are used by default.

* -s | --sastsdrive  

    Used to make the script try to send the final .tgz file to the track SASTSDrive workspace. Only use this option after a TSDrive workspace was already created and the customer authorized by Tech Support to send files to SASTSDrive for the track. It should not be used by customers whose domain have been enabled SSO with SAS, as the authentication won't work. If the script fails to send the .tgz file to SASTSDrive, the customer will still be able to collect the file from the --out directory to send it manually.

* -u | --no-update  

    Used to disable automatic update checks.

### Automatic Debugging and Default Behavior

The script has some built-in debugging steps which are executed automatically:

* Pod Logs: All logs from all pods are collected by default.
* Previous Logs: If a pod has ever been restarted automatically by kubernetes, it will collect the previous logs from that pod automatically.
* Restarting/Unhealthy CAS: If the default CAS controller pod is not available or if it has just recently been started, the script will wait for a while and collect any log that is generated for the default CAS controller pod.
* Time sync information: A report with the current date and time from each k8s node is generated.
* Redaction of Sensitive Data: For files that can contain sensitive data (usually inside deployment assets, consul config dump or YAML object definitions), the script parses those files and redacts certificate, private keys, secrets, passwords and tokens with the string '{{ sensitive data removed }}'.

### Help

The `-h` or `--help` option can be used to view usage information and list all options available for the script.

```
./get-k8s-info.sh --help
```

## Output

Upon completion, the script creates a .tgz file in the specified output directory:

* \<out\>/\<casenumber\>\_\<date\>\_\<time\>.tgz