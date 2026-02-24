# Manifest Validator CMP for ArgoCD

A Config Management Plugin (CMP) for ArgoCD/OpenShift GitOps that validates Kubernetes manifests and reports issues.

## Features

- **Schema Validation** (Kubeconform) - Validates manifests against Kubernetes API schemas
- **Deprecated API Detection** (Pluto) - Detects removed and deprecated API versions
- **Best Practices** (KubeLinter) - Checks security and configuration best practices

All validation issues are logged and written to a single JSON report at `/tmp/validation-report.json`. Manifests are always passed through to ArgoCD regardless of findings. A `manifest-validator-report` ConfigMap is deployed alongside application resources, and an ArgoCD UI extension provides a "Manifest Validation" tab on each application.

## Validation Checks

| Tool | Check | Description |
|------|-------|-------------|
| Kubeconform | Schema validation | Missing required fields, invalid values, type mismatches |
| Pluto | Removed APIs | API versions removed in target K8s version |
| Pluto | Deprecated APIs | API versions deprecated in target K8s version |
| KubeLinter | Security | host-network, host-pid, host-ipc, privileged-container |
| KubeLinter | Best practices | read-only root fs, CPU/memory requirements, latest tag, NET_RAW capability |

## Prerequisites

- OpenShift GitOps or ArgoCD installed
- Podman installed locally

## Installation

### 1. Build and Push Container Image to OpenShift Internal Registry

```bash
cd manifest-validator

# Login to OpenShift
oc login -u kubeadmin https://api.crc.testing:6443

# Expose the internal registry (if not already exposed)
oc patch configs.imageregistry.operator.openshift.io/cluster --type merge -p '{"spec":{"defaultRoute":true}}'

# Create the BuildConfig (if not already applied)
oc apply -f k8s/buildconfig.yaml -n openshift-gitops

# Trigger the build — uploads your local source into the cluster and builds there.
oc start-build manifest-validator --from-dir=. -n openshift-gitops --follow

#Validate the build is there
oc get imagestream manifest-validator -n openshift-gitops
```

### 2. Deploy Kubernetes Resources

```bash
# Apply ConfigMaps
kubectl apply -f k8s/configmap-plugin.yaml
kubectl apply -f k8s/configmap-kube-linter.yaml
kubectl apply -f k8s/configmap-kubeconform.yaml
kubectl apply -f k8s/configmap-pluto.yaml
kubectl apply -f k8s/configmap-extension.yaml

# Patch ArgoCD to add the CMP sidecar and UI extension
kubectl patch argocd openshift-gitops -n openshift-gitops --type=merge --patch-file k8s/argocd-patch.yaml
```

### 3. Wait for Rollout

```bash
kubectl rollout status deployment/openshift-gitops-repo-server -n openshift-gitops
```

### 4. To Remove the sidecar

```bash
kubectl patch argocd openshift-gitops -n openshift-gitops --type=merge --patch-file k8s/argocd-remove.yaml
```

## Usage

### Create an Application Using the Plugin

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: openshift-gitops
spec:
  source:
    plugin:
      name: manifest-validator
    repoURL: git@github.com:your-org/your-repo.git
    path: manifests/
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: my-app-ns
```

See `k8s/example-application.yaml` for a complete example.

## Verification

### Check Sidecar is Running

```bash
kubectl get pods -n openshift-gitops -l app.kubernetes.io/name=openshift-gitops-repo-server \
  -o jsonpath='{.items[*].spec.containers[*].name}'
```

### View CMP Logs

```bash
kubectl logs -n openshift-gitops deployment/openshift-gitops-repo-server -c manifest-validator -f
```

### Check UI Extension is Loaded

After patching, the argocd-server pod will restart. Once it's ready, open the ArgoCD UI and navigate to an application that uses the `manifest-validator` plugin. A "Manifest Validation" tab should appear in the application view.

### Test Validation

1. **Valid manifests** - Should pass through with no issues reported, tab shows "All checks passed"
2. **Invalid schema** - Should report errors in logs and validation report, manifests still passed through, tab shows errors grouped by tool

## Configuration

### ConfigMaps

| ConfigMap | Key | Default | Description |
|-----------|-----|---------|-------------|
| `cmp-kubeconform-config` | `KUBERNETES_VERSION` | `1.28.0` | K8s version for schema validation |
| `cmp-pluto-config` | `TARGET_KUBERNETES_VERSION` | `v1.29.0` | Target K8s version for API deprecation |
| `cmp-kube-linter-config` | `kube-linter.yaml` | See ConfigMap | KubeLinter check configuration |
| `manifest-validator-extension` | `extension-manifest-validator.js` | See ConfigMap | ArgoCD UI extension JavaScript |

### Customizing KubeLinter Rules

Edit the `cmp-kube-linter-config` ConfigMap to enable/disable specific checks.

### Report ConfigMap

The CMP outputs a `manifest-validator-report` ConfigMap to each application's target namespace containing the validation report as JSON. This ConfigMap is managed by ArgoCD as part of the application's resources and is cleaned up automatically if pruning is enabled. The UI extension reads this ConfigMap to display results.

## Troubleshooting

### Plugin Not Discovered

Check that the plugin configuration is mounted correctly:
```bash
kubectl exec -n openshift-gitops deployment/openshift-gitops-repo-server -c manifest-validator \
  -- cat /home/argocd/cmp-server/config/plugin.yaml
```

### Validation Tools Missing

Check init logs:
```bash
kubectl logs -n openshift-gitops deployment/openshift-gitops-repo-server -c manifest-validator | head -20
```

## License

MIT
