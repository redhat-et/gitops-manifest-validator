#!/bin/bash

# Logging functions
log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') $*" >&2
}

log_warn() {
    echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') $*" >&2
}

log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $*" >&2
}

# Single array for all validation errors
declare -a VALIDATION_ERRORS

# Error collection functions
collect_kubeconform_errors() {
    local output_file="$1"

    if [ ! -f "$output_file" ] || [ ! -s "$output_file" ]; then
        return
    fi

    # Parse JSON output - all schema errors are collected
    while IFS= read -r line; do
        local status=$(echo "$line" | jq -r '.status // empty' 2>/dev/null)

        if [ "$status" = "statusInvalid" ] || [ "$status" = "statusError" ] || [ "$status" = "invalid" ] || [ "$status" = "error" ]; then
            local filename=$(echo "$line" | jq -r '.filename // "unknown"' 2>/dev/null)
            local msg=$(echo "$line" | jq -r '.msg // "validation error"' 2>/dev/null)

            log_warn "Kubeconform: $filename - $msg"
            VALIDATION_ERRORS+=("kubeconform|$filename - $msg")
        fi
    done < <(jq -c 'if type == "array" then .[] else . end' "$output_file" 2>/dev/null || cat "$output_file" 2>/dev/null)

    # Also check for non-JSON error output
    if grep -qi "error\|invalid\|missing required" "$output_file" 2>/dev/null; then
        local error_text=$(grep -i "error\|invalid\|missing required" "$output_file" 2>/dev/null | head -5)
        if [ -n "$error_text" ]; then
            log_warn "Kubeconform raw error output detected"
            VALIDATION_ERRORS+=("kubeconform|$error_text")
        fi
    fi
}

collect_pluto_errors() {
    local output_file="$1"

    if [ ! -f "$output_file" ] || [ ! -s "$output_file" ]; then
        return
    fi

    while IFS= read -r line; do
        local removed=$(echo "$line" | jq -r '.removed // false' 2>/dev/null)
        local deprecated=$(echo "$line" | jq -r '.deprecated // false' 2>/dev/null)
        local name=$(echo "$line" | jq -r '.name // "unknown"' 2>/dev/null)
        local kind=$(echo "$line" | jq -r '.kind // "unknown"' 2>/dev/null)
        local version=$(echo "$line" | jq -r '.version // "unknown"' 2>/dev/null)
        local replacement=$(echo "$line" | jq -r '.replacementAPI // "none"' 2>/dev/null)

        if [ "$removed" = "true" ]; then
            log_warn "Pluto: $kind/$name uses removed API $version (replace with $replacement)"
            VALIDATION_ERRORS+=("pluto|$kind/$name uses removed API $version (replace with $replacement)")
        elif [ "$deprecated" = "true" ]; then
            log_warn "Pluto: $kind/$name uses deprecated API $version (replace with $replacement)"
            VALIDATION_ERRORS+=("pluto|$kind/$name uses deprecated API $version (replace with $replacement)")
        fi
    done < <(jq -c '.items[]?' "$output_file" 2>/dev/null || true)
}

collect_kubelinter_errors() {
    local output_file="$1"

    if [ ! -f "$output_file" ] || [ ! -s "$output_file" ]; then
        return
    fi

    while IFS= read -r line; do
        local check=$(echo "$line" | jq -r '.Check // empty' 2>/dev/null)
        local object=$(echo "$line" | jq -r '.Object.K8sObject.Name // "unknown"' 2>/dev/null)
        local message=$(echo "$line" | jq -r '.Diagnostic.Message // "check failed"' 2>/dev/null)

        if [ -z "$check" ]; then
            continue
        fi

        log_warn "KubeLinter: $check on $object - $message"
        VALIDATION_ERRORS+=("kube-linter|$check on $object - $message")
    done < <(jq -c '.Reports[]?' "$output_file" 2>/dev/null || true)
}

generate_error_report() {
    local errors_json="[]"
    for err in "${VALIDATION_ERRORS[@]}"; do
        local tool="${err%%|*}"
        local message="${err#*|}"
        errors_json=$(echo "$errors_json" | jq --arg t "$tool" --arg m "$message" '. += [{"tool": $t, "message": $m}]')
    done

    cat > /tmp/validation-report.json <<EOF
{
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "app_name": "${ARGOCD_APP_NAME:-unknown}",
    "source_repo": "${ARGOCD_APP_SOURCE_REPO_URL:-unknown}",
    "source_path": "${ARGOCD_APP_SOURCE_PATH:-unknown}",
    "revision": "${ARGOCD_APP_REVISION:-unknown}",
    "errors": $errors_json
}
EOF
}

output_report_configmap() {
    local report_file="/tmp/validation-report.json"
    local namespace="${ARGOCD_APP_NAMESPACE:-default}"

    if [ ! -f "$report_file" ]; then
        log_warn "No validation report found at $report_file"
        return
    fi

    local report_json
    report_json=$(cat "$report_file")

    cat <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: manifest-validator-report
  namespace: $namespace
  labels:
    manifest-validator/report: "true"
data:
  report.json: |
$(echo "$report_json" | sed 's/^/    /')
EOF
}

export -f log_info log_warn log_error
export -f collect_kubeconform_errors collect_pluto_errors collect_kubelinter_errors
export -f generate_error_report output_report_configmap
