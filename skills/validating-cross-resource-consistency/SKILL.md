---
name: validating-cross-resource-consistency
description: >
  Use when reviewing, creating, or modifying Kubernetes manifests that contain
  multiple resources. Use when Services, Deployments, ConfigMaps, Secrets,
  RBAC resources, Ingress, Routes, or NetworkPolicies appear together.
  Use when manifests reference other resources by name, label selector, or
  service account. Use when debugging why pods aren't receiving traffic,
  why containers fail to start, or why RBAC permissions aren't working.
---

# Validating Cross-Resource Consistency

## Overview

**Core principle: Every cross-resource reference MUST resolve to an existing resource in the manifest set.**

Linters validate individual resources but cannot detect broken links between them. You MUST verify ALL cross-references. Do NOT assume referenced resources "might exist elsewhere."

## Validation Checklist

### 1. Selector Alignment

Service/NetworkPolicy/PDB `selector` must match Pod template labels (NOT Deployment metadata labels). Every label key AND value must match exactly. One mismatched character = zero Pods selected. See `references/selector-patterns.md`.

### 2. Name References

Every name reference must resolve to a resource in the manifest set. See `references/k8s-resource-references.md` for the complete field-to-resource mapping. Key references to check:
- ConfigMap/Secret names in `volumes`, `envFrom`, `env[].valueFrom`
- `serviceAccountName` -> ServiceAccount
- `imagePullSecrets` -> Secret
- Ingress/Route backend -> Service
- RoleBinding `subjects` -> ServiceAccount, `roleRef` -> Role

### 3. Port Consistency

- Service `targetPort` must match a Pod `containerPort`
- Ingress/Route port must match a Service port

### 4. Namespace Consistency

All cross-referenced resources must share a namespace (except ClusterRole/ClusterRoleBinding).

### 5. RBAC Chain

For every `serviceAccountName`: ServiceAccount must exist, RoleBinding must bind it, Role must exist and grant needed permissions.

## Report Format

```
CROSS-RESOURCE INCONSISTENCY:
  Source: [kind/name] field [field path]
  References: [target kind/name]
  Problem: [mismatch, missing, wrong namespace]
  Impact: [runtime failure]
  Fix: [specific correction]
```

## Red Flags - STOP and Investigate

- Selector matching zero Pods
- ConfigMap/Secret referenced but not defined
- ServiceAccount name not matching any ServiceAccount resource
- Ingress/Route pointing to non-existent Service
- Ports in Service not matching any container port

## Common Rationalizations to Reject

| Excuse | Reality |
|--------|---------|
| "ConfigMap might exist in the cluster" | Untracked dependency. Flag it. |
| "RBAC is handled by cluster admins" | If manifest has serviceAccountName, RBAC chain must be complete. |
| "The selector probably works" | Verify character by character. `web-frontend` != `frontend`. |
| "External resources are managed separately" | Flag undocumented external dependencies. |
| "Each resource looks valid individually" | Individual validity is meaningless if cross-references break. |
| "It worked in dev" | Dev has pre-existing resources. Production won't. |
| "These are Kustomize bases, overlays add the rest" | Validate what's present. Flag missing resources with note about expected overlay. |
| "Helm templates will resolve this" | If reviewing rendered manifests, all references must resolve. If templates, note unresolvable refs. |
| "Other manifests exist in another directory" | Validate the set you have. Flag dependencies on external files explicitly. |

## Reference Files

| File | Content |
|------|---------|
| `references/k8s-resource-references.md` | Complete cross-reference field mapping |
| `references/selector-patterns.md` | Label selector patterns and common mismatches |
