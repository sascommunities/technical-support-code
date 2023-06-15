# get-k8s-info.sh Script

The get-k8s-info.sh script collects information from a SAS software deployment in a Kubernetes cluster. The information collected 
may include, depending on the options specified, versions from softwares in use by the deployment, list and describe output from objects 
created in the SAS deployment namespace as well as in the kube-system and ingress controller namespaces, YAML definition from some objects when applicable, 
describe and top output from nodes in the cluster, logs from pods and key-value pairs from Consul and the deployment assets used to deploy the
environment. When sensitive data is found among the information collected, the script also redacts the data before compacting the final .tgz file.

## Prerequisites

- The tool should be run on the machine/jumpbox from where the environment was originally deployed, with access to the deployment files and the Kubernetes 
command-line interface, `kubectl`, to access the Kubernetes cluster.
- Bash Shell

## Usage

**Note**: Some information may be omitted or unavailable depending on the permissions granted for the provided
`KUBECONFIG`.

### Interactive Mode Example

The following example runs the script without providing any option, which causes the script to request all required information interactively.

```
./get-k8s-info.sh
```

The script will request the following information interactively:

```
# Track Number:
-> SAS Tech Support track number (leave blank if not known):

# Deployment Assets Directory
-> Specify the path of the viya $deploy directory (<current directory>):

# Output Directory
-> Specify the path where the script output file will be saved (<current directory>):
```

**Note**: The \<current directory\> can be specified by just pressing ENTER.

### Command-line Mode Example

The following example runs the script providing all required options in the command line, which causes the script to execute without requesting any information:

```
./get-k8s-info.sh --track 7600000000 --deploypath /home/user/viyadeployments/prod --out /tmp 
```

* -t|--track  
    10-digit track number. When not provided, the script uses 7600000000 by default. When --sastsdrive is specified, this option is required.

* -d|--deploypath  
    Path of the directory containing the deployment assets, including the 'site-config' directory and 'kustomization.yaml' file. Deployment asset collection can be supressed by specifying '--deploypath unavailable'.

* -o|--out  
    Path of the directory where the final .tgz file will be created.

### Additional Options

You can specify options to enable additional features or collect additional information.

* -n|--namespace  

    Used to specify the namespace from where information will be collected. By default, the script automatically detects the namespace that contains a Viya deployment. If more than one are found and a namespace was not provided, the script will ask the user to choose one of the namespaces detected.

```
Namespaces with a Viya deployment:

[0] dev
[1] prod

 -> Select the namespace where the information should be collected from: 
```

* -l|--logs  

    Used to capture logs from pods using a comma separated list of label selectors. 

```
./get-k8s-info.sh --logs 'sas-microanalytic-score,type=esp,workload.sas.com/class=stateful'
```

**Note**: The default label key is "app=". As such, if a value without '=' is provided, the actual label selector will be 'app=\<value\>'.

* -d|--debugtags  

    Used to perform specific actions from the script based on a debugtag provided. Available debugtags are:  

    * 'cas': Capture logs from all cas related pods (sas-cas-control, sas-cas-operator, sas-cas-server controller and workers) and capture all casdeployment objects YAML definition.  
    * 'config': Dump all key-value pairs currently defined in Consul.  
    * 'nginx': Collect a list and describe output from objects created in the Ingress Controller namespace and collect logs from all ingress controller pods.  
    * 'postgres': Collect log from the sas-data-server-operator pod and all pgcluster objects YAML definition. If Postgres was deployed internally, also collect logs from all crunchy data pods, the pgha configmap YAML definition and the 'patronictl' command output.



```
./get-k8s-info.sh --debugtags 'postgres,cas'
```



* -s|--sastsdrive  

    Used to make the script try to send the final .tgz file to the track SASTSDrive workspace. Only use this option after a TSDrive workspace was already created and the customer authorized by Tech Support to send files to SASTSDrive for the track. It should not be used by customers whose domain have been enabled SSO with SAS, as the authentication won't work. If the script fails to send the .tgz file to SASTSDrive, the customer will still be able to collect the file from the --out directory to send it manually.

```
./get-k8s-info.sh --sastsdrive
```

### Automatic Debugging and Default Behavior

The script has some built-in debugging steps, which can trigger additional debugtags and collect logs from pods automatically:

* Not Ready Pods: If a pod is currently not healthy (i.e.: not "1/1 Running"), it will collect the logs from that pod automatically.
* Previous Logs: If a pod has ever been restarted automatically by kubernetes, it will collect the previous logs from that pod automatically.
* Any CAS or Postgres Pod Not Ready: If a pod from CAS or Postgres is not ready, it will automatically perform all actions from the respective debugtag.
* Redaction of Sensitive Data: For files that can contain sensitive data (usually inside deployment assets, consul config dump or YAML object definitions), the script parses those files and redacts 
  certificate, private keys, secrets, passwords and tokens with the string '{{ sensitive data removed }}'.

### Help with the Command

The `-h` or `--help` option can be used to view usage information and list all options available for the script.

```
./get-k8s-info.sh --help
```

## Script Output

The script generates a .tgz file containing all information and files in the --out directory upon completion:

* \<out\>/T\<tracknumber\>.tgz
