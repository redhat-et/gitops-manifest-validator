# Manifest Validator CMP — How It Works

This is an **ArgoCD Config Management Plugin (CMP)** that validates Kubernetes manifests during deployment and reports any issues found.

## How It Works

### Entry Point

ArgoCD invokes `scripts/validate.sh` as a sidecar container whenever an Application using this plugin syncs. The plugin runs inside a custom Docker image containing three validation tools: **Kubeconform**, **Pluto**, and **KubeLinter**.

### Validation Pipeline

The flow has five stages:

**1. Collect YAML files** — Finds all `*.yaml`/`*.yml` files, excluding `kustomization.yaml` and hidden files.

**2. Run three validation tools:**

| Tool | Purpose |
|------|---------|
| **Kubeconform** | Schema validation against K8s OpenAPI specs |
| **Pluto** | Detects deprecated/removed API versions |
| **KubeLinter** | Security and best-practice checks (configured via ConfigMap) |

**3. Collect errors** — `scripts/utils.sh` parses the JSON output from each tool and collects all findings into a single list, then generates a JSON report at `/tmp/validation-report.json`.

**4. AI analysis (optional)** — If errors were found and `OPENAI_BASE_URL` is configured, `scripts/ai-analysis.sh` sends the error report to an OpenAI-compatible API. The LLM returns root cause analysis and fix suggestions as markdown, written to `/tmp/ai-analysis.md`. If the call fails or is unconfigured, this step is skipped with a warning.

**5. Report and pass through:**

```
Issues found?
  └─ YES → Log warnings, run AI analysis (if configured),
           output original manifests to stdout,
           output ConfigMap with report.json + ai-analysis (if available),
           exit 0 (ArgoCD proceeds with deployment)

No issues?
  └─ Output original manifests to stdout,
     output ConfigMap with report.json, exit 0
```

### Configuration

Each tool is configured via its own ConfigMap:

- **`cmp-kubeconform-config`** — Sets the `KUBERNETES_VERSION` environment variable for schema validation
- **`cmp-pluto-config`** — Sets the `TARGET_KUBERNETES_VERSION` environment variable for API deprecation checks
- **`cmp-kube-linter-config`** — Mounts a `kube-linter.yaml` config file with the list of enabled/disabled checks
- **`cmp-openai-config`** (optional) — Sets `OPENAI_BASE_URL`, `OPENAI_API_KEY`, `OPENAI_MODEL_NAME`, and `OPENAI_TIMEOUT` for AI-powered error analysis. All four env vars are marked `optional: true` in the ArgoCD patch, so the sidecar works without this ConfigMap.

### UI Extension

The ArgoCD UI extension (`extensions/extension-manifest-validator.js`) reads the `manifest-validator-report` ConfigMap and renders a "Manifest Validation" tab. When the ConfigMap includes an `ai-analysis` key, the extension converts the markdown to HTML and displays it in an "AI-Powered Error Analysis" section below the error list.

### Deployment

The validator runs as a sidecar container in the ArgoCD repo-server pod, configured via `k8s/argocd-patch.yaml`. ConfigMaps provide the plugin registration, tool configurations, and KubeLinter check rules.
