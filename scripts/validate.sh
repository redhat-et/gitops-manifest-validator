#!/bin/bash
# Manifest Validator - Python/Ollama wrapper script
# This script discovers YAML manifests, runs AI-powered analysis via Ollama,
# and generates validation reports as Kubernetes ConfigMaps.

set -euo pipefail

# Logging functions (all output to stderr)
log_info() {
    echo "[INFO] $*" >&2
}

log_warn() {
    echo "[WARN] $*" >&2
}

log_error() {
    echo "[ERROR] $*" >&2
}

# Main execution
main() {
    log_info "Starting manifest validation..."

    # Discover YAML files (exclude kustomization files and hidden files)
    log_info "Discovering YAML manifests..."

    log_info "Current directory: $(pwd)"

    yaml_files=()
    while IFS= read -r -d '' file; do
        # Skip hidden files and kustomization files
        basename=$(basename "$file")
        if [[ ! "$basename" =~ ^\. ]] && [[ ! "$basename" =~ ^kustomization\. ]]; then
            yaml_files+=("$file")
            log_info "  Found: $file"
        fi
    done < <(find . -type f \( -name "*.yaml" -o -name "*.yml" \) -print0)

    if [ ${#yaml_files[@]} -eq 0 ]; then
        log_warn "No YAML manifests found in current directory"
    else
        log_info "Found ${#yaml_files[@]} manifest file(s)"
    fi

    # Output all manifests to stdout (for ArgoCD consumption)
    log_info "Outputting manifests to stdout..."
    for file in "${yaml_files[@]}"; do
        cat "$file"
        echo ""
        echo "---"
    done

    # Run AI-powered analysis via review_manifests.py
    log_info "Running AI-powered manifest analysis..."

    # Prepare prompt for analysis
    prompt="Analyze the Kubernetes manifests in the directory $(pwd) for security issues, best practices violations, and optimization opportunities. Provide a comprehensive review with specific recommendations"

    # Clear any old output file
    rm -f /tmp/ollama_review_output.txt

    # Call Python script (output goes to /tmp/ollama_review_output.txt)
    if ! python3.11 /home/argocd/scripts/review_manifests.py "$prompt" 2>&1 | while IFS= read -r line; do log_info "$line"; done; then
        log_error "AI analysis script exited with non-zero status"
    fi

    # Check if output file was created
    if [ ! -f /tmp/ollama_review_output.txt ]; then
        log_error "AI analysis did not produce output file, creating placeholder..."
        echo "AI analysis failed or timed out" > /tmp/ollama_review_output.txt
    fi

    # Read AI analysis output
    ai_analysis=""
    if [ -f /tmp/ollama_review_output.txt ]; then
        ai_analysis=$(cat /tmp/ollama_review_output.txt)
        log_info "AI analysis completed ($(wc -l < /tmp/ollama_review_output.txt) lines)"
    else
        log_warn "No AI analysis output found"
        ai_analysis="No analysis available"
    fi

    # Extract ArgoCD metadata from environment
    app_name="${ARGOCD_APP_NAME:-unknown}"
    source_repo="${ARGOCD_APP_SOURCE_REPO_URL:-unknown}"
    source_path="${ARGOCD_APP_SOURCE_PATH:-unknown}"
    revision="${ARGOCD_APP_REVISION:-unknown}"
    namespace="${ARGOCD_APP_NAMESPACE:-default}"
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Create report.json structure
    log_info "Generating validation report..."
    report_json=$(cat <<EOFJSON
{
  "timestamp": "$timestamp",
  "app_name": "$app_name",
  "source_repo": "$source_repo",
  "source_path": "$source_path",
  "revision": "$revision",
  "errors": []
}
EOFJSON
)

    # Generate ConfigMap YAML with report.json and ai-analysis
    log_info "Creating ConfigMap with validation results..."

    # Indent JSON for YAML embedding
    report_json_indented=$(echo "$report_json" | sed 's/^/    /')

    # Indent AI analysis for YAML embedding
    ai_analysis_indented=$(echo "$ai_analysis" | sed 's/^/    /')

    # Output ConfigMap to stdout
    cat <<EOFCM
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: manifest-validator-report
  namespace: $namespace
  labels:
    manifest-validator/report: "true"
    argocd.argoproj.io/instance: $app_name
data:
  report.json: |
$report_json_indented
  ai-analysis: |
$ai_analysis_indented
EOFCM

    log_info "Validation complete!"
    log_info "ConfigMap 'manifest-validator-report' will be created in namespace: $namespace"
}

# Execute main function and always exit 0 (non-blocking validation)
main || {
    log_error "Validation script encountered errors, but exiting successfully (non-blocking mode)"
}

exit 0
