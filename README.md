# Manifest Validator CMP for ArgoCD

A Config Management Plugin (CMP) for ArgoCD/OpenShift GitOps that validates Kubernetes manifests and reports issues.

## Features

- **AI-Powered Manifest Analysis** - Uses self-hosted Ollama with qwen2.5:14b model for comprehensive manifest review
- **Function Calling & Skills** - Python-based validation leverages Claude skills (k8s-lint-validator, k8s-manifest-reviewer) for intelligent analysis
- **Security Best Practices** - Identifies security issues, misconfigurations, and optimization opportunities
- **Non-Blocking Validation** - Manifests always deploy successfully; issues are reported for review
- **ArgoCD UI Integration** - Dedicated "Manifest Validation" tab shows AI-powered analysis results

Validation results are written to a `manifest-validator-report` ConfigMap deployed alongside application resources. An ArgoCD UI extension provides a "Manifest Validation" tab displaying the AI analysis. All manifests pass through to ArgoCD regardless of findings.

## Validation Approach

The validator uses AI-powered analysis via Ollama to provide comprehensive manifest review:

- **Schema Validation** - Detects invalid Kubernetes API usage, missing required fields
- **API Deprecation** - Identifies removed or deprecated API versions
- **Security Issues** - Flags privileged containers, host network/PID access, missing security contexts
- **Best Practices** - Reviews resource limits, readiness/liveness probes, image tags
- **Optimization** - Suggests improvements for efficiency, reliability, and maintainability

The AI model can dynamically call validation skills (kubeconform, pluto, kubelinter) as needed during analysis.

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

### 2. Deploy Ollama Service

```bash
# Apply all Ollama resources (PVC, Deployment, Service, Job)
kubectl apply -f k8s/ollama/

# Monitor model pull progress (this takes 10-30 minutes for ~8-10GB download)
kubectl logs -n openshift-gitops job/ollama-model-pull -f


# Wait for model pull to complete
kubectl wait --for=condition=complete job/ollama-model-pull -n openshift-gitops --timeout=1800s

# Verify Ollama is ready
kubectl get pods -n openshift-gitops -l app.kubernetes.io/name=ollama
```

### 3. Deploy Kubernetes Resources

```bash
# Apply ConfigMaps
kubectl apply -f k8s/configmap-plugin.yaml
kubectl apply -f k8s/configmap-openai.yaml
kubectl apply -f k8s/configmap-extension.yaml

# Patch ArgoCD to add the CMP sidecar and UI extension
kubectl patch argocd openshift-gitops -n openshift-gitops --type=merge --patch-file k8s/argocd-patch.yaml
```

### 4. Wait for Rollout

```bash
kubectl rollout status deployment/openshift-gitops-repo-server -n openshift-gitops
```

### 5. Verify Deployment

**Check CMP sidecar:**
```bash
kubectl get pods -n openshift-gitops -l app.kubernetes.io/name=openshift-gitops-repo-server \
  -o jsonpath='{.items[0].spec.containers[*].name}'
# Should include "manifest-validator"
```

**Check CMP logs:**
```bash
kubectl logs -n openshift-gitops deployment/openshift-gitops-repo-server -c manifest-validator -f
```

**Test Ollama connectivity:**
```bash
kubectl run test-ollama -n openshift-gitops --rm -i --restart=Never \
  --image=curlimages/curl -- \
  curl -X POST http://ollama:11434/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen2.5:14b","messages":[{"role":"user","content":"Hello"}]}'
```

Alternatively, use the test pod manifest:
```bash
kubectl apply -f k8s/ollama/test-ollama-pod.yaml
kubectl logs -n openshift-gitops test-ollama -f
kubectl delete pod test-ollama -n openshift-gitops
```


### 6. Test with Application

Create a test application:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: test-validator
  namespace: openshift-gitops
spec:
  source:
    plugin:
      name: manifest-validator
    repoURL: <your-repo>
    path: <manifests-path>
  destination:
    server: https://kubernetes.default.svc
    namespace: test-ns
```

**Verify results:**
1. Sync the application
2. Check for ConfigMap: `kubectl get configmap manifest-validator-report -n test-ns`
3. Verify ConfigMap has both keys: `kubectl get configmap manifest-validator-report -n test-ns -o yaml`
4. Open ArgoCD UI → Navigate to application → Look for "Manifest Validation" tab
5. Confirm AI analysis appears



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
| `cmp-plugin-config` | `plugin.yaml` | See ConfigMap | ArgoCD CMP plugin registration |
| `manifest-validator-extension` | `extension-manifest-validator.js` | See ConfigMap | ArgoCD UI extension JavaScript |
| `cmp-openai-config` | `OPENAI_BASE_URL` | `http://ollama.openshift-gitops.svc.cluster.local:11434/v1` | Ollama service URL |
| `cmp-openai-config` | `OPENAI_API_KEY` | `not-needed` | API key (not required for Ollama) |
| `cmp-openai-config` | `OPENAI_MODEL_NAME` | `qwen2.5:14b` | Model name for analysis |
| `cmp-openai-config` | `OPENAI_TIMEOUT` | `120` | Request timeout in seconds |

### Ollama Configuration

The Ollama service runs in the `openshift-gitops` namespace with:
- **Model**: qwen2.5:14b (~8-10GB, auto-pulled via Job)
- **Storage**: 20Gi PVC for model persistence
- **Resources**: 2 CPU / 10Gi memory limits (8Gi requests, 10Gi limits to accommodate 8.7 GiB model requirement)

### AI Analysis Customization

The AI analysis behavior is controlled by the prompt in `scripts/validate.sh`. The Python script (`review_manifests.py`) uses function calling to dynamically load and execute Claude skills from `.claude/skills/` directory based on the analysis requirements.

### Report ConfigMap

The CMP outputs a `manifest-validator-report` ConfigMap to each application's target namespace containing the validation report as JSON. When AI analysis is configured and succeeds, the ConfigMap also includes an `ai-analysis` key with the LLM's markdown response. This ConfigMap is managed by ArgoCD as part of the application's resources and is cleaned up automatically if pruning is enabled. The UI extension reads this ConfigMap to display results.

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
