# Right-Sizing Guide for Kubernetes Resources

## When to Flag Overprovisioning

| Signal | Threshold | Recommendation |
|--------|-----------|----------------|
| CPU requests >> actual usage | requests > 2x P95 usage | Reduce requests to 1.2-1.5x P95 |
| Memory requests >> actual usage | requests > 1.5x P95 usage | Reduce requests to 1.2x P95 |
| CPU limits = requests | Tight limits cause throttling | Set limits to 2-5x requests (or remove CPU limits) |
| Memory limits >> requests | limits > 3x requests | Reduce limits to 1.5-2x requests |
| No requests set | Cannot schedule efficiently | Always set requests based on profiling |

## Common Application Resource Profiles

Use these as starting points when actual usage data is unavailable:

| Application Type | CPU Request | Memory Request | Notes |
|-----------------|-------------|----------------|-------|
| Java/Spring Boot | 500m-2000m | 512Mi-2Gi | JVM heap + metaspace + overhead |
| Node.js/Express | 100m-500m | 128Mi-512Mi | Single-threaded, memory-efficient |
| Python/Django | 250m-1000m | 256Mi-1Gi | GIL limits CPU parallelism |
| Go microservice | 100m-500m | 64Mi-256Mi | Low overhead, efficient |
| Nginx/static | 50m-200m | 64Mi-128Mi | Very lightweight |
| PostgreSQL | 500m-4000m | 1Gi-8Gi | Depends on working set size |
| Redis | 250m-1000m | 256Mi-4Gi | Memory is the key resource |
| Elasticsearch | 2000m-8000m | 4Gi-32Gi | Memory-intensive, JVM-based |

## Right-Sizing Decision Process

### Step 1: Check if requests are set

If missing: Flag immediately. Cannot reason about cost or scheduling without requests.

### Step 2: Compare to application profile

If requests are 5x+ above the typical profile for that application type, flag as likely overprovisioned.

Example: Node.js app requesting 4 CPU and 8Gi memory is 8-40x above typical profile.

### Step 3: Check request-to-limit ratio

| Ratio (limits/requests) | Assessment |
|--------------------------|------------|
| 1.0 (equal) | Guaranteed QoS, but may throttle under load |
| 1.5-2.0 | Good balance of guarantee and burst |
| 3.0+ | Likely overprovisioned limits or underestimated requests |
| No limits | Burstable, risks noisy-neighbor |

### Step 4: Calculate waste

```
Waste % = (1 - actual_usage / requests) x 100
Monthly waste $ = (requests - actual_usage) x cost_per_unit x 730 hours x replicas
```

## QoS Classes and Cost Implications

| QoS Class | Condition | Cost Impact | When to Use |
|-----------|-----------|-------------|-------------|
| Guaranteed | requests = limits | Highest (reserves full allocation) | Critical production workloads |
| Burstable | requests < limits | Medium (reserves requests, can burst) | Most workloads |
| BestEffort | No requests/limits | Lowest (no guarantees) | Batch jobs, dev only |

## Waste Indicators Quick Reference

**Definitely overprovisioned (act now):**
- CPU usage consistently < 10% of requests
- Memory usage consistently < 30% of requests
- Cost > $500/month per workload with low utilization

**Possibly overprovisioned (investigate):**
- CPU usage < 30% of requests
- Memory usage < 50% of requests
- Limits > 5x requests

**Appropriately sized:**
- CPU P95 usage = 60-80% of requests
- Memory P95 usage = 70-90% of requests
- Limits = 1.5-2x requests

## Optimization Recommendations Format

When suggesting right-sizing, always provide:

1. **Current state:** What resources are requested and what they cost
2. **Recommended state:** Specific new values with justification
3. **Monthly savings:** Dollar amount saved by the change
4. **Risk assessment:** What could go wrong if recommendation is too aggressive

Example:
```
Current: 4 CPU / 8Gi memory x 10 replicas = $1,139/month (AWS)
Recommended: 1 CPU / 2Gi memory x 10 replicas = $278/month (AWS)
Savings: $861/month ($10,332/year)
Risk: If actual peak usage exceeds 1 CPU, Pods may be throttled.
       Monitor P99 CPU for 2 weeks after change.
```
