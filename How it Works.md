# Manifest Validator CMP — How It Works

This is an **ArgoCD Config Management Plugin (CMP)** that validates Kubernetes manifests during deployment and reports any issues found.

## How It Works

### Entry Point

ArgoCD invokes `scripts/validate.sh` as a sidecar container whenever an Application using this plugin syncs. The plugin runs inside a custom Docker image containing Python 3.11, the OpenAI SDK, validation tools (kubeconform, pluto, kubelinter), and Claude skills for intelligent analysis.

### Validation Pipeline

The flow has four stages:

**1. Discover manifests** — `scripts/validate.sh` (bash wrapper) finds all `*.yaml`/`*.yml` files, excluding `kustomization.yaml` and hidden files.

**2. Output manifests to stdout** — All discovered YAML files are written to stdout with `---` separators for ArgoCD consumption.

**3. AI-powered analysis** — The wrapper calls `scripts/review_manifests.py` (Python) which:
- Connects to the Ollama service running in the cluster
- Uses the qwen2.5:14b model with function calling capabilities
- Dynamically loads Claude skills from `.claude/skills/` directory
- Analyzes manifests by calling appropriate skills (k8s-lint-validator, k8s-manifest-reviewer)
- Generates comprehensive markdown analysis with security, best practices, and optimization recommendations
- Writes results to `/tmp/ollama_review_output.txt`

**4. Generate ConfigMap report:**

```
AI analysis complete?
  └─ YES → Create ConfigMap with report.json + ai-analysis,
           output to stdout,
           log completion to stderr,
           exit 0 (always non-blocking)

AI analysis failed?
  └─ Create ConfigMap with report.json + error message,
     output to stdout, exit 0
```

### Ollama Integration

The validator uses a self-hosted Ollama service instead of external APIs:
- **Service**: Runs as a Deployment in `openshift-gitops` namespace
- **Model**: qwen2.5:14b (14B parameter model, ~8-10GB)
- **Storage**: 20Gi PVC for model persistence
- **Endpoint**: `http://ollama.openshift-gitops.svc.cluster.local:11434/v1`
- **Deployment**: Automated via `k8s/ollama/` resources, model auto-pulled by Kubernetes Job

### Function Calling with Skills

The Python script uses OpenAI's function calling API to dynamically invoke Claude skills:
1. Skills are discovered from `.claude/skills/` directory at runtime
2. Each skill's metadata (name, description, allowed-tools) is parsed from `SKILL.md`
3. Skills are registered as callable functions in the API request
4. The AI model decides which skills to call based on the manifest content
5. Skill execution results are fed back to the model for comprehensive analysis

This enables the AI to perform targeted validation (schema checks, security scans) only when needed, rather than running all tools blindly.

### Configuration

The validator is configured via two ConfigMaps:

- **`cmp-plugin-config`** — ArgoCD CMP plugin registration (`plugin.yaml`)
- **`cmp-openai-config`** — Ollama service connection settings:
  - `OPENAI_BASE_URL`: Ollama service endpoint (default: in-cluster service)
  - `OPENAI_MODEL_NAME`: Model to use (qwen2.5:14b)
  - `OPENAI_TIMEOUT`: Request timeout in seconds (120s for larger model)

Skills configuration is embedded in `.claude/skills/` directory structure copied into the container image at build time.

### UI Extension

The ArgoCD UI extension (`configmap-extension.yaml`) reads the `manifest-validator-report` ConfigMap and renders a "Manifest Validation" tab. The extension converts the markdown in the `ai-analysis` key to HTML and displays the AI-powered analysis results.

### Deployment

The validator runs as a sidecar container in the ArgoCD repo-server pod, configured via `k8s/argocd-patch.yaml`. ConfigMaps provide the plugin registration, tool configurations, and KubeLinter check rules.
