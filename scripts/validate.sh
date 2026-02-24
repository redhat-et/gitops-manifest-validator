#!/bin/bash
set -uo pipefail

# Source utilities
source /home/argocd/scripts/utils.sh

# Configuration
# CMP receives files in current directory, not in ARGOCD_APP_SOURCE_PATH
WORK_DIR="."
mkdir /tmp/unvalidated-manifests/
cp -r "$WORK_DIR" /tmp/unvalidated-manifests/
OUTPUT_DIR="/tmp/validated-manifests"


# Initialize arrays
VALIDATION_ERRORS=()

# Initialize
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
log_info "Starting manifest validation for: $WORK_DIR"

# Step 1: Collect all YAML files (excluding kustomization and non-manifest files)
YAML_FILES=$(find "$WORK_DIR" -type f \( -name "*.yaml" -o -name "*.yml" \) \
    ! -name "kustomization.yaml" \
    ! -name "kustomization.yml" \
    ! -name "Kustomization" \
    ! -name ".*.yaml" \
    ! -name ".*.yml" \
    | sort)
if [ -z "$YAML_FILES" ]; then
    log_warn "No YAML files found in $WORK_DIR"
    exit 0
fi

log_info "Found $(echo "$YAML_FILES" | wc -l | tr -d ' ') YAML files to validate"

# Step 2: Run validation tools and collect results

# Run Kubeconform (schema validation)
log_info "Running Kubeconform schema validation..."
K8S_VERSION="${KUBERNETES_VERSION:-1.28.0}"
log_info "Kubeconform: validating against Kubernetes $K8S_VERSION schema"
/home/argocd/scripts/kubeconform-check.sh "$WORK_DIR" "$K8S_VERSION" > /tmp/kubeconform-output.json 2>&1 || true
collect_kubeconform_errors /tmp/kubeconform-output.json

# Run Pluto (deprecated API detection)
log_info "Running Pluto deprecated API detection..."
TARGET_K8S_VERSION="${TARGET_KUBERNETES_VERSION:-v1.29.0}"
log_info "Pluto: checking for deprecated APIs against Kubernetes $TARGET_K8S_VERSION"
/home/argocd/scripts/pluto-check.sh "$WORK_DIR" "$TARGET_K8S_VERSION" > /tmp/pluto-output.json 2>&1 || true
collect_pluto_errors /tmp/pluto-output.json

# Run KubeLinter (best practices)
log_info "Running KubeLinter best practices check..."
/home/argocd/scripts/kubelinter-check.sh "$WORK_DIR" > /tmp/kubelinter-output.json 2>&1 || true
collect_kubelinter_errors /tmp/kubelinter-output.json

# Step 3: Generate report
log_info "Validation complete: ${#VALIDATION_ERRORS[@]} issues found"

if [ ${#VALIDATION_ERRORS[@]} -gt 0 ]; then
    generate_error_report

    for err in "${VALIDATION_ERRORS[@]}"; do
        local_tool="${err%%|*}"
        local_msg="${err#*|}"
        log_warn "  [$local_tool] $local_msg"
    done
fi

# Step 4: Output manifests (always pass through regardless of errors)
log_info "Outputting manifests"
for file in $YAML_FILES; do
    cat "$file"
    echo ""
    echo "---"
done

log_info "Manifest validation complete"
