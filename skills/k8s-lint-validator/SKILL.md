---
name: k8s-lint-validator
description: |
  Runs comprehensive Kubernetes manifest linting with kube-linter, kubeconform, and pluto.
  This skill should be used when the user wants to validate K8s manifests. Validations can include 
  best practices, schema correctness, deprecated APIs, and security issues. Aggregates results from 
  multiple linters into a unified, filterable output format. Use for pre-commit validation,
  CI/CD integration, or comprehensive manifest audits.
allowed-tools: Bash, Read, Write, Glob
---

# Kubernetes Lint Validator

Comprehensive Kubernetes manifest linting with unified output from multiple tools.

## Before Implementation

Gather context to ensure successful linting:

| Source | Gather |
|--------|--------|
| **Codebase** | Manifest files, existing linter configs, CI/CD setup |
| **Conversation** | User's validation needs, severity thresholds, specific concerns |
| **Skill References** | Tool configurations, check definitions from `references/` |
| **User Guidelines** | Project-specific standards, exemptions, compliance requirements |

Ensure all required context is gathered before running linters.
Only ask user for THEIR specific requirements (domain expertise is in this skill).

---

## What This Skill Does

- ✅ Runs **kube-linter** (best practices & security)
- ✅ Runs **kubeconform** (schema validation)
- ✅ Runs **pluto** (deprecated API detection)
- ✅ Aggregates results into unified output format
- ✅ Filters issues by severity, tool, or check name
- ✅ Provides actionable fix suggestions
- ✅ Configurable check inclusion/exclusion
- ✅ CI/CD integration ready

## What This Skill Does NOT Do

- ❌ Auto-fix manifest issues (provides suggestions only)
- ❌ Deploy or apply manifests
- ❌ Install linting tools (requires pre-installation)
- ❌ Validate runtime cluster state
- ❌ Replace policy enforcement (OPA, Kyverno)

---

## Quick Start

### Prerequisites Check

```bash
# Verify tools are installed
./scripts/check-dependencies.sh
```

**Required tools**:
- **kube-linter** v0.6.0+
- **kubeconform** v0.6.0+
- **pluto** v5.0.0+

See `references/installation.md` for installation instructions.

### Basic Usage

```bash
# Lint single file
./scripts/lint-manifests.sh deployment.yaml

# Lint directory
./scripts/lint-manifests.sh ./manifests/

# Lint with custom config
./scripts/lint-manifests.sh ./manifests/ --config .lint-config.yaml
```

---

## Linting Workflow

### Step 1: Discover Manifests

Find all Kubernetes YAML files to lint:

```bash
# Using glob patterns
find . -type f \( -name "*.yaml" -o -name "*.yml" \) \
  -not -path "*/node_modules/*" \
  -not -path "*/.git/*"
```

Or use Glob tool with pattern: `**/*.yaml`

### Step 2: Run Linters

The skill runs three linters in parallel:

**kube-linter** - Best Practices & Security
```bash
kube-linter lint \
  --config .kube-linter.yaml \
  --format json \
  <manifest-file>
```

**kubeconform** - Schema Validation
```bash
kubeconform \
  -strict \
  -verbose \
  -output json \
  -ignore-missing-schemas \
  <manifest-file>
```

**pluto** - Deprecated APIs
```bash
pluto detect-files \
  -d <directory> \
  -o json \
  --target-versions k8s=v1.29.0
```

### Step 3: Aggregate Results

All results are aggregated into unified format:

```json
{
  "file": "deployment.yaml",
  "issues": [
    {
      "name": "no-read-only-root-fs",
      "tool": "kube-linter",
      "severity": "warning",
      "line": 15,
      "description": "Container does not have a read-only root filesystem",
      "why": "Writable root filesystem increases attack surface and risk of container escape",
      "fix": "Add securityContext.readOnlyRootFilesystem: true to container spec"
    }
  ]
}
```

### Step 4: Filter & Format

Filter results by:
- **Severity**: critical, error, warning, info
- **Tool**: kube-linter, kubeconform, pluto
- **Check name**: specific check IDs

Output formats:
- **Console** (default): Human-readable colored output
- **JSON**: Machine-parseable for CI/CD
- **Markdown**: For reports and documentation

---

## Configuration

### Default Configuration

Create `.lint-config.yaml` in your project root:

```yaml
# Linting configuration
version: 1

# Global settings
strict: true              # Fail on any issues
ignore-missing-schemas: true

# Tool-specific settings
kube-linter:
  enabled: true
  add-all-built-in: true  # Enable all checks
  exclude:
    # Exclude specific checks
    # - no-extensions-v1beta
  ignore-paths:
    - "**/test/**"
    - "**/examples/**"

kubeconform:
  enabled: true
  kubernetes-version: "1.29.0"
  strict: true
  schema-locations:
    - default
    # Add custom CRD schemas
    # - 'https://example.com/schemas/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'

pluto:
  enabled: true
  target-versions:
    k8s: "v1.29.0"
  ignore-deprecations: false
  ignore-removals: false

# Output settings
output:
  format: console       # console, json, markdown
  show-passed: false    # Only show issues, not passed checks
  group-by: file        # file, tool, severity
```

### Check-Specific Configuration

**kube-linter** - See `references/kube-linter-checks.md` for all available checks.

Common checks to exclude:
```yaml
kube-linter:
  exclude:
    - no-extensions-v1beta        # If you need older APIs
    - unset-cpu-requirements       # If not enforcing CPU limits
    - unset-memory-requirements    # If not enforcing memory limits
```

**kubeconform** - Customize schema validation:
```yaml
kubeconform:
  schema-locations:
    - default
    - 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
```

**pluto** - Set target versions:
```yaml
pluto:
  target-versions:
    k8s: "v1.29.0"          # Target Kubernetes version
    cert-manager: "v1.12.0"  # Other components
```

---

## Output Format

### Console Output

```
🔍 Kubernetes Manifest Linting Results
======================================

📄 deployment.yaml
  ❌ CRITICAL [kube-linter] privileged-container (line 18)
     Why: Privileged containers have full host access
     Fix: Remove 'privileged: true' or set to false

  ⚠️  WARNING [kube-linter] no-read-only-root-fs (line 15)
     Why: Writable root filesystem increases attack surface
     Fix: Add securityContext.readOnlyRootFilesystem: true

  ⚠️  WARNING [pluto] deprecated-api
     Why: apps/v1beta1 Deployment deprecated in v1.16, removed in v1.25
     Fix: Update apiVersion to apps/v1

  ℹ️  INFO [kubeconform] schema-validation
     Resource validated against Kubernetes v1.29.0 schema

📄 service.yaml
  ✅ No issues found

======================================
Summary:
  Files: 2
  Issues: 3 (1 critical, 2 warnings, 0 info)
  Tools: kube-linter, kubeconform, pluto
```

### JSON Output

```json
{
  "summary": {
    "files": 2,
    "issues": 3,
    "critical": 1,
    "errors": 0,
    "warnings": 2,
    "info": 0
  },
  "results": [
    {
      "file": "deployment.yaml",
      "issues": [
        {
          "name": "privileged-container",
          "tool": "kube-linter",
          "severity": "critical",
          "line": 18,
          "column": 10,
          "description": "Container runs in privileged mode",
          "why": "Privileged containers have full host access and can escape container boundaries",
          "fix": "Remove 'privileged: true' from securityContext or set to false",
          "resource": {
            "kind": "Deployment",
            "name": "web-app",
            "namespace": "default"
          }
        }
      ]
    }
  ]
}
```

### Markdown Output

For documentation or CI/CD reports:

```markdown
# Kubernetes Linting Report

**Date**: 2026-02-26
**Files**: 2
**Issues**: 3 (1 critical, 2 warnings)

## Issues by File

### deployment.yaml

| Severity | Check | Tool | Line | Description |
|----------|-------|------|------|-------------|
| ❌ CRITICAL | privileged-container | kube-linter | 18 | Container runs in privileged mode |
| ⚠️ WARNING | no-read-only-root-fs | kube-linter | 15 | Container does not have read-only root filesystem |
| ⚠️ WARNING | deprecated-api | pluto | - | apps/v1beta1 deprecated in v1.16 |

### service.yaml

✅ No issues found
```

---

## CI/CD Integration

### GitHub Actions

```yaml
name: Lint Kubernetes Manifests

on:
  pull_request:
    paths:
      - '**.yaml'
      - '**.yml'

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Tools
        run: |
          # Install kube-linter
          curl -L https://github.com/stackrox/kube-linter/releases/latest/download/kube-linter-linux -o kube-linter
          chmod +x kube-linter && sudo mv kube-linter /usr/local/bin/

          # Install kubeconform
          curl -L https://github.com/yannh/kubeconform/releases/latest/download/kubeconform-linux-amd64.tar.gz | tar xz
          chmod +x kubeconform && sudo mv kubeconform /usr/local/bin/

          # Install pluto
          curl -L https://github.com/FairwindsOps/pluto/releases/latest/download/pluto_*_linux_amd64.tar.gz | tar xz
          chmod +x pluto && sudo mv pluto /usr/local/bin/

      - name: Run Linting
        run: |
          ./scripts/lint-manifests.sh ./manifests/ --output json > results.json

      - name: Check Results
        run: |
          # Fail if critical issues found
          if [ $(jq '.summary.critical' results.json) -gt 0 ]; then
            echo "❌ Critical issues found"
            jq '.results' results.json
            exit 1
          fi
```

### GitLab CI

```yaml
lint-manifests:
  stage: test
  image: alpine:latest
  before_script:
    - apk add --no-cache curl jq bash
    # Install tools (similar to GitHub Actions)
  script:
    - ./scripts/lint-manifests.sh ./manifests/ --output json > results.json
    - jq '.summary' results.json
  artifacts:
    reports:
      junit: results.json
    when: always
```

### Pre-commit Hook

```bash
#!/bin/bash
# .git/hooks/pre-commit

# Find staged YAML files
STAGED_YAML=$(git diff --cached --name-only --diff-filter=ACM | grep -E '\.(yaml|yml)$')

if [ -z "$STAGED_YAML" ]; then
  exit 0
fi

# Run linting
./scripts/lint-manifests.sh $STAGED_YAML --strict

if [ $? -ne 0 ]; then
  echo "❌ Linting failed. Fix issues before committing."
  exit 1
fi

exit 0
```

---

## Advanced Usage

### Severity Filtering

```bash
# Only show critical and error issues
./scripts/lint-manifests.sh ./manifests/ --min-severity error

# Show all issues including info
./scripts/lint-manifests.sh ./manifests/ --min-severity info
```

### Tool Selection

```bash
# Run only kube-linter
./scripts/lint-manifests.sh ./manifests/ --tools kube-linter

# Run kubeconform and pluto only
./scripts/lint-manifests.sh ./manifests/ --tools kubeconform,pluto
```

### Custom Target Versions

```bash
# Check against specific Kubernetes version
./scripts/lint-manifests.sh ./manifests/ --k8s-version 1.28.0
```

### Ignore Specific Issues

```bash
# Via command line
./scripts/lint-manifests.sh ./manifests/ \
  --exclude no-read-only-root-fs,unset-cpu-requirements

# Via annotation in manifest
metadata:
  annotations:
    ignore-check.kube-linter.io/no-read-only-root-fs: "Legacy app requirement"
```

---

## Troubleshooting

### Tools Not Found

```bash
# Check which tools are missing
./scripts/check-dependencies.sh

# See installation instructions
cat references/installation.md
```

### Schema Validation Failures

```
Error: could not find schema for CustomResourceDefinition
```

**Solution**: Add custom schema location to config:
```yaml
kubeconform:
  schema-locations:
    - default
    - 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
```

Or use `--ignore-missing-schemas` flag.

### False Positives

**Exclude specific checks** via config:
```yaml
kube-linter:
  exclude:
    - check-name
```

**Or use annotations** in manifests:
```yaml
metadata:
  annotations:
    ignore-check.kube-linter.io/<check-name>: "Justification here"
```

### Performance Issues

For large repos:
```bash
# Lint only changed files
git diff --name-only main...HEAD | grep '\.yaml$' | xargs ./scripts/lint-manifests.sh

# Use parallel processing
./scripts/lint-manifests.sh ./manifests/ --parallel 8
```

---

## Reference Files

| File | Content |
|------|---------|
| `references/installation.md` | Tool installation instructions for all platforms |
| `references/kube-linter-checks.md` | Complete list of kube-linter checks with examples |
| `references/kubeconform-schemas.md` | Schema validation guide and CRD support |
| `references/pluto-deprecations.md` | Kubernetes API deprecation timeline |
| `references/configuration-examples.md` | Sample configs for different use cases |

---

## Usage Examples

### Example 1: Pre-commit Validation

```bash
# Lint only staged files
STAGED=$(git diff --cached --name-only | grep '\.yaml$')
./scripts/lint-manifests.sh $STAGED --strict
```

### Example 2: CI/CD Integration

```bash
# Fail pipeline on critical issues only
./scripts/lint-manifests.sh ./k8s/ \
  --output json \
  --min-severity critical \
  --exit-code
```

### Example 3: Generate Report

```bash
# Create markdown report
./scripts/lint-manifests.sh ./manifests/ \
  --output markdown > lint-report.md
```

---

## Summary

This skill provides comprehensive Kubernetes manifest linting by:

1. **Running three industry-standard linters** in parallel
2. **Aggregating results** into unified, filterable output
3. **Providing actionable fixes** for each issue
4. **Supporting flexible configuration** for project-specific needs
5. **Integrating seamlessly** with CI/CD pipelines

Use this skill to catch errors early, enforce best practices, and maintain high-quality Kubernetes manifests.
