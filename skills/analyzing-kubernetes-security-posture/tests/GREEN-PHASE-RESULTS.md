# GREEN Phase: Skill Application Results

## Scenario 1: Privilege Escalation Chain

With the skill applied, the analysis identifies:

**Attack Path: Container Escape -> Host Takeover -> Cluster Compromise**
- Severity: CRITICAL
- MITRE ATT&CK: T1611 (Escape to Host), T1552.007 (Container API), T1053 (Scheduled Task)

Chain:
1. Attacker compromises infra-agent application (RCE, dependency vuln, or supply chain via `latest` tag)
2. `privileged: true` grants ALL host capabilities (Step 2 of Attack Path 1)
3. `hostPath: /` at `/host` provides read/write to entire node filesystem (Step 2 of Attack Path 1)
4. `/var/run/docker.sock` mount enables spawning arbitrary containers (Step 3 of Attack Path 1)
5. `hostPID: true` allows `nsenter` into host PID namespace (Step 4 of Attack Path 1)
6. `hostNetwork: true` bypasses all NetworkPolicy enforcement
7. ServiceAccount `infra-agent` has ClusterRole with `delete` on secrets cluster-wide (Attack Path 2)
8. DaemonSet means this runs on EVERY node - single vuln = full cluster

Defense-in-Depth Score: 3 / 45 (CRITICAL)

**Compound risks identified by skill**:
- privileged + hostPath + docker.sock = triple redundant escape (Compound Risk Matrix row 1)
- hostNetwork + no NetworkPolicy check = full network visibility
- DaemonSet + any escape vector = ALL nodes compromised (Compound Risk Matrix row 6)
- `latest` tag = supply chain attack vector (Image Security layer)
- ClusterRole with secret CRUD = credential harvesting across all namespaces

**Remediation provided**: Specific YAML fixes for each finding.

PASS: Skill identifies all expected attack paths and compound risks.

## Scenario 2: Defense-in-Depth Violation

With the skill applied, the analysis identifies:

**Attack Path: Compromised Web API -> Lateral Movement -> Data Exfiltration**
- Severity: HIGH
- MITRE ATT&CK: T1046 (Network Service Scanning), T1552 (Unsecured Credentials)

Chain:
1. Attacker compromises web-api (web vulnerability, SSRF)
2. No securityContext = root execution (Layer 1 failure)
3. No `readOnlyRootFilesystem` = tool download and binary replacement (Attack Path 4)
4. No seccomp profile = unrestricted syscalls including curl/wget
5. `automountServiceAccountToken` defaults to true = K8s API token available (Attack Path 2)
6. No NetworkPolicy = can reach postgres, redis, K8s API, cloud metadata (Attack Path 3)
7. Hardcoded DB/Redis URLs reveal internal architecture for targeted attacks
8. 3 replicas = 3 separate compromise points

Defense-in-Depth Score: 8 / 45 (CRITICAL)

**Compound risks identified by skill**:
- root + writable FS + no seccomp = persistence chain (Compound Risk Matrix row 3)
- SA token + default RBAC + no NetworkPolicy = K8s API recon (Compound Risk Matrix row 4)
- DB connection strings + no egress policy = direct database access after compromise

**Key insight the skill provides**: No single finding here is individually critical, but the COMBINATION creates an easily exploitable chain. This is exactly the compound vulnerability analysis the skill is designed to surface.

PASS: Skill identifies layered failures and compound risks.

## Scenario 3: Secret Exposure

With the skill applied, the analysis identifies:

**Attack Path: Secret Harvesting via Multiple Vectors**
- Severity: CRITICAL
- MITRE ATT&CK: T1552.001 (Credentials in Files), T1552.007 (Container API)

Chain:
1. Secrets exposed in env vars: DB_PASSWORD, STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET, JWT_SIGNING_KEY, ENCRYPTION_KEY
2. Secrets duplicated in args: --db-password, --stripe-key (DOUBLE exposure)
3. Env var exposure vectors: kubectl describe, K8s API, etcd, /proc/[pid]/environ, audit logs
4. Args exposure vectors: /proc/[pid]/cmdline, ps output on node, container runtime logs
5. Specific credential identification:
   - `sk_live_` prefix = Stripe LIVE payment key (PCI-DSS scope)
   - `whsec_` prefix = Stripe webhook secret
   - `eyJ` prefix = JWT/base64 encoded key material
   - `aes256:` prefix = encryption key
   - `payment_admin` = privileged database user

Defense-in-Depth Score: 28 / 45 (WEAK - strong in other layers but Layer 5 is completely failed)

**Key insight the skill provides**: This workload has GOOD container isolation (runAsNonRoot, readOnlyRootFilesystem, no privilege escalation, resource limits) but completely fails on secret management. The skill correctly identifies that strong container security is undermined when production payment credentials are in plain text. An attacker does not need to escape the container - they just need to read the pod spec.

**Additional finding**: `automountServiceAccountToken` not explicitly set to false. Combined with default SA, anyone who can exec into the pod or read pod specs gets both K8s API access AND all the plain-text credentials.

PASS: Skill identifies secret exposure patterns, credential types, and blast radius.
