---
name: k8s-manifest-reviewer
description: |
  Reviews deployed Kubernetes resources in live clusters for optimization opportunities.
  This skill should be used when they user wants to review manifests and have suggestions offered.  
  Suggestions can inculde security improvements, performance optimization, cost reduction, or general health checks. 
  Uses kubectl to inspect live resources and provides actionable recommendations based on official
  Kubernetes documentation and production best practices.
allowed-tools: Bash, Read, Grep, Glob
---

# Kubernetes Manifest Reviewer

Analyze deployed Kubernetes resources and provide actionable improvement recommendations.

## Before Implementation

Gather context to ensure accurate analysis:

| Source | Gather |
|--------|--------|
| **Cluster State** | Current deployed resources, resource usage, cluster version |
| **Conversation** | User's specific concerns, target namespaces, resource types to review |
| **Skill References** | Official K8s patterns from `references/` (security, optimization, best practices) |
| **User Guidelines** | Organization policies, compliance requirements, constraints |

Ensure all required context is gathered before analyzing resources.
Only ask user for THEIR specific requirements (domain expertise is in this skill).

---

## What This Skill Does

- ✅ Inspects live/deployed Kubernetes resources using kubectl
- ✅ Analyzes resource usage vs requests/limits
- ✅ Reviews security compliance (Pod Security Standards)
- ✅ Evaluates health probe configurations
- ✅ Identifies cost optimization opportunities
- ✅ Checks autoscaling configurations
- ✅ Validates deployment strategies and patterns
- ✅ Compares desired state vs actual state
- ✅ Provides actionable, priority-ranked recommendations

## What This Skill Does NOT Do

- ❌ Apply changes to running clusters
- ❌ Validate pre-deployment YAML files (use k8s-manifest-analyzer instead)
- ❌ Monitor real-time cluster metrics (use observability tools)
- ❌ Replace policy enforcement (OPA, Kyverno)
- ❌ Perform security scanning of container images

---

## Quick Review Workflow

### Step 1: Verify Cluster Access

```bash
# Test kubectl connectivity
kubectl cluster-info

# Check current context
kubectl config current-context

# Verify API server version
kubectl version --short
```

### Step 2: Discover Resources

```bash
# List all namespaces
kubectl get namespaces

# Common resource types to review
kubectl get deployments,statefulsets,daemonsets,jobs -A
kubectl get pods -A
kubectl get services,ingresses -A
kubectl get hpa -A
```

Ask user: Which namespace(s) and resource type(s) to analyze?

### Step 3: Inspect Target Resources

For each resource, gather complete information:

```bash
# Get resource YAML (desired state)
kubectl get <type> <name> -n <namespace> -o yaml

# Get detailed description (actual state + events)
kubectl describe <type> <name> -n <namespace>

# For pods: check resource usage
kubectl top pod <name> -n <namespace>

# Check logs for errors (last 50 lines)
kubectl logs <pod-name> -n <namespace> --tail=50

# Check events for issues
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
```

### Step 4: Run Analysis Checklist

Analyze resources in priority order:

#### Priority 1: Security (CRITICAL)

- [ ] Pod Security Standards compliance (see `references/security-standards.md`)
  - Privileged containers? (`securityContext.privileged`)
  - Running as root? (check `runAsNonRoot`, `runAsUser`)
  - Privilege escalation? (`allowPrivilegeEscalation`)
  - Capabilities dropped? (`capabilities.drop: ["ALL"]`)
  - Read-only filesystem? (`readOnlyRootFilesystem`)
  - Host namespaces? (`hostNetwork`, `hostPID`, `hostIPC`)
  - Seccomp profile? (`seccompProfile.type`)
- [ ] Secrets management
  - Hardcoded secrets in env vars?
  - Using secretRef/secretKeyRef?
  - Service accounts explicitly defined?
- [ ] Network policies
  - NetworkPolicy defined for namespace?
  - Ingress/egress rules configured?

#### Priority 2: Resource Management (HIGH)

- [ ] Resource requests and limits defined? (see `references/resource-optimization.md`)
  - Memory: requests = limits (prevent OOM)
  - CPU: requests defined, limits optional
  - Appropriate units? (CPU: m or cores, Memory: Mi/Gi)
- [ ] Actual usage vs requests/limits
  - Over-provisioned? (usage << requests)
  - Under-provisioned? (usage approaching limits)
  - CPU throttling? (check metrics)
- [ ] QoS class
  - BestEffort (no requests/limits) - risky in prod
  - Burstable (requests < limits) - acceptable
  - Guaranteed (requests = limits) - ideal for critical workloads

#### Priority 3: Reliability (HIGH)

- [ ] Health probes configured? (see `references/health-probes.md`)
  - Liveness probe for crash detection?
  - Readiness probe for traffic control?
  - Startup probe for slow-starting apps?
  - Appropriate timeouts and thresholds?
- [ ] High availability
  - Replica count ≥ 2 for Deployments?
  - PodDisruptionBudget defined?
  - Anti-affinity rules for distribution?
- [ ] Update strategy
  - RollingUpdate configured correctly?
  - maxSurge and maxUnavailable set?
  - revisionHistoryLimit reasonable?

#### Priority 4: Autoscaling (MEDIUM)

- [ ] HPA configured? (see `references/autoscaling-guide.md`)
  - Appropriate min/max replicas?
  - Metrics defined (CPU, memory, custom)?
  - Resource requests defined (required for HPA)?
  - Scaling behavior tuned?
- [ ] Scaling events
  - Recent scaling activity?
  - Hitting max replicas frequently?
  - Rapid oscillation?

#### Priority 5: Best Practices (LOW)

- [ ] Image management
  - Specific version tags (not `latest`)?
  - Image pull policy appropriate?
- [ ] Labels and annotations
  - Standard labels present? (`app`, `version`, `component`)
  - Annotations document purpose?
- [ ] Configuration management
  - ConfigMaps/Secrets for config (not hardcoded)?
  - Appropriate volume mounts?
- [ ] Logging
  - Stdout/stderr for logs?
  - Structured logging format?

### Step 5: Generate Prioritized Report

Structure findings as:

```markdown
## Critical Issues (Fix Immediately)
- [Resource:Name] Issue description
  - Impact: Security/availability risk
  - Current State: What was found
  - Recommendation: Specific fix with kubectl command or YAML snippet
  - Reference: Link to official K8s docs

## High Priority (Fix Soon)
- [Resource:Name] Resource optimization opportunity
  - Impact: Performance/cost improvement
  - Current State: Current configuration
  - Recommendation: Suggested change
  - Expected Benefit: Quantified improvement

## Medium Priority (Consider)
- [Resource:Name] Best practice violation
  - Impact: Operational efficiency
  - Current State: Current setup
  - Recommendation: Suggested improvement
  - Reference: Best practice documentation

## Low Priority (Nice to Have)
- [Resource:Name] Minor improvement
  - Impact: Maintainability
  - Recommendation: Suggested enhancement
```

---

## Resource Type Specific Checks

### Deployments

```bash
# Get deployment details
kubectl get deployment <name> -n <namespace> -o yaml
kubectl describe deployment <name> -n <namespace>

# Check rollout status
kubectl rollout status deployment/<name> -n <namespace>

# Check rollout history
kubectl rollout history deployment/<name> -n <namespace>

# Check pod distribution
kubectl get pods -n <namespace> -l app=<label> -o wide
```

**Analysis points**:
- Strategy: RollingUpdate vs Recreate
- maxSurge/maxUnavailable settings
- Revision history limit
- Selector matches pod labels
- Replica count for HA
- Pod template annotations

See `references/deployment-patterns.md` for detailed patterns.

### StatefulSets

```bash
# Get StatefulSet details
kubectl get statefulset <name> -n <namespace> -o yaml
kubectl describe statefulset <name> -n <namespace>

# Check PVCs
kubectl get pvc -n <namespace> -l app=<label>

# Check pod ordering
kubectl get pods -n <namespace> -l app=<label> --sort-by=.metadata.name
```

**Analysis points**:
- Headless service defined?
- VolumeClaimTemplates configured?
- Pod management policy (OrderedReady vs Parallel)
- Update strategy and partition
- terminationGracePeriodSeconds appropriate?
- Stable network identity working?

See `references/stateful-workloads.md` for patterns.

### DaemonSets

```bash
# Get DaemonSet details
kubectl get daemonset <name> -n <namespace> -o yaml

# Check which nodes have pods
kubectl get pods -n <namespace> -l app=<label> -o wide
```

**Analysis points**:
- Node selector appropriate?
- Tolerations for taints?
- Update strategy (RollingUpdate vs OnDelete)?
- Resource limits defined (critical for DaemonSets)?

### Services

```bash
# Get service details
kubectl get service <name> -n <namespace> -o yaml
kubectl describe service <name> -n <namespace>

# Check endpoints
kubectl get endpoints <name> -n <namespace>
```

**Analysis points**:
- Type appropriate? (ClusterIP, NodePort, LoadBalancer)
- Selector matches pod labels?
- Endpoints populated (pods ready)?
- Session affinity needed?
- External traffic policy?

### Ingress

```bash
# Get ingress details
kubectl get ingress <name> -n <namespace> -o yaml
kubectl describe ingress <name> -n <namespace>
```

**Analysis points**:
- Ingress class specified?
- TLS configured?
- Backend services exist?
- Annotations appropriate for ingress controller?

### HorizontalPodAutoscaler

```bash
# Get HPA details
kubectl get hpa <name> -n <namespace> -o yaml
kubectl describe hpa <name> -n <namespace>

# Check scaling events
kubectl get events -n <namespace> --field-selector involvedObject.name=<name>
```

**Analysis points**:
- Min/max replicas appropriate?
- Metrics defined and working?
- Target resource has requests defined?
- Scaling behavior configured?
- Recent scaling events?

See `references/autoscaling-guide.md` for patterns.

### ConfigMaps & Secrets

```bash
# List ConfigMaps/Secrets
kubectl get configmaps,secrets -n <namespace>

# Check which pods use them
kubectl get pods -n <namespace> -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.volumes[*].configMap.name}{"\t"}{.spec.volumes[*].secret.secretName}{"\n"}{end}'
```

**Analysis points**:
- Unused ConfigMaps/Secrets?
- Secrets base64 encoded (not plaintext)?
- Appropriate volume mounts or env references?

---

## Comparing Desired vs Actual State

### Check for Configuration Drift

```bash
# Get current resource YAML
kubectl get <type> <name> -n <namespace> -o yaml > current.yaml

# Compare with Git source (if available)
diff git-source.yaml current.yaml

# Check for manual modifications
kubectl get <type> <name> -n <namespace> -o jsonpath='{.metadata.managedFields}'
```

### Validate Actual Pod State

```bash
# Check if pods match deployment spec
kubectl get pods -n <namespace> -l app=<label> -o yaml | grep "image:"

# Check pod status conditions
kubectl get pods -n <namespace> -l app=<label> -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}'
```

### Review Resource Usage Patterns

```bash
# Current usage
kubectl top pods -n <namespace>
kubectl top nodes

# Check for throttling or OOM kills
kubectl describe pod <name> -n <namespace> | grep -A 5 "State:"
kubectl get events -n <namespace> | grep -E "OOMKilled|Throttling"
```

---

## Common Issues and Recommendations

### Issue: High CPU Throttling

**Detection**:
```bash
kubectl top pod <name> -n <namespace>  # CPU near limit
kubectl describe pod <name> -n <namespace> | grep -i throttl
```

**Recommendation**:
- Increase CPU limits or remove them (allow bursting)
- Verify application isn't inefficient
- Consider HPA if load varies

### Issue: Memory OOMKilled

**Detection**:
```bash
kubectl get events -n <namespace> | grep OOMKilled
kubectl describe pod <name> -n <namespace> | grep "State:"
```

**Recommendation**:
- Increase memory limits
- Set memory requests = limits (Guaranteed QoS)
- Investigate memory leaks
- Add liveness probe to restart sooner

### Issue: Over-Provisioned Resources

**Detection**:
```bash
kubectl top pods -n <namespace>
# Compare usage to requests
```

**Recommendation**:
- Reduce resource requests to match actual usage
- Lower limits proportionally
- Potential cost savings
- Free up cluster capacity

### Issue: No Health Probes

**Detection**:
```bash
kubectl get pod <name> -n <namespace> -o jsonpath='{.spec.containers[*].livenessProbe}'
# Empty output = no probe
```

**Recommendation**:
Add appropriate probes:
```yaml
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
  initialDelaySeconds: 15
  periodSeconds: 20
readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 10
```

### Issue: Security Vulnerabilities

**Detection**:
```bash
kubectl get pod <name> -n <namespace> -o jsonpath='{.spec.containers[*].securityContext}'
```

**Recommendation**:
Apply security context:
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  allowPrivilegeEscalation: false
  capabilities:
    drop:
    - ALL
  readOnlyRootFilesystem: true
  seccompProfile:
    type: RuntimeDefault
```

---

## Integration with Existing Tools

### If Metrics Server Available

```bash
# Check if metrics-server installed
kubectl get deployment metrics-server -n kube-system

# Use for resource analysis
kubectl top nodes
kubectl top pods -A
```

### If Prometheus/Grafana Available

Ask user for Prometheus query endpoints to:
- Historical resource usage patterns
- P95/P99 latency metrics
- Error rates
- Custom application metrics

### If Policy Tools Installed

```bash
# Check for Gatekeeper
kubectl get constrainttemplates

# Check for Kyverno
kubectl get clusterpolicies

# Note existing policies in recommendations
```

---

## Output Format Example

```markdown
# Kubernetes Manifest Review: production/web-app

**Cluster**: production-us-east
**Namespace**: production
**Resources Reviewed**: 5 Deployments, 2 StatefulSets, 1 HPA
**Reviewed**: 2024-01-15 10:30 UTC

---

## Executive Summary

- **Critical Issues**: 2 (security vulnerabilities)
- **High Priority**: 4 (resource optimization opportunities)
- **Medium Priority**: 3 (best practice improvements)
- **Low Priority**: 5 (minor enhancements)

**Estimated Impact**:
- Cost reduction: ~30% (reduce over-provisioning)
- Security: Address 2 Baseline violations
- Reliability: Add missing health probes to 3 deployments

---

## Critical Issues

### [Deployment:api-server] Running as root user
- **Impact**: Security risk - container escape possible
- **Current State**: No `runAsNonRoot` or `runAsUser` set
- **Pod Security Standard**: Violates Baseline
- **Recommendation**:
  ```yaml
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 3000
  ```
- **Reference**: https://kubernetes.io/docs/concepts/security/pod-security-standards/

---

## High Priority

### [Deployment:web-frontend] Over-provisioned resources
- **Impact**: Wasting ~$200/month in cluster costs
- **Current State**:
  - Requests: CPU 1000m, Memory 2Gi
  - Actual Usage: CPU 150m (15%), Memory 400Mi (20%)
- **Recommendation**:
  ```yaml
  resources:
    requests:
      cpu: 200m
      memory: 512Mi
    limits:
      memory: 512Mi
  ```
- **Expected Benefit**: 80% cost reduction for this workload

[... continue for all findings ...]
```

---

## Reference Files

| File | Content |
|------|---------|
| `references/kubectl-commands.md` | Comprehensive kubectl command reference for inspection |
| `references/resource-optimization.md` | CPU/memory sizing, QoS classes, optimization patterns |
| `references/security-standards.md` | Pod Security Standards (Privileged/Baseline/Restricted) |
| `references/health-probes.md` | Liveness, readiness, startup probe patterns |
| `references/deployment-patterns.md` | Deployment strategies, rollouts, HA patterns |
| `references/autoscaling-guide.md` | HPA configuration, metrics, scaling behavior |
| `references/stateful-workloads.md` | StatefulSet patterns, volume management |
| `references/logging-best-practices.md` | Logging architecture and configuration |

Load these references when detailed domain knowledge is needed for analysis.

---

## Usage

```bash
# Review entire namespace
kubectl get all -n <namespace>
# Then run analysis on each resource type

# Review specific deployment
kubectl get deployment <name> -n <namespace> -o yaml
kubectl describe deployment <name> -n <namespace>
kubectl top pods -n <namespace> -l app=<label>
# Then run analysis checklist

# Review with resource usage
kubectl top pods -A | grep <pattern>
# Identify over/under-provisioned workloads
```

This skill provides zero-shot manifest review using embedded Kubernetes expertise from official documentation and production best practices.
