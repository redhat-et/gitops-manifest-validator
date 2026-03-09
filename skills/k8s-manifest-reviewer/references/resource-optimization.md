# Resource Optimization Guide

Best practices for CPU and memory requests/limits based on official Kubernetes documentation.

## Core Concepts

### Requests vs Limits

- **Requests**: Guaranteed resources; used by scheduler for pod placement
- **Limits**: Maximum resources allowed; enforced by kubelet

**Key Principle**: Container can use more than request if available, but never exceeds limit.

### Resource Units

**CPU**:
- Full units: `1` = 1 CPU core (1 AWS vCPU, 1 GCP Core, 1 Azure vCore, 1 Hyperthread)
- Fractional: `0.5` = half a core
- MilliCPU: `500m` = 0.5 CPU (preferred for values < 1)
- Minimum: `1m` (0.001 CPU)

**Memory**:
- Bytes: `128974848`, `129000000`
- Decimal suffixes: `E`, `P`, `T`, `G`, `M`, `k`
- Binary suffixes: `Ei`, `Pi`, `Ti`, `Gi`, `Mi`, `Ki` (preferred)
- **Case-sensitive**: `400m` = 0.4 bytes (NOT megabytes!)

**Examples**:
```yaml
resources:
  requests:
    cpu: "250m"      # 0.25 CPU
    memory: "64Mi"   # 64 mebibytes
  limits:
    cpu: "500m"      # 0.5 CPU
    memory: "128Mi"  # 128 mebibytes
```

## Quality of Service (QoS) Classes

Kubernetes assigns QoS based on requests/limits configuration:

### 1. Guaranteed (Highest Priority)

**Requirements**:
- Every container has CPU and memory limits
- Requests equal limits (or requests omitted, inherits from limits)

```yaml
resources:
  requests:
    cpu: "500m"
    memory: "256Mi"
  limits:
    cpu: "500m"      # Same as request
    memory: "256Mi"  # Same as request
```

**Characteristics**:
- Last to be evicted under memory pressure
- Most predictable performance
- **Best for**: Critical production workloads, databases, stateful apps

### 2. Burstable (Medium Priority)

**Requirements**:
- At least one container has CPU or memory request/limit
- Requests < limits (allows bursting)

```yaml
resources:
  requests:
    cpu: "100m"
    memory: "64Mi"
  limits:
    cpu: "500m"      # Can burst to 500m
    memory: "256Mi"  # Can burst to 256Mi
```

**Characteristics**:
- Evicted before Guaranteed, after BestEffort
- Can burst above request when resources available
- **Best for**: Most applications, web servers, APIs

### 3. BestEffort (Lowest Priority)

**Requirements**:
- No requests or limits defined

```yaml
resources: {}  # Empty
```

**Characteristics**:
- First to be evicted under memory pressure
- No resource guarantees
- **Best for**: Non-critical batch jobs, development/testing only

## CPU Resource Management

### CPU Limits Enforcement

- **Hard throttling**: Kernel enforces CPU limits via CFS quotas
- Container throttled when exceeding limit
- No OOM kill for CPU (unlike memory)

### CPU Best Practices

**1. Always set CPU requests**:
```yaml
resources:
  requests:
    cpu: "100m"  # Scheduler guarantee
```

**2. Consider omitting CPU limits** (controversial but valid):
```yaml
resources:
  requests:
    cpu: "100m"
  # No CPU limit - allows bursting
```

**Rationale**:
- CPU is compressible (throttling, not killing)
- Prevents artificial throttling during bursts
- Node's total CPU is the natural limit

**Counter-argument**:
- One pod could monopolize CPU
- Better to set reasonable limits for noisy neighbor protection

**Production recommendation**:
```yaml
resources:
  requests:
    cpu: "100m"   # Based on P95 usage
  limits:
    cpu: "1000m"  # 2-5x request for burst capacity
```

### Sizing CPU Requests

**Methods**:

1. **Historical data** (preferred):
   ```bash
   kubectl top pod <name> -n <namespace>
   # Monitor over days/weeks
   # Set request to P95 usage
   ```

2. **Load testing**:
   - Simulate production traffic
   - Measure CPU under load
   - Add 20-30% buffer

3. **Conservative start**:
   ```yaml
   # Start with conservative values
   requests:
     cpu: "100m"
   # Monitor and adjust
   ```

### CPU Patterns by Workload Type

**Web APIs** (variable load):
```yaml
resources:
  requests:
    cpu: "100m"   # Baseline
  limits:
    cpu: "1000m"  # 10x burst for spikes
```

**Background Workers** (steady load):
```yaml
resources:
  requests:
    cpu: "500m"   # Average usage
  limits:
    cpu: "750m"   # 1.5x for occasional spikes
```

**Batch Jobs** (high utilization):
```yaml
resources:
  requests:
    cpu: "2000m"  # High baseline
  limits:
    cpu: "4000m"  # 2x for parallel processing
```

## Memory Resource Management

### Memory Limits Enforcement

- **OOM Kill**: Container killed when exceeding memory limit
- **No throttling**: Memory is incompressible
- **Critical**: Always set memory limits in production

### Memory Best Practices

**1. Always set memory requests AND limits**:
```yaml
resources:
  requests:
    memory: "128Mi"
  limits:
    memory: "128Mi"  # Same as request for Guaranteed QoS
```

**2. Requests = Limits (recommended for production)**:
```yaml
resources:
  requests:
    memory: "256Mi"
  limits:
    memory: "256Mi"  # Guaranteed QoS prevents OOM surprises
```

**Rationale**:
- Predictable memory allocation
- Prevents OOM kills during memory pressure
- Scheduler can make better placement decisions

**3. Avoid large request/limit gaps**:
```yaml
# ❌ BAD: Large gap causes issues
resources:
  requests:
    memory: "128Mi"
  limits:
    memory: "2Gi"     # 16x difference - risky!

# ✅ GOOD: Reasonable gap
resources:
  requests:
    memory: "256Mi"
  limits:
    memory: "512Mi"   # 2x difference - safe burst
```

### Sizing Memory Requests

**Methods**:

1. **Monitor actual usage**:
   ```bash
   kubectl top pod <name> -n <namespace> --containers
   # Track peak usage over time
   # Set limit to peak + 20% buffer
   ```

2. **Application profiling**:
   - JVM heap size (Java)
   - Memory limits (Node.js --max-old-space-size)
   - Language-specific memory usage

3. **Container insights**:
   ```bash
   kubectl describe pod <name> -n <namespace>
   # Check for OOMKilled events
   # Check current memory usage in status
   ```

### Memory Patterns by Workload Type

**Java Applications** (JVM heap):
```yaml
resources:
  requests:
    memory: "1Gi"    # Heap + overhead
  limits:
    memory: "1Gi"    # Guaranteed QoS
# Set JVM: -Xmx750m -Xms750m (75% of limit)
```

**Node.js Applications**:
```yaml
resources:
  requests:
    memory: "512Mi"
  limits:
    memory: "512Mi"  # Guaranteed QoS
# Set Node: --max-old-space-size=384 (75% of limit)
```

**Go Applications** (low memory footprint):
```yaml
resources:
  requests:
    memory: "64Mi"
  limits:
    memory: "128Mi"
```

**Memory-intensive (ML, data processing)**:
```yaml
resources:
  requests:
    memory: "4Gi"
  limits:
    memory: "8Gi"   # Allow some burst for data loading
```

## Common Optimization Patterns

### Pattern 1: Over-Provisioned Resources

**Detection**:
```bash
kubectl top pods -n <namespace>
# Usage << Requests
```

**Example**:
```yaml
# Current (wasteful)
resources:
  requests:
    cpu: "1000m"
    memory: "2Gi"
# Actual usage: CPU 100m (10%), Memory 400Mi (20%)
```

**Optimization**:
```yaml
# Optimized (right-sized)
resources:
  requests:
    cpu: "200m"     # 2x actual usage
    memory: "512Mi" # 1.3x actual usage
  limits:
    memory: "512Mi" # Guaranteed QoS
```

**Impact**: 80% cost reduction, free cluster capacity

### Pattern 2: Under-Provisioned Resources

**Detection**:
```bash
kubectl describe pod <name> -n <namespace>
# Look for: OOMKilled, CrashLoopBackOff
# CPU throttling (check metrics)
```

**Example**:
```yaml
# Current (insufficient)
resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
# Actual: Pod killed by OOM
```

**Optimization**:
```yaml
# Fixed (adequate)
resources:
  requests:
    cpu: "250m"      # Increased
    memory: "512Mi"  # Increased to prevent OOM
  limits:
    memory: "512Mi"
```

### Pattern 3: No Resource Limits (BestEffort)

**Current**:
```yaml
resources: {}  # No limits
```

**Risk**: Pod evicted first under memory pressure

**Optimization**:
```yaml
resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    cpu: "500m"
    memory: "256Mi"  # Burstable QoS
```

### Pattern 4: CPU Limits Causing Throttling

**Detection**:
```bash
# Check for CPU throttling in metrics
# If using Prometheus:
# container_cpu_cfs_throttled_seconds_total
```

**Current**:
```yaml
resources:
  requests:
    cpu: "100m"
  limits:
    cpu: "200m"  # Causing throttling under load
```

**Optimization (Option A - Increase limit)**:
```yaml
resources:
  requests:
    cpu: "100m"
  limits:
    cpu: "1000m"  # 10x for burst
```

**Optimization (Option B - Remove limit)**:
```yaml
resources:
  requests:
    cpu: "100m"
  # No limit - allows unlimited burst
```

## Container-Level vs Pod-Level Resources

### Container-Level (Standard)

```yaml
spec:
  containers:
  - name: app
    resources:
      requests:
        cpu: "100m"
        memory: "128Mi"
      limits:
        cpu: "500m"
        memory: "256Mi"
  - name: sidecar
    resources:
      requests:
        cpu: "50m"
        memory: "64Mi"
      limits:
        cpu: "100m"
        memory: "128Mi"
```

**Pod totals**: Sum of all containers

### Pod-Level Resources (Kubernetes v1.34+ beta)

Requires `PodLevelResources` feature gate:

```yaml
spec:
  resources:
    requests:
      cpu: "500m"
      memory: "512Mi"
    limits:
      cpu: "1000m"
      memory: "1Gi"
  containers:
  - name: app
    # Shares pod resources
  - name: sidecar
    resources:
      requests:
        cpu: "100m"  # Guaranteed from pod budget
```

**Benefits**:
- Containers share idle resources
- Simpler total resource management

## Vertical Pod Autoscaler (VPA)

Automatically adjusts requests/limits based on usage:

```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: app-vpa
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: app
  updatePolicy:
    updateMode: "Auto"  # or "Initial", "Off"
  resourcePolicy:
    containerPolicies:
    - containerName: app
      minAllowed:
        cpu: "100m"
        memory: "128Mi"
      maxAllowed:
        cpu: "2000m"
        memory: "2Gi"
```

**Use VPA when**:
- Workload usage patterns vary significantly
- Manual tuning is time-consuming
- Want data-driven recommendations

**Avoid VPA when**:
- Using HPA (VPA + HPA can conflict)
- Stateful applications sensitive to restarts
- Resources already well-tuned

## Cost Optimization Checklist

- [ ] All pods have resource requests defined
- [ ] Requests match actual usage (1.2-1.5x P95)
- [ ] Memory limits = requests for Guaranteed QoS (production)
- [ ] CPU limits reasonable or omitted (allow bursting)
- [ ] No BestEffort QoS in production
- [ ] Monitor for OOMKilled events
- [ ] Check for CPU throttling
- [ ] Identify over-provisioned workloads (usage << requests)
- [ ] Right-size based on historical data
- [ ] Consider VPA for dynamic workloads

## Quick Reference

| Scenario | CPU Request | CPU Limit | Memory Request | Memory Limit |
|----------|-------------|-----------|----------------|--------------|
| **Production critical** | P95 usage | 2-3x request | Peak + 20% | = Request (Guaranteed) |
| **Production standard** | P95 usage | 3-5x request | Peak + 20% | = Request (Guaranteed) |
| **Batch jobs** | High | 1.5-2x | High | 1.5-2x (Burstable) |
| **Development** | Low | Omit | Low | 2x request |
| **Burstable workloads** | Baseline | 5-10x | Baseline | 2x request |

## Official Documentation

- Resource Management: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/
- QoS Classes: https://kubernetes.io/docs/tasks/configure-pod-container/quality-service-pod/
- VPA: https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler
