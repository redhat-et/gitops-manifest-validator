---
name: validating-kubernetes-intent-and-architecture
description: >
  Use when reviewing Kubernetes manifests to validate design intent and architectural
  decisions. Use when manifests contain unexplained port exposure, single-replica
  production deployments, multi-container Pods, unusual update strategies, or any
  configuration where the WHY behind a decision is unclear. Use when creating new
  manifests to ensure the author has thought through architectural tradeoffs.
  Use when multi-container Pods need pattern classification (sidecar, init, ambassador,
  adapter). Use when manifests show signs of anti-patterns like stateful Deployments,
  sidecar sprawl, or distributed monoliths.
allowed-tools: Read, Glob, Grep
---

# Validating Kubernetes Intent and Architecture

**Core principle: Every manifest configuration should reflect a deliberate design decision. If the intent behind a choice is unclear, ASK -- do not assume or silently accept.**

## Workflow

### Step 1: Classify the Workload

Before analyzing details, determine what the manifest is trying to accomplish:

| Signal | Likely Workload Type | Follow-up |
|--------|---------------------|-----------|
| replicas > 1, readiness probe, Service | Stateless web service | Verify rolling update strategy |
| replicas: 1, PVC, Recreate strategy | Stateful singleton | Ask why not StatefulSet |
| initContainers + main container | Startup-dependent service | Verify init is idempotent |
| Multiple containers sharing volumes | Multi-container pattern | Classify pattern (see Step 2) |
| No Service, high resources | Batch/compute workload | Ask why not Job/CronJob |
| DaemonSet | Node-level agent | Verify needs to run on every node |

### Step 2: Classify Multi-Container Patterns

When a Pod has 2+ containers, identify the architectural pattern. See `references/architecture-patterns.md`.

**Decision process:**
1. Identify the main container (highest resources, exposes primary port)
2. For each additional container, determine its relationship to the main container
3. Classify: sidecar (enhances main), ambassador (proxies outbound), adapter (transforms output)
4. If multiple containers appear to be "main" containers (each with significant resources and application ports), this is a red flag -- they likely belong in separate Deployments
5. If no clear pattern fits, the containers may belong in separate Deployments

**Multiple "main" containers warning:** When 2+ containers each have substantial resource requests and expose application ports, question whether they are co-located for a valid reason (shared data via emptyDir, tight latency coupling) or if they should be independent Deployments that scale and update separately.

**You MUST state the identified pattern explicitly** and ask the user to confirm. Example:
> "This Pod appears to use the **sidecar pattern**: 'ingester' is the main container, and 'exporter' is a metrics adapter reading from the shared volume. Is this correct?"

### Step 3: Validate Port Intent

For every exposed port, verify its purpose. See `references/intent-questions.md` for question templates.

**Non-negotiable checks:**
- Every port MUST have a named purpose (HTTP API, metrics, admin, debug)
- Database ports (5432, 3306, 27017, 6379) on non-database containers MUST be explained
- Ports exposed via LoadBalancer MUST be intentionally public
- Metrics ports (9090, 9100) should not be publicly exposed

**If a port's purpose is unclear, ask.** Do not guess. Do not rationalize.

### Step 4: Validate Replica Intent

Check that replica count matches the workload's requirements.

| Configuration | Question to Ask |
|--------------|----------------|
| replicas: 1 in production | "Is this a singleton by design? What is the recovery plan?" |
| replicas: 1 + Recreate strategy | "Recreate causes downtime. Is this required for exclusive resource access?" |
| replicas: 1 + PVC (RWO) | "Looks like a stateful singleton. Should this be a StatefulSet?" |
| replicas: 1 + lock file env var | "Lock-based singleton detected. Is there a stale lock cleanup mechanism?" |
| replicas > 10, no HPA | "Static high replica count. Is load constant or should HPA manage scaling?" |

### Step 5: Validate Health and Observability Intent

For production workloads, verify probes and observability are intentional:

| Missing Element | Question to Ask |
|----------------|----------------|
| No livenessProbe | "How does Kubernetes detect if this container has crashed or deadlocked?" |
| No readinessProbe | "How does Kubernetes know when this container is ready to receive traffic?" |
| No metrics port | "How is this workload monitored? Is there an external metrics collection mechanism?" |
| Probes pointing to application port | "Are the probe endpoints lightweight? Heavy probe endpoints cause cascading failures under load." |

### Step 6: Detect Anti-Patterns

Scan for common anti-patterns. See `references/anti-patterns.md` for the full catalog.

**Priority anti-patterns to flag:**
1. Stateful Deployment that should be StatefulSet
2. Containers that should be separate Deployments (different scaling/lifecycle needs)
3. Hardcoded environment-specific values
4. Privileged containers without justification
5. EmptyDir for data that needs persistence
6. LoadBalancer exposing internal-only ports
7. Missing health probes on production workloads
8. Secrets in environment variables for highly sensitive credentials

### Step 7: Produce Intent Report

For every manifest reviewed, produce a structured report:

```
INTENT VALIDATION REPORT

Workload: [name] ([classified type])
Pattern: [multi-container pattern if applicable]

QUESTIONS REQUIRING ANSWERS:
1. [Question about unclear design decision]
2. [Question about unclear design decision]

ANTI-PATTERNS DETECTED:
- [Anti-pattern name]: [specific finding] -> [recommended alternative]

ARCHITECTURAL OBSERVATIONS:
- [Pattern classification and whether it's appropriate]
- [Scaling/lifecycle concerns]

ASSUMPTIONS MADE:
- [Any assumptions about intent, flagged for confirmation]
```

## Red Flags -- STOP and Investigate

- Multi-container Pod where all containers expose application ports (likely should be separate Deployments)
- Database port exposed on a LoadBalancer Service
- Production Deployment with replicas: 1 and no documented justification
- Container using Recreate strategy with a Service (guaranteed downtime for traffic)
- Init container connecting to external service without timeout
- Pod with 4+ containers (sidecar sprawl)

## Non-Negotiable Rules

1. **Never accept an unexplained port.** Every containerPort must have a stated purpose.
2. **Never accept single replica in production without asking why.** The answer may be valid, but it must be explicit.
3. **Always classify multi-container Pods by pattern.** "It has multiple containers" is not analysis.
4. **Always ask before assuming intent.** "This is probably a sidecar" is not validation -- ask the user to confirm.
5. **Flag anti-patterns with alternatives.** Don't just say "this is wrong" -- suggest the correct pattern.

## Common Rationalizations to Reject

| Excuse | Reality |
|--------|---------|
| "The port is probably for debugging" | Debug ports in production are a security risk. Confirm and restrict. |
| "Single replica is fine, we'll scale later" | Production needs HA now. "Later" means after the first outage. |
| "Those containers need to be together" | Prove it. Do they share data? Same lifecycle? Same scaling needs? |
| "The init container always succeeds" | What is the failure mode? What is the timeout? |
| "That's just how we've always done it" | Legacy patterns need validation, not perpetuation. |
| "It works in staging" | Staging doesn't have production traffic, node pressure, or zone failures. |
| "The Recreate strategy is temporary" | Document the timeline. Temporary configurations become permanent. |

## Reference Files

| File | Content |
|------|---------|
| `references/architecture-patterns.md` | Multi-container Pod patterns (sidecar, init, ambassador, adapter) |
| `references/intent-questions.md` | Question templates for validating design decisions |
| `references/anti-patterns.md` | Common Kubernetes anti-patterns with detection signals |
