---
name: reasoning-about-kubernetes-cost-reliability
description: >
  Use when reviewing Kubernetes manifests for resource cost implications, overprovisioning waste,
  reliability gaps (single replica, no PDB, missing anti-affinity), or cost-vs-reliability tradeoff
  decisions. Use when someone asks "how much does this cost?" or "is this production-ready?"
allowed-tools: Read, Glob, Grep
---

# Kubernetes Cost & Reliability Reasoning

**Core principle:** Every resource request has a dollar cost. Every reliability gap has an outage risk. Always quantify both.

## Workflow

### Step 1: Calculate Cost

Extract `requests.cpu` and `requests.memory` (not limits) for each container. Multiply by replicas.

**Quick estimate:** `(CPU x $22 + Memory_GiB x $3) x replicas = monthly cost`

See `references/cost-calculation-formulas.md` for per-provider pricing (AWS/GCP/Azure).

### Step 2: Detect Waste

| Signal | Threshold | Action |
|--------|-----------|--------|
| limits >> requests | limits > 3x requests | Flag overprovisioning risk |
| No resource requests | Missing entirely | Flag -- cannot calculate cost |
| High replica count | > 5 replicas without HPA | Question if static scaling needed |
| Unused storage | PVC without matching Pod mount | Flag orphaned storage cost |

See `references/right-sizing-guide.md` for optimization heuristics.

### Step 3: Evaluate Reliability

| Check | Production Minimum | Risk if Missing |
|-------|-------------------|-----------------|
| replicas >= 3 | Required | No HA, single-point-of-failure |
| PodDisruptionBudget | Required | Node drain kills all Pods |
| Pod anti-affinity | Required | All replicas on same node = no HA |
| Liveness + readiness probes | Required | No auto-recovery from crashes |
| Topology spread constraints | Recommended | Zone failure takes entire app down |

See `references/reliability-patterns.md` for HA patterns and SLA calculations.

### Step 4: Present Tradeoff Table

Always present a table with columns: Option | Monthly Cost | Availability | Risk. Show current state, recommended state, and high-HA option with calculated dollar amounts and SLA percentages.

## Red Flags -- STOP and Investigate

- Production namespace + replicas: 1 + no PDB
- CPU/memory requests missing entirely (cannot reason about cost)
- limits set but requests missing (limits become requests, likely unintentional)
- Storage class "gp3" or "premium" without justification for cost tier

## Non-Negotiable Rules

1. **Every analysis MUST include a dollar amount.** "Significant resources" is not analysis. Calculate it.
2. **Every reliability finding MUST include an SLA percentage.** "Not highly available" is not analysis. Quantify it.
3. **Always present cost AND reliability together** as a tradeoff table. Never analyze one without the other.
4. **Use the quick estimate formula** inline -- do not defer to "see the reference file."

## Common Mistakes

| Mistake | Reality |
|---------|---------|
| "Resources look reasonable" without dollar amounts | Always calculate: `(CPU x $22 + Mem_GiB x $3) x replicas` |
| Noting "single replica" without SLA impact | Quantify: 1 replica = ~99.5%, 3 replicas = ~99.95% |
| Ignoring memory when only CPU seems high | Memory is often the larger cost driver |
| Not mentioning PDB for any multi-replica workload | PDB is required for safe node maintenance |
| Analyzing cost without reliability (or vice versa) | Always present both together in tradeoff table |
