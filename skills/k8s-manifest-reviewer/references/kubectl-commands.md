# kubectl Commands Reference for Manifest Review

Essential kubectl commands for inspecting and analyzing deployed Kubernetes resources.

## Resource Discovery

### List Resources

```bash
# All resources in namespace
kubectl get all -n <namespace>

# Specific resource types
kubectl get deployments,statefulsets,daemonsets -n <namespace>
kubectl get pods,services,ingresses -n <namespace>
kubectl get configmaps,secrets -n <namespace>
kubectl get hpa,pdb -n <namespace>

# Across all namespaces
kubectl get pods -A
kubectl get deployments -A

# With additional columns
kubectl get pods -n <namespace> -o wide
kubectl get nodes -o wide
```

### Show Labels

```bash
# Show labels
kubectl get pods -n <namespace> --show-labels

# Filter by label
kubectl get pods -n <namespace> -l app=web
kubectl get pods -n <namespace> -l 'environment in (prod,staging)'

# Show specific label columns
kubectl get pods -n <namespace> -L app,version
```

## Detailed Inspection

### describe - Most Comprehensive

```bash
# Get detailed information including events
kubectl describe pod <name> -n <namespace>
kubectl describe deployment <name> -n <namespace>
kubectl describe node <name>

# Describes all pods matching label
kubectl describe pods -n <namespace> -l app=web
```

**Output includes**:
- Resource metadata and specifications
- Current status and conditions
- Volume mounts and secrets
- Resource requests and limits
- Events (last hour)
- Node assignment

### get with YAML/JSON output

```bash
# Full YAML representation
kubectl get pod <name> -n <namespace> -o yaml

# Full JSON representation
kubectl get deployment <name> -n <namespace> -o json

# Extract specific fields with jsonpath
kubectl get pods -n <namespace> -o jsonpath='{.items[*].metadata.name}'

# Custom columns
kubectl get pods -n <namespace> -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,NODE:.spec.nodeName
```

### explain - Built-in Documentation

```bash
# Get documentation for resource type
kubectl explain pod
kubectl explain deployment.spec
kubectl explain pod.spec.containers

# Show all fields recursively
kubectl explain pod --recursive

# Useful for understanding available fields
kubectl explain deployment.spec.strategy.rollingUpdate
```

## Resource Usage

### top - Resource Metrics

```bash
# Node resource usage
kubectl top nodes
kubectl top nodes --sort-by=cpu
kubectl top nodes --sort-by=memory

# Pod resource usage
kubectl top pods -n <namespace>
kubectl top pods -A
kubectl top pods -n <namespace> --sort-by=cpu
kubectl top pods -n <namespace> --sort-by=memory

# Specific pod with containers
kubectl top pod <name> -n <namespace> --containers
```

**Requires**: Metrics Server installed

### Resource Requests vs Limits

```bash
# Show resource configuration
kubectl get pod <name> -n <namespace> -o jsonpath='{.spec.containers[*].resources}'

# Compare all pods in namespace
kubectl get pods -n <namespace> -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].resources.requests.cpu}{"\t"}{.spec.containers[*].resources.limits.cpu}{"\n"}{end}'

# Format: Name, CPU Request, CPU Limit
```

## Status and Health

### Pod Status

```bash
# Check pod status
kubectl get pods -n <namespace>

# Show conditions
kubectl get pod <name> -n <namespace> -o jsonpath='{.status.conditions[*].type}'

# Check ready status
kubectl get pod <name> -n <namespace> -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'

# Check restart count
kubectl get pods -n <namespace> -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.containerStatuses[*].restartCount}{"\n"}{end}'
```

### Deployment Rollout Status

```bash
# Check rollout status
kubectl rollout status deployment/<name> -n <namespace>

# View rollout history
kubectl rollout history deployment/<name> -n <namespace>

# View specific revision
kubectl rollout history deployment/<name> -n <namespace> --revision=2

# Pause/resume rollouts
kubectl rollout pause deployment/<name> -n <namespace>
kubectl rollout resume deployment/<name> -n <namespace>

# Rollback
kubectl rollout undo deployment/<name> -n <namespace>
kubectl rollout undo deployment/<name> -n <namespace> --to-revision=2
```

## Events and Logs

### Events

```bash
# Recent events in namespace
kubectl get events -n <namespace>

# Sort by timestamp
kubectl get events -n <namespace> --sort-by='.lastTimestamp'

# Events across all namespaces
kubectl get events -A

# Filter events for specific object
kubectl get events -n <namespace> --field-selector involvedObject.name=<pod-name>

# Watch events in real-time
kubectl get events -n <namespace> --watch
```

### Logs

```bash
# View pod logs
kubectl logs <pod-name> -n <namespace>

# Specific container in pod
kubectl logs <pod-name> -c <container-name> -n <namespace>

# Last N lines
kubectl logs <pod-name> -n <namespace> --tail=50

# Follow logs
kubectl logs <pod-name> -n <namespace> --follow

# Previous container instance (after crash)
kubectl logs <pod-name> -n <namespace> --previous

# All pods with label
kubectl logs -n <namespace> -l app=web --all-containers=true

# Timestamp logs
kubectl logs <pod-name> -n <namespace> --timestamps
```

## Configuration and Secrets

### ConfigMaps

```bash
# List ConfigMaps
kubectl get configmaps -n <namespace>

# Show ConfigMap data
kubectl get configmap <name> -n <namespace> -o yaml

# Describe ConfigMap
kubectl describe configmap <name> -n <namespace>

# Check which pods use it
kubectl get pods -n <namespace> -o json | jq '.items[] | select(.spec.volumes[]?.configMap.name=="<configmap-name>") | .metadata.name'
```

### Secrets

```bash
# List Secrets
kubectl get secrets -n <namespace>

# Show Secret (base64 encoded)
kubectl get secret <name> -n <namespace> -o yaml

# Decode secret value
kubectl get secret <name> -n <namespace> -o jsonpath='{.data.<key>}' | base64 -d

# Check which pods use it
kubectl get pods -n <namespace> -o json | jq '.items[] | select(.spec.volumes[]?.secret.secretName=="<secret-name>") | .metadata.name'
```

## Networking

### Services

```bash
# List services
kubectl get services -n <namespace>

# Describe service
kubectl describe service <name> -n <namespace>

# Check endpoints
kubectl get endpoints <name> -n <namespace>

# Show service with endpoints
kubectl get svc <name> -n <namespace> -o wide
```

### Ingress

```bash
# List ingresses
kubectl get ingress -n <namespace>

# Describe ingress
kubectl describe ingress <name> -n <namespace>

# Show ingress rules
kubectl get ingress <name> -n <namespace> -o jsonpath='{.spec.rules[*].host}'
```

### Network Policies

```bash
# List network policies
kubectl get networkpolicies -n <namespace>

# Describe network policy
kubectl describe networkpolicy <name> -n <namespace>
```

## Autoscaling

### HorizontalPodAutoscaler

```bash
# List HPAs
kubectl get hpa -n <namespace>

# Describe HPA
kubectl describe hpa <name> -n <namespace>

# Show HPA status
kubectl get hpa <name> -n <namespace> -o jsonpath='{.status.currentReplicas}{" / "}{.status.desiredReplicas}'

# Check HPA metrics
kubectl get hpa <name> -n <namespace> -o jsonpath='{.status.currentMetrics}'
```

### PodDisruptionBudget

```bash
# List PDBs
kubectl get pdb -n <namespace>

# Describe PDB
kubectl describe pdb <name> -n <namespace>
```

## Storage

### PersistentVolumeClaims

```bash
# List PVCs
kubectl get pvc -n <namespace>

# Describe PVC
kubectl describe pvc <name> -n <namespace>

# Show bound PV
kubectl get pvc <name> -n <namespace> -o jsonpath='{.spec.volumeName}'

# Check which pods use PVC
kubectl get pods -n <namespace> -o json | jq '.items[] | select(.spec.volumes[]?.persistentVolumeClaim.claimName=="<pvc-name>") | .metadata.name'
```

### PersistentVolumes

```bash
# List PVs (cluster-scoped)
kubectl get pv

# Describe PV
kubectl describe pv <name>

# Show PV status
kubectl get pv -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,CLAIM:.spec.claimRef.name
```

## Security

### ServiceAccounts

```bash
# List service accounts
kubectl get serviceaccounts -n <namespace>

# Describe service account
kubectl describe serviceaccount <name> -n <namespace>

# Check which pods use SA
kubectl get pods -n <namespace> -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.serviceAccountName}{"\n"}{end}'
```

### RBAC

```bash
# List roles and rolebindings
kubectl get roles,rolebindings -n <namespace>

# Cluster-level
kubectl get clusterroles,clusterrolebindings

# Describe role
kubectl describe role <name> -n <namespace>

# Check permissions for service account
kubectl auth can-i --list --as=system:serviceaccount:<namespace>:<sa-name> -n <namespace>
```

## Cluster Information

### Cluster Context

```bash
# Show current context
kubectl config current-context

# Show cluster info
kubectl cluster-info

# API server version
kubectl version --short

# Cluster API resources
kubectl api-resources

# API versions
kubectl api-versions
```

### Nodes

```bash
# List nodes
kubectl get nodes

# Describe node
kubectl describe node <name>

# Node capacity and allocatable
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.capacity.cpu}{"\t"}{.status.allocatable.cpu}{"\n"}{end}'

# Pods on specific node
kubectl get pods -A --field-selector spec.nodeName=<node-name>
```

## Advanced Queries with JSONPath

### Useful Patterns

```bash
# List all images in use
kubectl get pods -A -o jsonpath='{range .items[*]}{.spec.containers[*].image}{"\n"}{end}' | sort -u

# Find pods without resource limits
kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].resources.limits}{"\n"}{end}' | grep -v "map"

# Find pods without probes
kubectl get pods -n <namespace> -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].livenessProbe}{"\n"}{end}' | grep -v "map"

# List all environment variables
kubectl get pod <name> -n <namespace> -o jsonpath='{.spec.containers[*].env[*].name}{"\n"}'

# Check for privileged containers
kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].securityContext.privileged}{"\n"}{end}' | grep true

# Find pods running as root
kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.securityContext.runAsUser}{"\n"}{end}' | grep -E '\s0$'
```

## Efficiency Tips

### Use Aliases

```bash
# Common aliases
alias k=kubectl
alias kgp='kubectl get pods'
alias kgd='kubectl get deployments'
alias kgs='kubectl get services'
alias kdp='kubectl describe pod'
alias kl='kubectl logs'
```

### Output Format Options

- `-o yaml`: Full YAML representation
- `-o json`: Full JSON representation
- `-o wide`: Additional columns
- `-o name`: Resource name only
- `-o jsonpath='{.path}'`: Extract specific fields
- `-o custom-columns=`: Define custom output columns

### Field Selectors

```bash
# Filter by status
kubectl get pods --field-selector status.phase=Running

# Filter by node
kubectl get pods --field-selector spec.nodeName=<node>

# Filter by specific field
kubectl get events --field-selector involvedObject.name=<name>
```

### Label Selectors

```bash
# Equality
kubectl get pods -l app=web

# Inequality
kubectl get pods -l app!=web

# Set membership
kubectl get pods -l 'environment in (prod,staging)'

# Multiple selectors
kubectl get pods -l app=web,version=v1
```

## Reference

- Official kubectl docs: https://kubernetes.io/docs/reference/kubectl/
- kubectl Cheat Sheet: https://kubernetes.io/docs/reference/kubectl/cheatsheet/
- JSONPath Support: https://kubernetes.io/docs/reference/kubectl/jsonpath/
