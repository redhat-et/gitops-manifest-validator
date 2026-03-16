# Kubernetes Label Selector Patterns

## How Selectors Work

A selector `{app: frontend, tier: web}` matches Pods that have BOTH labels with EXACT values. Missing any label = no match.

## Common Mismatch Patterns

### 1. Naming Inconsistency
```yaml
# Deployment labels
app: frontend

# Service selector (BROKEN - different value)
app: web-frontend
```
**Fix**: Use identical label values. Decide on one naming convention.

### 2. Extra Labels in Selector
```yaml
# Pod labels
app: api

# Service selector (BROKEN - Pod missing 'version' label)
app: api
version: v2
```
**Fix**: Service selector should be a SUBSET of Pod labels, not a superset.

### 3. Label Key Mismatch
```yaml
# Pod uses standard labels
app.kubernetes.io/name: frontend

# Service uses simple labels (BROKEN - different key)
app: frontend
```
**Fix**: Ensure selector key matches exactly what's on the Pod.

### 4. Template vs Metadata Labels
```yaml
# Deployment metadata (NOT what pods get)
metadata:
  labels:
    app: frontend

# Pod template (THIS is what pods actually get)
spec:
  template:
    metadata:
      labels:
        app: frontend-app  # Different from Deployment metadata!
```
**Rule**: Service selectors match `spec.template.metadata.labels`, NOT `metadata.labels` on the Deployment itself.

### 5. Namespace Mismatch
```yaml
# Service in namespace "production"
# But target Deployment is in namespace "staging"
```
Service selectors only match Pods in the SAME namespace. Cross-namespace service discovery requires ExternalName or specific DNS.

## Recommended Label Schema

Follow the Kubernetes recommended labels for consistency:

```yaml
metadata:
  labels:
    app.kubernetes.io/name: frontend        # Application name
    app.kubernetes.io/instance: frontend-prod # Instance identifier
    app.kubernetes.io/version: "1.2.3"      # Version
    app.kubernetes.io/component: web         # Component within architecture
    app.kubernetes.io/part-of: my-app        # Higher-level application
    app.kubernetes.io/managed-by: helm       # Tool managing the resource
```

For Service selectors, use a minimal stable subset:
```yaml
spec:
  selector:
    app.kubernetes.io/name: frontend
    app.kubernetes.io/instance: frontend-prod
```

## Verification Steps

For each Service in a manifest set:

1. Read `spec.selector` - note every key-value pair
2. Find all Deployments/StatefulSets/DaemonSets in the SAME namespace
3. Check `spec.template.metadata.labels` (NOT `metadata.labels`)
4. Verify EVERY selector key-value pair exists in template labels
5. If zero matches found: **CRITICAL ERROR** - Service will have no endpoints

For each NetworkPolicy:

1. Read `spec.podSelector.matchLabels`
2. Find all Pods (via Deployment templates) in the SAME namespace
3. Verify at least one Pod matches ALL selector labels
4. If zero matches: Policy applies to no Pods (may be intentional for deny-all, but verify)
