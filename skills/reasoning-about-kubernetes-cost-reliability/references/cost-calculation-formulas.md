# Cloud Provider Cost Calculation Formulas

## Reference Pricing (On-Demand, US regions, as of 2025)

### AWS EKS

| Resource | Instance Type Basis | Hourly Rate | Monthly (730h) |
|----------|-------------------|-------------|-----------------|
| 1 vCPU | m5.large equivalent | $0.031 | $22.63 |
| 1 GiB Memory | m5.large equivalent | $0.004 | $2.92 |
| EKS Control Plane | Per cluster | $0.10/hr | $73.00 |

**Formula:** `Monthly = (CPU_requests x $22.63) + (Memory_GiB x $2.92) x replicas`

**Example:** 4 CPU, 8Gi, 10 replicas = (4 x $22.63 + 8 x $2.92) x 10 = **$1,139/month**

### GCP GKE

| Resource | E2 basis | Hourly Rate | Monthly (730h) |
|----------|----------|-------------|-----------------|
| 1 vCPU | E2 standard | $0.028 | $20.44 |
| 1 GiB Memory | E2 standard | $0.004 | $2.69 |
| GKE Autopilot vCPU | Per Pod | $0.034 | $24.82 |
| GKE Autopilot Memory | Per Pod GiB | $0.004 | $2.69 |
| GKE Control Plane (Standard) | Per cluster | $0.10/hr | $73.00 |

**Formula:** `Monthly = (CPU_requests x $20.44) + (Memory_GiB x $2.69) x replicas`

**Example:** 4 CPU, 8Gi, 10 replicas = (4 x $20.44 + 8 x $2.69) x 10 = **$1,032.80/month**

### Azure AKS

| Resource | D-series basis | Hourly Rate | Monthly (730h) |
|----------|---------------|-------------|-----------------|
| 1 vCPU | D2s v3 equivalent | $0.033 | $24.09 |
| 1 GiB Memory | D2s v3 equivalent | $0.004 | $3.07 |
| AKS Control Plane (Free tier) | Per cluster | $0.00 | $0.00 |
| AKS Control Plane (Standard) | Per cluster | $0.10/hr | $73.00 |

**Formula:** `Monthly = (CPU_requests x $24.09) + (Memory_GiB x $3.07) x replicas`

**Example:** 4 CPU, 8Gi, 10 replicas = (4 x $24.09 + 8 x $3.07) x 10 = **$1,209.20/month**

## Storage Costs

| Provider | Storage Class | $/GiB/month |
|----------|--------------|-------------|
| AWS | gp3 (default) | $0.08 |
| AWS | io2 (high IOPS) | $0.125+ |
| GCP | pd-standard | $0.04 |
| GCP | pd-ssd | $0.17 |
| Azure | Standard HDD | $0.04 |
| Azure | Premium SSD | $0.12 |

**PVC Formula:** `Monthly = PVC_size_GiB x $/GiB x number_of_PVCs`

## Savings Options

| Option | Typical Savings | Commitment |
|--------|----------------|------------|
| Reserved Instances (1yr) | 30-40% | 1 year |
| Reserved Instances (3yr) | 50-60% | 3 years |
| Spot/Preemptible | 60-90% | Can be interrupted |
| Committed Use (GCP) | 37-55% | 1-3 years |

When reporting costs, show on-demand price and note: "Savings of 30-60% possible with reserved instances or spot."

## Quick Estimation Shortcut

For quick estimates when exact pricing is not critical:

- **1 CPU-month ~ $22** (average across providers)
- **1 GiB-month ~ $3** (average across providers)
- **Formula:** `(CPU x $22 + Memory_GiB x $3) x replicas = monthly cost`

This gives a reasonable ballpark within 10-15% of actual cost.
