---
name: analyzing-kubernetes-security-posture
description: |
  Analyzes Kubernetes manifests for security posture, threat modeling, and attack path identification.
  Use when reviewing manifests for security risks beyond simple lint checks. This skill identifies
  compound vulnerabilities where multiple misconfigurations create exploitable attack chains:
  privilege escalation paths, defense-in-depth violations, lateral movement vectors, secret exposure,
  and blast radius analysis. Applies NSA/CISA hardening guidance, MITRE ATT&CK for Containers,
  CIS Kubernetes Benchmark, and Pod Security Standards.
allowed-tools: Read, Glob, Grep
---

# Kubernetes Security Posture Analysis

Threat modeling and attack path analysis for Kubernetes manifests.

## Before Analysis

Gather context to ensure accurate security assessment:

| Source | Gather |
|--------|--------|
| **Manifests** | All YAML files in scope including RBAC, NetworkPolicy, Secrets, workloads |
| **Conversation** | User's security requirements, compliance frameworks, known exceptions |
| **Skill References** | Attack paths, hardening controls, defense-in-depth checklist from `references/` |
| **Namespace Context** | What else runs in the same namespace, what NetworkPolicies exist |

Read ALL referenced manifests before analysis. Security assessment requires the full picture.
Only ask the user for THEIR specific context (threat model, compliance needs). Domain expertise is in this skill.

---

## What This Skill Does

- Identifies attack paths: how an attacker progresses from initial compromise to objectives
- Detects compound vulnerabilities where individual misconfigurations combine into exploitable chains
- Assesses defense-in-depth across 7 security layers
- Maps findings to NSA/CISA controls, MITRE ATT&CK techniques, and Pod Security Standards
- Calculates blast radius: what an attacker can reach from a compromised workload
- Provides specific, actionable remediation with corrected YAML

## What This Skill Does NOT Do

- Runtime security monitoring or live cluster assessment
- Vulnerability scanning of container images
- Policy enforcement (OPA/Gatekeeper, Kyverno)
- Penetration testing or active exploitation
- Network traffic analysis

---

## Analysis Workflow

### Step 1: Manifest Inventory

Identify all resources in scope and their relationships:

```
Workloads:    Deployment, StatefulSet, DaemonSet, Job, CronJob
Identity:     ServiceAccount, Role, ClusterRole, RoleBinding, ClusterRoleBinding
Network:      Service, Ingress, NetworkPolicy
Config:       ConfigMap, Secret
Storage:      PersistentVolumeClaim, hostPath volumes
```

For each workload, map:
- Which ServiceAccount it uses
- What RBAC permissions that ServiceAccount has
- What NetworkPolicies apply to the namespace
- What volumes are mounted and their types
- What secrets/config are referenced

### Step 2: Attack Path Analysis

For every workload, evaluate each attack path from `references/attack-paths.md`:

**Path 1 - Container Escape to Host**:
Check for ANY of these escape vectors:
- `privileged: true`
- `hostPath` volumes (especially `/`, `/etc`, `/var/run`)
- Docker/containerd socket mounts
- `hostPID: true` or `hostIPC: true`
- `hostNetwork: true`
- `CAP_SYS_ADMIN` or `CAP_SYS_PTRACE` capabilities
- Missing seccomp profile with dangerous capabilities

**Path 2 - Lateral Movement via K8s API**:
Check for the combination of:
- `automountServiceAccountToken: true` (or not set)
- ServiceAccount with broad RBAC permissions
- Ability to reach the K8s API server (no egress NetworkPolicy)

**Path 3 - Lateral Movement via Network**:
Check for:
- Missing NetworkPolicy in the namespace
- Hardcoded service addresses in env vars revealing architecture
- Database connection strings with inline credentials
- No egress restrictions (cloud metadata, kubelet API reachable)

**Path 4 - Persistence via Writable Filesystem**:
Check for the combination of:
- Running as root (no `runAsNonRoot`, no `runAsUser`)
- Writable root filesystem (no `readOnlyRootFilesystem`)
- Missing seccomp profile (allows downloading tools)
- Writable volume mounts to executable paths

**Path 5 - Secret Harvesting**:
Check for:
- Plain-text secrets in `env[].value` fields
- Secrets in `command` or `args` arrays
- Passwords, API keys, tokens identifiable by pattern or name
- Specific credential types identified by prefix/pattern:

| Pattern | Credential Type | Blast Radius |
|---------|----------------|--------------|
| `sk_live_` | Stripe live secret key | Payment processing, PCI-DSS scope |
| `sk_test_` | Stripe test key | May leak test account info |
| `whsec_` | Stripe webhook secret | Webhook forgery |
| `eyJ` (base64 JSON) | JWT / token material | Authentication bypass |
| `aes256:` / `AKIA` / `-----BEGIN` | Encryption/AWS/PEM key | Cryptographic compromise |
| `password`, `passwd`, `secret` in env name | Database or service password | Backend system access |
| `mongodb://`, `postgres://`, `mysql://` | Connection string with creds | Direct database access |
| `Bearer `, `Basic ` | Auth header values | Service impersonation |

- Dual exposure: secrets appearing in BOTH env vars AND args are exposed through two independent vectors
- Even well-secured containers (good securityContext, resource limits) are fully undermined by plain-text secrets -- an attacker only needs pod spec read access, not container escape

**Path 6 - Supply Chain via Image**:
Check for:
- `latest` tag (mutable, attacker can replace)
- No image digest (`@sha256:...`)
- Public registry with no pull policy
- `imagePullPolicy: IfNotPresent` with mutable tags (cached stale/compromised image persists)
- Images from untrusted or unverified registries

### Step 3: Defense-in-Depth Assessment

Evaluate each security layer using `references/defense-in-depth-checklist.md`:

1. **Container Isolation** - securityContext controls
2. **Volume Security** - hostPath, socket mounts, read-only
3. **Network Segmentation** - NetworkPolicy presence and scope
4. **Identity and Access** - SA tokens, RBAC scope, least privilege
5. **Secret Management** - how credentials are handled
6. **Resource Boundaries** - limits, quotas
7. **Image Security** - digests, tags, base images

For each layer, note:
- Present controls (what IS configured correctly)
- Missing controls (what is absent)
- Misconfigured controls (what is present but wrong)

### Step 4: Compound Risk Identification

Individual findings are NOT independent. Evaluate combinations:

| Combination | Risk Level | Attack Scenario |
|-------------|-----------|-----------------|
| privileged + hostPath | CRITICAL | Container escape + host FS = full node takeover |
| hostNetwork + no NetworkPolicy | HIGH | Network sniffing + unrestricted lateral movement |
| root + writable FS + no seccomp | HIGH | Tool installation + binary replacement + persistence |
| SA token + broad RBAC + no NetworkPolicy | CRITICAL | API access + permissions + reachability = cluster compromise |
| secrets in env + readable pod spec | HIGH | Anyone with pod read access gets production credentials |
| DaemonSet + any escape vector | CRITICAL | Vulnerability affects ALL nodes simultaneously |
| privileged + hostPID + hostNetwork | CRITICAL | Full host access from every angle |
| docker.sock + SA with create pods | CRITICAL | Unlimited container spawning with arbitrary config |
| good securityContext + secrets in env | HIGH | Container hardening is irrelevant when credentials are in pod spec |
| secrets in env + secrets in args | HIGH | Dual exposure: env vars (/proc/environ) AND args (/proc/cmdline) |
| `latest` tag + privileged | CRITICAL | Supply chain attack delivers code directly into privileged context |
| payment creds in env + no NetworkPolicy | CRITICAL | Credential theft + unrestricted exfiltration to attacker |

### Step 5: Blast Radius Assessment

Determine what an attacker can reach after compromising each workload:

1. **Same-pod access**: Other containers in the pod (shared network, optional shared PID/IPC)
2. **Same-namespace access**: Other pods (if no NetworkPolicy), namespace-scoped secrets
3. **Cross-namespace access**: Via ClusterRole/ClusterRoleBinding permissions
4. **Node-level access**: Via container escape vectors
5. **Cluster-wide access**: Via cluster-scoped RBAC or node-level kubelet credentials
6. **External access**: Via egress to cloud metadata, external databases, payment APIs

For DaemonSets: multiply node-level impact across all nodes.

---

## Output Format

Structure findings as follows:

### Security Posture Summary

```
Overall Rating: CRITICAL | HIGH | MODERATE | LOW
Defense-in-Depth Score: X / 45 (see checklist)

Layers Assessed:
  [FAIL] Container Isolation - privileged, no capabilities dropped
  [FAIL] Volume Security - hostPath /, docker.sock mounted
  [WARN] Network Segmentation - no NetworkPolicy found
  [FAIL] Identity and Access - ClusterRole with secret access
  [PASS] Secret Management - using secretKeyRef
  [WARN] Resource Boundaries - no limits set
  [PASS] Image Security - digest used
```

### Attack Paths Identified

For each identified attack path:

```
ATTACK PATH: Container Escape -> Host Takeover -> Cluster Compromise
  Severity: CRITICAL
  MITRE ATT&CK: T1611 (Escape to Host), T1552.007 (Container API)

  Chain:
    1. Attacker compromises application (RCE, SSRF, dependency vuln)
    2. privileged: true grants full host capabilities
    3. hostPath "/" mount provides host filesystem read/write
    4. docker.sock access allows spawning arbitrary containers
    5. ServiceAccount token + ClusterRole enables cluster-wide secret access

  Blast Radius:
    - All pods on compromised node
    - All secrets in all namespaces (via RBAC)
    - All nodes (DaemonSet runs everywhere)

  Remediation:
    - Remove privileged: true
    - Replace hostPath with PVC or emptyDir
    - Remove docker.sock mount
    - Set automountServiceAccountToken: false
    - Scope RBAC to namespace-level Role
```

### Remediation Priority

Order remediations by:
1. CRITICAL compound risks (multiple escape vectors, cluster-wide blast radius)
2. HIGH individual risks (single escape vector, node-level impact)
3. MODERATE missing controls (defense-in-depth gaps without immediate exploit path)
4. LOW hardening recommendations (best practices not yet exploitable)

For each remediation, provide the corrected YAML snippet.

---

## Rationalization Resistance

When users attempt to rationalize security risks, counter with specific attack scenarios:

| Rationalization | Counter |
|----------------|---------|
| "It needs privileged for monitoring" | Use specific capabilities (CAP_NET_ADMIN, CAP_SYS_PTRACE) instead of full privileged mode |
| "hostPath is needed to read logs" | Mount specific paths read-only, not `/`. Use a logging agent with minimal mounts |
| "We trust our internal network" | Lateral movement is the #1 technique after initial compromise. NetworkPolicy costs nothing |
| "The ServiceAccount needs broad access" | List the exact resources and verbs needed. Wildcard permissions are never justified |
| "Secrets in env vars are fine, we encrypt etcd" | Env vars are exposed in 5+ places: kubectl describe, /proc, audit logs, crash dumps, core files |
| "It's just a dev environment" | Dev environments are the #1 entry point for supply chain attacks. Attackers pivot from dev to prod |
| "We have a WAF in front" | WAFs protect against web attacks. Container escape, SSRF, and dependency vulns bypass WAFs entirely |
| "We'll fix it later" | The window between deployment and fix is when attacks happen. Harden before deploying |

---

## Reference Files

| File | Content |
|------|---------|
| `references/nsa-kubernetes-hardening.md` | NSA/CISA Kubernetes Hardening Guide key controls |
| `references/attack-paths.md` | Container escape, lateral movement, persistence, secret harvesting attack chains |
| `references/defense-in-depth-checklist.md` | 7-layer security checklist with scoring |
