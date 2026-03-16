# Compliance Framework Mappings for Kubernetes Manifests

## PCI-DSS 4.0 - Kubernetes Manifest Controls

### Requirement 1: Network Security Controls

| PCI-DSS Req | Control | Manifest Check | Pass Criteria |
|-------------|---------|---------------|---------------|
| 1.2.1 | Restrict inbound/outbound traffic | NetworkPolicy exists for namespace | NetworkPolicy with ingress AND egress rules present |
| 1.3.1 | Restrict inbound traffic to CDE | NetworkPolicy ingress rules | Only authorized sources in `from` rules |
| 1.3.2 | Restrict outbound traffic from CDE | NetworkPolicy egress rules | Only authorized destinations in `to` rules |
| 1.4.1 | Control traffic between trusted/untrusted | Namespace isolation | CDE workloads in dedicated namespace with NetworkPolicy |

**Gap if missing**: No NetworkPolicy resources in CDE namespace = FAIL 1.2.1, 1.3.1, 1.3.2

### Requirement 2: Secure Configurations

| PCI-DSS Req | Control | Manifest Check | Pass Criteria |
|-------------|---------|---------------|---------------|
| 2.2.1 | Secure system configuration standards | SecurityContext fully specified | All security fields explicitly set (not relying on defaults) |
| 2.2.5 | Remove unnecessary services/ports | Container ports | Only required ports exposed; no `hostPort`, no `hostNetwork` |
| 2.2.7 | Encrypt non-console admin access | Service/Ingress TLS | TLS configured on Services/Ingress handling admin traffic |

### Requirement 3: Protect Stored Account Data

| PCI-DSS Req | Control | Manifest Check | Pass Criteria |
|-------------|---------|---------------|---------------|
| 3.4.1 | Render PAN unreadable | Env vars and ConfigMaps | No card data in plaintext env vars; use Secrets with encryption at rest |
| 3.5.1 | Protect cryptographic keys | Secret management | Encryption keys in Kubernetes Secrets (encrypted at rest), not env vars |

**Gap if found**: Plaintext credentials or keys in `env[].value` = FAIL 3.4.1, 3.5.1

### Requirement 6: Secure Software Development

| PCI-DSS Req | Control | Manifest Check | Pass Criteria |
|-------------|---------|---------------|---------------|
| 6.3.1 | Security vulnerabilities identified | Image scanning reference | Image from scanned registry; not `latest` tag |
| 6.3.2 | Software developed securely | Image tags/digests | Pinned image version (tag or digest); no `latest` or mutable tags |
| 6.5.4 | Protect against common attacks | SecurityContext hardening | `readOnlyRootFilesystem: true`, dropped capabilities, non-root |

### Requirement 8: Identify Users and Authenticate Access

| PCI-DSS Req | Control | Manifest Check | Pass Criteria |
|-------------|---------|---------------|---------------|
| 8.2.1 | Unique accounts for access | ServiceAccount usage | Dedicated ServiceAccount (not `default`); `automountServiceAccountToken: false` unless needed |
| 8.3.1 | Strong authentication | Credential management | No hardcoded passwords in env vars; use Secrets or external vault |
| 8.6.1 | Service account management | ServiceAccount scope | ServiceAccount exists with minimal RBAC bindings |

### Requirement 10: Log and Monitor Activity

| PCI-DSS Req | Control | Manifest Check | Pass Criteria |
|-------------|---------|---------------|---------------|
| 10.2.1 | Audit log coverage | Pod audit configuration | Audit logging enabled; stdout/stderr captured |
| 10.3.1 | Protect audit logs | Log volume configuration | Log volumes not writable by application; separate from data volumes |

### Requirement 12: Organizational Policies

| PCI-DSS Req | Control | Manifest Check | Pass Criteria |
|-------------|---------|---------------|---------------|
| 12.1.1 | Security policy | Labels and annotations | `pci-scope` label present on CDE workloads |

## HIPAA Technical Safeguards - Kubernetes Manifest Controls

### Access Control (164.312(a))

| HIPAA Ref | Control | Manifest Check | Pass Criteria |
|-----------|---------|---------------|---------------|
| 164.312(a)(1) | Unique user identification | ServiceAccount per workload | Dedicated ServiceAccount; not `default` |
| 164.312(a)(1) | Access control | RBAC bindings | RoleBinding with least-privilege Role |
| 164.312(a)(2)(i) | Emergency access | Break-glass annotations | Documented emergency access procedure |

### Audit Controls (164.312(b))

| HIPAA Ref | Control | Manifest Check | Pass Criteria |
|-----------|---------|---------------|---------------|
| 164.312(b) | Hardware/software audit | Logging configuration | Application logs to stdout; log aggregation configured |
| 164.312(b) | Process audit | Liveness/readiness probes | Probes configured for health monitoring |

### Integrity (164.312(c))

| HIPAA Ref | Control | Manifest Check | Pass Criteria |
|-----------|---------|---------------|---------------|
| 164.312(c)(1) | Data integrity | readOnlyRootFilesystem | `readOnlyRootFilesystem: true`; immutable container |
| 164.312(c)(2) | Integrity validation | Image digest pinning | Image referenced by digest, not mutable tag |

### Transmission Security (164.312(e))

| HIPAA Ref | Control | Manifest Check | Pass Criteria |
|-----------|---------|---------------|---------------|
| 164.312(e)(1) | Encryption in transit | TLS configuration | HTTPS ports; TLS termination configured |
| 164.312(e)(1) | Network segmentation | NetworkPolicy | NetworkPolicy isolating PHI workloads |

## SOC2 Trust Service Criteria - Kubernetes Manifest Controls

### CC6.1: Logical Access Security

| SOC2 Ref | Control | Manifest Check | Pass Criteria |
|----------|---------|---------------|---------------|
| CC6.1 | Least privilege | SecurityContext + RBAC | `allowPrivilegeEscalation: false`; `drop: [ALL]`; minimal RBAC |
| CC6.1 | Segregation of duties | Namespace isolation | Workloads separated by namespace; NetworkPolicy between them |
| CC6.1 | Access restrictions | ServiceAccount management | Dedicated SA; `automountServiceAccountToken: false` |

### CC6.6: Security Boundaries

| SOC2 Ref | Control | Manifest Check | Pass Criteria |
|----------|---------|---------------|---------------|
| CC6.6 | Network segmentation | NetworkPolicy | Ingress/egress rules defined |
| CC6.6 | Data protection boundary | Namespace labels | Clear boundary labels (`data-classification`, `environment`) |

### CC7.1: Monitoring

| SOC2 Ref | Control | Manifest Check | Pass Criteria |
|----------|---------|---------------|---------------|
| CC7.1 | Detect unauthorized changes | readOnlyRootFilesystem | Immutable containers detect tampering |
| CC7.1 | Health monitoring | Probes configured | Liveness + readiness probes present |

### CC8.1: Change Management

| SOC2 Ref | Control | Manifest Check | Pass Criteria |
|----------|---------|---------------|---------------|
| CC8.1 | Controlled deployments | Image versioning | Pinned image tags or digests; no `latest` |
| CC8.1 | Rollback capability | Deployment strategy | `strategy.type` defined; revision history maintained |

## NIST SP 800-190 - Application Container Security

### Section 4.1: Image Risks

| NIST Ref | Control | Manifest Check | Pass Criteria |
|----------|---------|---------------|---------------|
| 4.1.1 | Image vulnerabilities | Image source | Image from trusted registry; pinned version |
| 4.1.5 | Image configuration | SecurityContext | Non-root user; read-only filesystem; no privileged |

### Section 4.2: Registry Risks

| NIST Ref | Control | Manifest Check | Pass Criteria |
|----------|---------|---------------|---------------|
| 4.2.2 | Stale images | Image tags | No `latest`; version pinned or digest-referenced |

### Section 4.3: Orchestrator Risks

| NIST Ref | Control | Manifest Check | Pass Criteria |
|----------|---------|---------------|---------------|
| 4.3.1 | Admin access | RBAC configuration | Least-privilege roles; no cluster-admin bindings |
| 4.3.4 | Resource limits | Resource requests/limits | CPU and memory requests and limits set |

### Section 4.4: Container Risks

| NIST Ref | Control | Manifest Check | Pass Criteria |
|----------|---------|---------------|---------------|
| 4.4.1 | Runtime vulnerabilities | SecurityContext hardening | Drop ALL capabilities; readOnlyRootFilesystem; non-root |
| 4.4.2 | Network access | NetworkPolicy | Restrict container network access to minimum required |

### Section 4.6: Host OS Risks

| NIST Ref | Control | Manifest Check | Pass Criteria |
|----------|---------|---------------|---------------|
| 4.6.1 | Host isolation | Host namespace flags | No hostNetwork, hostPID, hostIPC, hostPath |

## Gap Report Template

```
[FRAMEWORK] COMPLIANCE GAP REPORT
===================================
Scope: [namespace(s) / resource(s)]
Framework: [PCI-DSS 4.0 / HIPAA / SOC2 / NIST SP 800-190]

CONTROL ASSESSMENT
------------------
[Req ID] [Title]
  Status: PASS | FAIL | PARTIAL | N/A
  Evidence: [manifest field = value]
  Gap: [what is missing or misconfigured]
  Risk: [what could happen if not remediated]
  Remediation: [specific manifest change]
  Priority: Critical | High | Medium | Low

SUMMARY
-------
Controls Evaluated: N
  PASS: N
  FAIL: N
  PARTIAL: N
  N/A: N

CRITICAL GAPS (must fix before audit):
1. [Req ID]: [description]
2. [Req ID]: [description]

HIGH GAPS (fix soon):
1. [Req ID]: [description]
```
