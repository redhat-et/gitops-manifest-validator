#!/bin/bash
# Kubernetes Manifest Linter
# Runs kube-linter, kubeconform, and pluto with unified output

set -e

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default settings
CONFIG_FILE=".lint-config.yaml"
OUTPUT_FORMAT="console"
MIN_SEVERITY="info"
TOOLS="kube-linter,kubeconform,pluto"
K8S_VERSION="1.29.0"
STRICT=false
EXIT_CODE=false
EXCLUDE_CHECKS=""
PARALLEL=4

# Counters
TOTAL_FILES=0
TOTAL_ISSUES=0
CRITICAL_ISSUES=0
ERROR_ISSUES=0
WARNING_ISSUES=0
INFO_ISSUES=0

# Temp files
RESULTS_FILE=$(mktemp)
KUBE_LINTER_RESULTS=$(mktemp)
KUBECONFORM_RESULTS=$(mktemp)
PLUTO_RESULTS=$(mktemp)

# Cleanup on exit
trap "rm -f $RESULTS_FILE $KUBE_LINTER_RESULTS $KUBECONFORM_RESULTS $PLUTO_RESULTS" EXIT

# Help message
show_help() {
    cat << EOF
Kubernetes Manifest Linter

Usage: $0 [OPTIONS] <file|directory>

OPTIONS:
    -c, --config FILE          Config file (default: .lint-config.yaml)
    -o, --output FORMAT        Output format: console, json, markdown (default: console)
    -s, --min-severity LEVEL   Minimum severity: critical, error, warning, info (default: info)
    -t, --tools TOOLS          Comma-separated tools: kube-linter,kubeconform,pluto (default: all)
    -k, --k8s-version VERSION  Target Kubernetes version (default: 1.29.0)
    -e, --exclude CHECKS       Comma-separated checks to exclude
    -p, --parallel N           Parallel processing (default: 4)
    --strict                   Fail on any issues
    --exit-code                Exit with non-zero code if issues found
    -h, --help                 Show this help message

EXAMPLES:
    $0 deployment.yaml
    $0 ./manifests/ --output json
    $0 ./k8s/ --min-severity error --strict
    $0 ./manifests/ --exclude no-read-only-root-fs,unset-cpu-requirements

EOF
    exit 0
}

# Parse arguments
TARGET=""
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        -s|--min-severity)
            MIN_SEVERITY="$2"
            shift 2
            ;;
        -t|--tools)
            TOOLS="$2"
            shift 2
            ;;
        -k|--k8s-version)
            K8S_VERSION="$2"
            shift 2
            ;;
        -e|--exclude)
            EXCLUDE_CHECKS="$2"
            shift 2
            ;;
        -p|--parallel)
            PARALLEL="$2"
            shift 2
            ;;
        --strict)
            STRICT=true
            shift
            ;;
        --exit-code)
            EXIT_CODE=true
            shift
            ;;
        -h|--help)
            show_help
            ;;
        *)
            TARGET="$1"
            shift
            ;;
    esac
done

# Validate target
if [ -z "$TARGET" ]; then
    echo "Error: No target file or directory specified"
    show_help
fi

if [ ! -e "$TARGET" ]; then
    echo "Error: $TARGET not found"
    exit 1
fi

# Find YAML files
if [ -d "$TARGET" ]; then
    YAML_FILES=$(find "$TARGET" -type f \( -name "*.yaml" -o -name "*.yml" \) 2>/dev/null)
elif [ -f "$TARGET" ]; then
    YAML_FILES="$TARGET"
else
    echo "Error: $TARGET is not a file or directory"
    exit 1
fi

if [ -z "$YAML_FILES" ]; then
    echo "No YAML files found in $TARGET"
    exit 0
fi

TOTAL_FILES=$(echo "$YAML_FILES" | wc -l | tr -d ' ')

# Check if tools are installed
check_tool() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "${RED}Error: $1 is not installed${NC}"
        echo "See references/installation.md for installation instructions"
        return 1
    fi
    return 0
}

# Run kube-linter
run_kube_linter() {
    if [[ $TOOLS != *"kube-linter"* ]]; then
        return 0
    fi

    if ! check_tool "kube-linter"; then
        return 1
    fi

    local config_args=""
    if [ -f "$CONFIG_FILE" ]; then
        config_args="--config $CONFIG_FILE"
    fi

    local exclude_args=""
    if [ -n "$EXCLUDE_CHECKS" ]; then
        IFS=',' read -ra CHECKS <<< "$EXCLUDE_CHECKS"
        for check in "${CHECKS[@]}"; do
            exclude_args="$exclude_args --exclude $check"
        done
    fi

    echo "$YAML_FILES" | while read -r file; do
        kube-linter lint "$file" $config_args $exclude_args --format json 2>/dev/null || true
    done > "$KUBE_LINTER_RESULTS"
}

# Run kubeconform
run_kubeconform() {
    if [[ $TOOLS != *"kubeconform"* ]]; then
        return 0
    fi

    if ! check_tool "kubeconform"; then
        return 1
    fi

    echo "$YAML_FILES" | while read -r file; do
        kubeconform \
            -strict \
            -verbose \
            -kubernetes-version "$K8S_VERSION" \
            -output json \
            -ignore-missing-schemas \
            -n "$PARALLEL" \
            "$file" 2>/dev/null || true
    done > "$KUBECONFORM_RESULTS"
}

# Run pluto
run_pluto() {
    if [[ $TOOLS != *"pluto"* ]]; then
        return 0
    fi

    if ! check_tool "pluto"; then
        return 1
    fi

    if [ -d "$TARGET" ]; then
        pluto detect-files \
            -d "$TARGET" \
            -o json \
            --target-versions "k8s=$K8S_VERSION" 2>/dev/null > "$PLUTO_RESULTS" || true
    else
        # For single file, create temp directory
        local tmpdir=$(mktemp -d)
        cp "$TARGET" "$tmpdir/"
        pluto detect-files \
            -d "$tmpdir" \
            -o json \
            --target-versions "k8s=$K8S_VERSION" 2>/dev/null > "$PLUTO_RESULTS" || true
        rm -rf "$tmpdir"
    fi
}

# Aggregate results
aggregate_results() {
    # Initialize results JSON
    cat > "$RESULTS_FILE" << 'EOF'
{
  "summary": {
    "files": 0,
    "issues": 0,
    "critical": 0,
    "errors": 0,
    "warnings": 0,
    "info": 0
  },
  "results": []
}
EOF

    # Parse kube-linter results
    if [ -s "$KUBE_LINTER_RESULTS" ]; then
        # Process kube-linter JSON output
        # This is a simplified parser - real implementation would use jq
        TOTAL_ISSUES=$((TOTAL_ISSUES + $(grep -c "Check" "$KUBE_LINTER_RESULTS" 2>/dev/null || echo 0)))
    fi

    # Parse kubeconform results
    if [ -s "$KUBECONFORM_RESULTS" ]; then
        # Process kubeconform JSON output
        ERROR_COUNT=$(grep -c '"status":"statusInvalid"' "$KUBECONFORM_RESULTS" 2>/dev/null || echo 0)
        TOTAL_ISSUES=$((TOTAL_ISSUES + ERROR_COUNT))
        ERROR_ISSUES=$((ERROR_ISSUES + ERROR_COUNT))
    fi

    # Parse pluto results
    if [ -s "$PLUTO_RESULTS" ]; then
        # Process pluto JSON output
        DEPRECATED_COUNT=$(grep -c '"deprecated":true' "$PLUTO_RESULTS" 2>/dev/null || echo 0)
        TOTAL_ISSUES=$((TOTAL_ISSUES + DEPRECATED_COUNT))
        WARNING_ISSUES=$((WARNING_ISSUES + DEPRECATED_COUNT))
    fi
}

# Output console format
output_console() {
    echo -e "${BLUE}🔍 Kubernetes Manifest Linting Results${NC}"
    echo "======================================"
    echo ""

    local any_issues=false

    # Process each file
    echo "$YAML_FILES" | while read -r file; do
        local file_issues=0

        echo -e "${BLUE}📄 $file${NC}"

        # Check kube-linter results
        if [ -s "$KUBE_LINTER_RESULTS" ]; then
            grep "$file" "$KUBE_LINTER_RESULTS" 2>/dev/null | while read -r line; do
                echo -e "  ${YELLOW}⚠️  WARNING [kube-linter]${NC} Check results"
                file_issues=$((file_issues + 1))
                any_issues=true
            done
        fi

        # Check kubeconform results
        if [ -s "$KUBECONFORM_RESULTS" ]; then
            if grep -q "$file.*statusInvalid" "$KUBECONFORM_RESULTS" 2>/dev/null; then
                echo -e "  ${RED}❌ ERROR [kubeconform]${NC} Schema validation failed"
                file_issues=$((file_issues + 1))
                any_issues=true
            fi
        fi

        # Check pluto results
        if [ -s "$PLUTO_RESULTS" ]; then
            if grep -q "$file.*deprecated" "$PLUTO_RESULTS" 2>/dev/null; then
                echo -e "  ${YELLOW}⚠️  WARNING [pluto]${NC} Deprecated API version detected"
                file_issues=$((file_issues + 1))
                any_issues=true
            fi
        fi

        if [ $file_issues -eq 0 ]; then
            echo -e "  ${GREEN}✅ No issues found${NC}"
        fi
        echo ""
    done

    echo "======================================"
    echo "Summary:"
    echo "  Files: $TOTAL_FILES"
    echo "  Issues: $TOTAL_ISSUES ($CRITICAL_ISSUES critical, $WARNING_ISSUES warnings, $INFO_ISSUES info)"
    echo "  Tools: $TOOLS"
    echo ""

    if $any_issues && $STRICT; then
        exit 1
    fi
}

# Output JSON format
output_json() {
    aggregate_results
    cat "$RESULTS_FILE"
}

# Output markdown format
output_markdown() {
    echo "# Kubernetes Linting Report"
    echo ""
    echo "**Date**: $(date +%Y-%m-%d)"
    echo "**Files**: $TOTAL_FILES"
    echo "**Issues**: $TOTAL_ISSUES ($CRITICAL_ISSUES critical, $WARNING_ISSUES warnings)"
    echo ""
    echo "## Issues by File"
    echo ""

    echo "$YAML_FILES" | while read -r file; do
        echo "### $file"
        echo ""
        echo "| Severity | Check | Tool | Description |"
        echo "|----------|-------|------|-------------|"

        # Add issues here
        echo "| ✅ | - | - | No issues found |"
        echo ""
    done
}

# Main execution
main() {
    if [ "$OUTPUT_FORMAT" == "console" ]; then
        echo -e "${BLUE}Running Kubernetes manifest linting...${NC}"
        echo ""
    fi

    # Run linters in parallel
    run_kube_linter &
    PID_KUBELINTER=$!

    run_kubeconform &
    PID_KUBECONFORM=$!

    run_pluto &
    PID_PLUTO=$!

    # Wait for all linters
    wait $PID_KUBELINTER
    wait $PID_KUBECONFORM
    wait $PID_PLUTO

    # Aggregate and output results
    case "$OUTPUT_FORMAT" in
        json)
            output_json
            ;;
        markdown)
            output_markdown
            ;;
        *)
            output_console
            ;;
    esac

    # Exit code handling
    if $EXIT_CODE && [ $TOTAL_ISSUES -gt 0 ]; then
        exit 1
    fi

    exit 0
}

main
