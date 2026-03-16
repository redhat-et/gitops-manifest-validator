---
name: mapping-kubernetes-compliance-controls
description: >
  Use when validating Kubernetes manifests against compliance frameworks
  (CIS Kubernetes Benchmark, Pod Security Standards, PCI-DSS, HIPAA, SOC2, NIST).
  Use when generating compliance reports, audit evidence, or mapping controls to
  regulatory requirements. Use when preparing for audits, assessing compliance gaps,
  or explaining why specific security controls are required by regulation. Use when
  determining Pod Security Standards levels (Restricted/Baseline/Privileged).
allowed-tools: Read, Glob, Grep
---

# Mapping Kubernetes Compliance Controls

## Overview

**Core principle: Every security control MUST be mapped to specific compliance framework control IDs. Generic "security best practice" statements are NOT audit-ready.**

Auditors require evidence mapped to numbered controls. You MUST reference specific control IDs (CIS 5.2.3, PCI-DSS 6.3.2, NIST SP 800-190 Section 4.1) rather than vague statements like "follow security best practices."

## Before Analysis

| Source | Gather |
|--------|--------|
| **Manifests** | All YAML files in scope, namespace structure, labels indicating scope |
| **Conversation** | Target compliance framework(s), environment type (CDE, production, etc.) |
| **Skill References** | Control mappings from `references/` files |
| **Labels/Annotations** | `pci-scope`, `data-classification`, `compliance-*` labels |

Determine which frameworks apply before starting analysis. Ask the user if unclear.

## Compliance Analysis Workflow

### Step 1: Determine Applicable Frameworks

Check manifest labels and namespace for scope indicators:
- `pci-scope: in-scope` -> PCI-DSS analysis required
- `data-classification: phi` -> HIPAA analysis required
- Namespace `cde` or `cardholder` -> PCI-DSS scope
- Any production workload -> CIS Benchmark + PSS analysis

### Step 2: Run CIS Benchmark Mapping

Map EVERY container security field to CIS Kubernetes Benchmark v1.8 controls. See `references/cis-benchmark-mapping.md` for the complete control-to-field mapping.

For each control, report:
```
CIS [control-id]: [control-title]
  Status: PASS | FAIL | N/A
  Evidence: [specific field value from manifest]
  Resource: [kind/name]
  Remediation: [if FAIL, specific fix]
```

### Step 3: Determine Pod Security Standards Level

For EVERY Pod spec, determine the PSS level. See `references/pss-validation-rules.md` for the exact field checks per level.

Classification rules (evaluate in order):
1. If ANY Baseline check fails -> **Privileged** (no restrictions, only for system workloads)
2. If ALL Baseline checks pass but ANY Restricted check fails -> **Baseline**
3. If ALL Restricted checks pass -> **Restricted**

Report the LOWEST qualifying level and list which specific fields prevent a higher level.

**Multi-container Pods**: Evaluate EVERY container (containers, initContainers, ephemeralContainers) independently. The Pod's level is determined by its WORST container.

**Default values matter**: Fields like `allowPrivilegeEscalation` default to `true` when absent. Treat absent fields as their default values, not as "not applicable."

### Step 4: Framework-Specific Gap Analysis

For each applicable framework, check for BOTH misconfigured AND absent resources:
- Missing NetworkPolicy = FAIL for network segmentation controls
- Missing ServiceAccount = using `default` SA = FAIL for access control
- Missing resource limits = FAIL for NIST 4.3.4
- Absent fields with insecure defaults = FAIL (not N/A)

For each applicable framework (PCI-DSS, HIPAA, SOC2, NIST), map manifest controls to framework requirements. See `references/compliance-frameworks.md` for the mapping tables.

### Step 5: Generate Compliance Report

Output format:

```
COMPLIANCE REPORT
=================
Scope: [namespaces/resources analyzed]
Frameworks: [CIS, PSS, PCI-DSS, etc.]
Date: [analysis date]

SUMMARY
-------
Total Controls Evaluated: N
  PASS: N
  FAIL: N
  N/A: N
  PARTIAL: N

CIS KUBERNETES BENCHMARK v1.8
------------------------------
[control-id] [title] ........... [PASS/FAIL]
  Evidence: [field=value]
  Resource: [kind/name in namespace]

POD SECURITY STANDARDS
----------------------
[resource]: [Restricted/Baseline/Privileged]
  Blocking fields: [list of fields preventing higher level]

[FRAMEWORK] GAP ANALYSIS
-------------------------
[requirement-id] [title] ........... [PASS/FAIL/PARTIAL]
  Manifest evidence: [what was found]
  Gap: [what is missing]
  Remediation: [specific fix]
  Priority: [Critical/High/Medium/Low]

REMEDIATION PLAN (prioritized)
------------------------------
1. [Critical] [requirement-id]: [action]
2. [High] [requirement-id]: [action]
...
```

## Critical Rules

1. **Absent != N/A**: A missing security field with an insecure default is a FAIL, not "not applicable." Example: no `allowPrivilegeEscalation` field means it defaults to `true` = CIS 5.2.5 FAIL.
2. **Missing resources are gaps**: No NetworkPolicy in a PCI-DSS namespace is a FAIL for Req 1.2.1, not "out of scope."
3. **Every container matters**: Init containers, sidecars, and ephemeral containers must all pass the same controls. One non-compliant init container fails the entire Pod.
4. **Scope labels determine analysis depth**: A Pod labeled `pci-scope: in-scope` triggers full PCI-DSS analysis. A Pod without scope labels still gets CIS + PSS analysis.
5. **Evidence must be quotable**: Every PASS/FAIL must cite the specific manifest field and value. "Appears secure" is not evidence.

## Red Flags - STOP and Escalate

- Secrets/credentials in plain text env vars (PCI-DSS 3.4, 8.3.1 violation)
- Privileged containers in cardholder data environment
- No NetworkPolicy in PCI-DSS scoped namespace
- `hostNetwork: true` on CDE workloads
- `latest` or mutable image tags in regulated environments
- Missing seccompProfile on Restricted-required workloads

## Common Rationalizations to Reject

| Excuse | Reality |
|--------|---------|
| "General security is enough for compliance" | Auditors need specific control IDs mapped to evidence. CIS 5.2.3 is not "run as non-root." |
| "We'll address compliance later" | Controls are required for certification. Deploy without them and you fail the audit. |
| "This is a dev environment, compliance doesn't apply" | If dev handles real cardholder data or PHI, it IS in scope. Check data classification. |
| "The cluster has admission controllers" | Manifest review is defense-in-depth. Admission controllers can be misconfigured or bypassed. |
| "We passed the audit last year" | Controls must be continuously maintained. A passing manifest last year may fail today. |
| "This control is compensating" | Compensating controls require documented justification. State the specific alternative. |
| "Only the network layer matters for PCI" | PCI-DSS 4.0 requires workload-level controls (Req 2.2, 6.3, 8.3). |
| "seccompProfile is optional" | PSS Restricted REQUIRES seccompProfile. Without it, you cannot claim Restricted level. |
| "Pod Security Admission handles this" | PSA enforces at admission time. Compliance mapping documents evidence for auditors regardless of enforcement. |

## Reference Files

| File | Content |
|------|---------|
| `references/cis-benchmark-mapping.md` | CIS Kubernetes Benchmark v1.8 controls 5.2.1-5.2.9 mapped to manifest fields |
| `references/pss-validation-rules.md` | Pod Security Standards Restricted/Baseline/Privileged field checks |
| `references/compliance-frameworks.md` | PCI-DSS 4.0, HIPAA, SOC2, NIST SP 800-190 control mappings |
