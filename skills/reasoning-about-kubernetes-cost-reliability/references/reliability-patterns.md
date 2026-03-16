# Kubernetes Reliability Patterns

## Availability Targets and SLA Calculations

| Availability | Monthly Downtime | Annual Downtime | Typical Use |
|-------------|------------------|-----------------|-------------|
| 99% | 7.3 hours | 3.65 days | Internal tools |
| 99.5% | 3.65 hours | 1.83 days | Single replica, no HA |
| 99.9% | 43.8 minutes | 8.77 hours | Multi-replica, basic HA |
| 99.95% | 21.9 minutes | 4.38 hours | Multi-replica + PDB |
| 99.99% | 4.4 minutes | 52.6 minutes | Full HA (anti-affinity + PDB + multi-zone) |
| 99.999% | 26.3 seconds | 5.26 minutes | Active-active multi-region |

**Composite SLA:** When service depends on multiple components, multiply their SLAs.
Example: App (99.95%) x Database (99.99%) x Load Balancer (99.99%) = 99.93%

## Required Reliability Controls by Environment

### Production (Minimum)

```yaml
# 1. Multiple replicas
spec:
  replicas: 3  # Minimum for HA

# 2. PodDisruptionBudget
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: app-pdb
spec:
  minAvailable: 2  # Or maxUnavailable: 1
  selector:
    matchLabels:
      app: my-app

# 3. Pod anti-affinity (spread across nodes)
spec:
  template:
    spec:
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app
                  operator: In
                  values: [my-app]
              topologyKey: kubernetes.io/hostname

# 4. Topology spread (spread across zones)
spec:
  template:
    spec:
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: topology.kubernetes.io/zone
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels:
            app: my-app

# 5. Health probes
spec:
  template:
    spec:
      containers:
      - livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
          initialDelaySeconds: 15
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
```

### Staging

- replicas: 2 (test multi-replica behavior)
- PDB: recommended
- Anti-affinity: optional
- Probes: required (match production config)

### Development

- replicas: 1 (acceptable)
- PDB: not needed
- Anti-affinity: not needed
- Probes: recommended

## Reliability Assessment Checklist

| Control | Weight | Check |
|---------|--------|-------|
| replicas >= 3 | Critical | `spec.replicas >= 3` |
| PodDisruptionBudget exists | Critical | PDB selector matches Pod labels |
| Liveness probe | High | `containers[*].livenessProbe` defined |
| Readiness probe | High | `containers[*].readinessProbe` defined |
| Pod anti-affinity | High | Anti-affinity on hostname topology |
| Topology spread | Medium | topologySpreadConstraints on zone |
| Resource requests | High | CPU and memory requests set |
| Resource limits | Medium | CPU and memory limits set |
| Startup probe | Low | For slow-starting apps |
| PreStop hook | Low | Graceful shutdown for long requests |

### Scoring

- All Critical + all High = Production-ready
- Missing any Critical = NOT production-ready
- Missing High = Production-ready with risk acceptance needed

## Failure Modes Without Controls

| Missing Control | Failure Mode | Business Impact |
|----------------|--------------|-----------------|
| Single replica | Pod crash = total outage | Minutes to hours of downtime |
| No PDB | `kubectl drain` kills all Pods | Downtime during maintenance |
| No anti-affinity | Node failure kills all replicas | Cluster event = app outage |
| No zone spread | Zone outage kills all replicas | Cloud zone event = app outage |
| No readiness probe | Traffic sent to unready Pods | Errors during deployment/restart |
| No liveness probe | Hung Pods never restart | Silent degradation |

## Cost of Adding Reliability

| Going from | To | Cost Multiplier | Availability Gain |
|------------|-----|-----------------|-------------------|
| 1 replica | 3 replicas | 3x compute | 99.5% -> 99.9% |
| 3 replicas | 3 replicas + PDB | 0 additional | 99.9% -> 99.95% |
| 3 replicas + PDB | + anti-affinity | 0 additional | 99.95% -> ~99.97% |
| + anti-affinity | + zone spread | 0 additional* | ~99.97% -> ~99.99% |

*Zone spread may require nodes in multiple zones, which is typically already the case in managed K8s.

**Key insight:** Going from 1 to 3 replicas is the most expensive step (3x cost) but also the biggest reliability gain. PDB, anti-affinity, and topology spread are free configuration changes.
