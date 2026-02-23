# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Manifest Validator is an ArgoCD Config Management Plugin (CMP) that validates Kubernetes manifests during deployment using three tools: **Kubeconform** (schema validation), **Pluto** (deprecated API detection), and **KubeLinter** (security/best practices). It is non-blocking — validation issues are reported but never prevent deployment. All manifests pass through to stdout for ArgoCD consumption.

## Build & Deploy (OpenShift)

```bash
# Build the container image
oc start-build manifest-validator --from-dir=. -n openshift-gitops --follow

# Apply ConfigMaps
kubectl apply -f k8s/configmap-plugin.yaml
kubectl apply -f k8s/configmap-kube-linter.yaml
kubectl apply -f k8s/configmap-kubeconform.yaml
kubectl apply -f k8s/configmap-pluto.yaml

# Patch ArgoCD to add sidecar
kubectl patch argocd openshift-gitops -n openshift-gitops --type merge --patch-file k8s/argocd-patch.yaml
```

There are no tests, linting, or local build commands — the project is shell scripts validated at container build time.

## Architecture

### Validation Pipeline

`scripts/validate.sh` is the orchestrator. It discovers YAML files (excluding `kustomization.yaml` and hidden files), runs all three validators, collects errors via `scripts/utils.sh`, generates a JSON report at `/tmp/validation-report.json`, and outputs the original manifests to stdout. It always exits 0.

### Stdout/Stderr Separation

This is critical: **stdout is reserved exclusively for manifest output** (consumed by ArgoCD). All logging goes to stderr via `log_info`, `log_warn`, `log_error` in `utils.sh`. Any accidental stdout output from validation scripts will corrupt the manifest stream.

### Tool Wrappers

Each tool has a wrapper script in `scripts/` that runs the tool and outputs results. The wrappers do not collect errors themselves — error collection happens in `validate.sh` using functions from `utils.sh`:
- `collect_kubeconform_errors()` — parses JSON output for invalid/error statuses
- `collect_pluto_errors()` — parses JSON for removed/deprecated API flags
- `collect_kubelinter_errors()` — parses JSON Reports array

### Error Report Format

Errors are stored as `"tool|message"` strings in the `VALIDATION_ERRORS[]` bash array, then serialized to JSON by `generate_error_report()` with ArgoCD metadata (app name, repo, path, revision from environment variables).

### CMP Integration

`plugin.yaml` defines the ArgoCD CMP contract:
- **init**: verifies all three tools are installed
- **discover**: matches directories containing `*.yaml` files
- **generate**: runs `validate.sh`

The plugin runs as a sidecar container alongside the ArgoCD repo-server (patched via `k8s/argocd-patch.yaml`). Tool versions and KubeLinter rules are injected via ConfigMaps.

### Container

Built on UBI 9 Minimal, runs as non-root user `argocd` (UID 999). Tools are downloaded for linux/arm64 architecture. Scripts live at `/home/argocd/scripts/`, plugin config at `/home/argocd/cmp-server/config/plugin.yaml`.
