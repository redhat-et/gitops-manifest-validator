# Manifest Validator CMP — How It Works

This is an **ArgoCD Config Management Plugin (CMP)** that validates Kubernetes manifests during deployment and reports any issues found.

## How It Works

### Entry Point

ArgoCD invokes `scripts/validate.sh` as a sidecar container whenever an Application using this plugin syncs. The plugin runs inside a custom Docker image containing three validation tools: **Kubeconform**, **Pluto**, and **KubeLinter**.

### Validation Pipeline

The flow has four stages:

**1. Collect YAML files** — Finds all `*.yaml`/`*.yml` files, excluding `kustomization.yaml` and hidden files.

**2. Run three validation tools:**

| Tool | Purpose |
|------|---------|
| **Kubeconform** | Schema validation against K8s OpenAPI specs |
| **Pluto** | Detects deprecated/removed API versions |
| **KubeLinter** | Security and best-practice checks (configured via ConfigMap) |

**3. Collect errors** — `scripts/utils.sh` parses the JSON output from each tool and collects all findings into a single list.

**4. Report and pass through:**

```
Issues found?
  └─ YES → Log warnings, generate JSON report at /tmp/validation-report.json,
           output original manifests to stdout, exit 0
           (ArgoCD proceeds with deployment)

No issues?
  └─ Output original manifests to stdout, exit 0
```

### Configuration

Each tool is configured via its own ConfigMap:

- **`cmp-kubeconform-config`** — Sets the `KUBERNETES_VERSION` environment variable for schema validation
- **`cmp-pluto-config`** — Sets the `TARGET_KUBERNETES_VERSION` environment variable for API deprecation checks
- **`cmp-kube-linter-config`** — Mounts a `kube-linter.yaml` config file with the list of enabled/disabled checks

### Deployment

The validator runs as a sidecar container in the ArgoCD repo-server pod, configured via `k8s/argocd-patch.yaml`. ConfigMaps provide the plugin registration, tool configurations, and KubeLinter check rules.
