# Horizontal Pod Autoscaling Guide

Complete HPA configuration and best practices based on official Kubernetes documentation.

## Overview

HorizontalPodAutoscaler (HPA) automatically scales workloads by adjusting replica count based on observed metrics.

**Supported resources**:
- Deployment
- ReplicaSet
- StatefulSet
- Custom resources (with scale subresource)

**NOT supported**:
- DaemonSet (runs on all nodes by design)

## How HPA Works

### Control Loop

1. Runs every 15 seconds (configurable via `--horizontal-pod-autoscaler-sync-period`)
2. Queries metrics from Metrics API
3. Calculates desired replicas using formula
4. Updates target resource's replica count if needed

### Scaling Formula

```
desiredReplicas = ceil(currentReplicas × currentMetricValue / desiredMetricValue)
```

**Example**:
- Current replicas: 2
- Current CPU usage: 200m
- Target CPU: 100m
- Desired replicas: ceil(2 × 200 / 100) = ceil(4) = 4

## Metrics Types

### 1. Resource Metrics (CPU/Memory)

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: app-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: app
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70  # Target 70% CPU utilization
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80  # Target 80% memory utilization
```

**Requirements**:
- Metrics Server must be installed
- Containers must have resource requests defined

**Utilization calculation**:
```
utilization% = (current usage / requested amount) × 100
```

### 2. Custom Metrics

```yaml
metrics:
- type: Pods
  pods:
    metric:
      name: http_requests_per_second
    target:
      type: AverageValue
      averageValue: "1000"  # Target 1000 RPS per pod
```

**Requirements**:
- Custom metrics adapter installed
- Metric exposed by application

### 3. External Metrics

```yaml
metrics:
- type: External
  external:
    metric:
      name: queue_depth
      selector:
        matchLabels:
          queue: worker_tasks
    target:
      type: AverageValue
      averageValue: "30"  # Target 30 messages per pod
```

**Use cases**:
- Cloud provider metrics (SQS queue depth, Pub/Sub backlog)
- External monitoring systems

### 4. Object Metrics

```yaml
metrics:
- type: Object
  object:
    metric:
      name: requests_per_second
    describedObject:
      apiVersion: networking.k8s.io/v1
      kind: Ingress
      name: main-route
    target:
      type: Value
      value: "10k"  # Total RPS across all pods
```

## Configuration Parameters

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: comprehensive-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: app
  minReplicas: 2          # Never scale below
  maxReplicas: 100        # Never scale above

  # Scaling behavior (v1.23+)
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 0  # Scale up immediately
      policies:
      - type: Percent
        value: 100      # Double pods
        periodSeconds: 60
      - type: Pods
        value: 4        # Or add 4 pods
        periodSeconds: 60
      selectPolicy: Max  # Use max of above policies
    scaleDown:
      stabilizationWindowSeconds: 300  # Wait 5 min before scale down
      policies:
      - type: Percent
        value: 50       # Remove 50% of pods
        periodSeconds: 60
      - type: Pods
        value: 2        # Or remove 2 pods
        periodSeconds: 60
      selectPolicy: Min  # Use min of above policies

  # Metrics
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

### Scaling Behavior Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `stabilizationWindowSeconds` | How long to look back at metrics before scaling | 300s (scale down), 0s (scale up) |
| `selectPolicy` | How to combine multiple policies | Max |
| `policies` | List of scaling policies | - |

**Policies**:
- `type: Percent` - Scale by percentage of current replicas
- `type: Pods` - Scale by absolute number of pods

## Production Patterns

### Pattern 1: CPU-Based Autoscaling (Web Apps)

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: web-app-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: web-app
  minReplicas: 3           # HA baseline
  maxReplicas: 20
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70  # Scale before CPU constrained
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 60
      policies:
      - type: Percent
        value: 50
        periodSeconds: 60
    scaleDown:
      stabilizationWindowSeconds: 300  # Slow scale down
      policies:
      - type: Pods
        value: 1
        periodSeconds: 60
```

### Pattern 2: Memory-Based Autoscaling (Data Processing)

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: processor-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: data-processor
  minReplicas: 2
  maxReplicas: 50
  metrics:
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80  # Scale at 80% memory
```

### Pattern 3: Multi-Metric Autoscaling (Production API)

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api
  minReplicas: 5
  maxReplicas: 100
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
  - type: Pods
    pods:
      metric:
        name: http_requests_per_second
      target:
        type: AverageValue
        averageValue: "1000"  # 1000 RPS per pod
```

**Behavior**: HPA chooses largest desired replica count from all metrics

### Pattern 4: Queue-Based Autoscaling (Workers)

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: worker-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: worker
  minReplicas: 1
  maxReplicas: 50
  metrics:
  - type: External
    external:
      metric:
        name: sqs_queue_depth
        selector:
          matchLabels:
            queue: tasks
      target:
        type: AverageValue
        averageValue: "30"  # 30 messages per worker
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 0    # Scale up immediately
      policies:
      - type: Percent
        value: 100    # Double when queue grows
        periodSeconds: 60
    scaleDown:
      stabilizationWindowSeconds: 600  # Wait 10 min before scale down
      policies:
      - type: Pods
        value: 1      # Remove 1 at a time
        periodSeconds: 120
```

## Prerequisites

### 1. Metrics Server (Required for Resource Metrics)

```bash
# Check if installed
kubectl get deployment metrics-server -n kube-system

# Install if missing (example)
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Verify
kubectl top nodes
kubectl top pods
```

### 2. Resource Requests (Required for CPU/Memory Metrics)

```yaml
# ❌ HPA WILL FAIL without requests
spec:
  containers:
  - name: app
    resources: {}

# ✅ REQUIRED for HPA
spec:
  containers:
  - name: app
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
```

**Error without requests**:
```
missing request for cpu
```

### 3. Deployment Must Be Scalable

```yaml
# ✅ Can autoscale
kind: Deployment
spec:
  replicas: 3  # HPA will override

# ❌ Cannot autoscale
kind: DaemonSet  # Runs on all nodes by design
```

## Monitoring HPA

### Check HPA Status

```bash
# List HPAs
kubectl get hpa

# Output:
# NAME      REFERENCE          TARGETS   MINPODS   MAXPODS   REPLICAS   AGE
# app-hpa   Deployment/app     45%/70%   2         10        3          5m

# Detailed status
kubectl describe hpa app-hpa

# Watch HPA in real-time
kubectl get hpa app-hpa --watch
```

### HPA Status Fields

```bash
kubectl describe hpa app-hpa

# Key fields:
# Current Replicas: 5
# Desired Replicas: 7
# Current Metrics:
#   cpu: 85% (target: 70%)
# Events:
#   ScaledUp: Scaled deployment from 5 to 7
```

### Scaling Events

```bash
# Recent scaling events
kubectl get events --sort-by='.lastTimestamp' | grep HorizontalPodAutoscaler

# Example events:
# Successfully set replica count to 7
# Failed to get memory utilization: missing request
```

## Troubleshooting

### Issue 1: HPA Not Scaling

**Check metric availability**:
```bash
kubectl top pods -n <namespace>

# If empty, Metrics Server not working
kubectl get deployment metrics-server -n kube-system
```

**Check resource requests**:
```bash
kubectl get pod <pod> -o jsonpath='{.spec.containers[*].resources.requests}'

# Must have CPU request for CPU-based HPA
```

**Check HPA status**:
```bash
kubectl describe hpa <name>

# Look for errors in Conditions or Events
```

### Issue 2: Rapid Scaling Oscillation

**Symptom**: HPA scales up and down repeatedly

**Causes**:
- Threshold too sensitive
- Stabilization window too short
- Missing readiness probes

**Fix**:
```yaml
behavior:
  scaleDown:
    stabilizationWindowSeconds: 300  # Increase from default
  scaleUp:
    stabilizationWindowSeconds: 60   # Avoid instant scale-ups
```

### Issue 3: Unable to Get Metrics

**Error**:
```
unable to get metrics for resource cpu
```

**Fixes**:
```bash
# 1. Check Metrics Server
kubectl get deployment metrics-server -n kube-system

# 2. Check API services
kubectl get apiservices | grep metrics

# 3. Verify resource requests defined
kubectl get pod <pod> -o yaml | grep -A 5 resources
```

### Issue 4: HPA Ignoring Max Replicas

**Symptom**: Replicas exceed maxReplicas

**Cause**: Manual scaling or other controllers

**Fix**:
```bash
# HPA should manage replicas; remove manual scaling
kubectl scale deployment <name> --replicas=3  # Will be overridden by HPA

# Check for conflicting controllers
kubectl get hpa,vpa -A  # VPA can conflict with HPA
```

## Best Practices

### 1. Set Appropriate Min/Max

```yaml
minReplicas: 3     # HA baseline, never go below
maxReplicas: 100   # Prevent runaway scaling, protect budget
```

### 2. Use Conservative Thresholds

```yaml
# ✅ GOOD: Scale before resource constrained
metrics:
- type: Resource
  resource:
    name: cpu
    target:
      type: Utilization
      averageUtilization: 70  # Scale at 70%, not 90%

# ❌ BAD: Scale only when saturated
averageUtilization: 95  # Too late, users already impacted
```

### 3. Combine Multiple Metrics

```yaml
# Scale based on whichever metric needs it first
metrics:
- type: Resource
  resource:
    name: cpu
    target:
      averageUtilization: 70
- type: Resource
  resource:
    name: memory
    target:
      averageUtilization: 80
```

### 4. Configure Scaling Behavior

```yaml
behavior:
  scaleUp:
    stabilizationWindowSeconds: 60   # Quick scale up
    policies:
    - type: Percent
      value: 100                      # Double for traffic spikes
      periodSeconds: 60
  scaleDown:
    stabilizationWindowSeconds: 300  # Slow scale down
    policies:
    - type: Pods
      value: 1                        # Remove 1 at a time
      periodSeconds: 60
```

### 5. Test HPA Before Production

```bash
# Generate load
kubectl run -it --rm load-generator --image=busybox /bin/sh
# Inside pod:
while true; do wget -q -O- http://app-service; done

# Watch HPA respond
kubectl get hpa --watch
kubectl top pods
```

### 6. Monitor Scaling Events

```bash
# Alert on frequent scaling
kubectl get events --field-selector reason=ScaledUp
kubectl get events --field-selector reason=ScaledDown

# Track scaling patterns
kubectl get hpa app-hpa -o jsonpath='{.status.currentReplicas}' --watch
```

## HPA vs VPA

| Aspect | HPA | VPA |
|--------|-----|-----|
| **What it scales** | Number of pods | Pod resource requests |
| **Use when** | Variable load | Workload resource needs change |
| **Can combine?** | **NO** - they conflict | Use one or the other |
| **Restart pods?** | No (adds/removes pods) | Yes (updates requests) |

**Recommendation**: Use HPA for production workloads

## Common Patterns Summary

| Workload Type | Metrics | MinReplicas | Target | Behavior |
|---------------|---------|-------------|--------|----------|
| **Web API** | CPU | 3 | 70% | Quick scale up, slow down |
| **Worker Queue** | External (queue depth) | 1 | 30 msgs/pod | Very quick up, very slow down |
| **Data Processing** | Memory | 2 | 80% | Balanced |
| **High Traffic** | CPU + Custom (RPS) | 10 | 70% + 1000 RPS | Aggressive scale up |

## Official Documentation

- HPA: https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/
- HPA Walkthrough: https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/
- Metrics Server: https://github.com/kubernetes-sigs/metrics-server
