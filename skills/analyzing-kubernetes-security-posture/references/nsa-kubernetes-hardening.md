# NSA/CISA Kubernetes Hardening Guide - Key Controls

Reference: NSA/CISA Kubernetes Hardening Guidance v1.2 (August 2022)

## Pod Security

| Control | Requirement | Why It Matters |
|---------|-------------|----------------|
| Non-root execution | `runAsNonRoot: true`, `runAsUser: >= 1000` | Root in container = root on host if escape occurs |
| Drop capabilities | `capabilities.drop: ["ALL"]` | Default capabilities include NET_RAW, SYS_CHROOT |
| No privilege escalation | `allowPrivilegeEscalation: false` | Prevents setuid/setgid binaries from gaining root |
| Read-only root FS | `readOnlyRootFilesystem: true` | Prevents binary replacement, tool installation |
| No privileged containers | `privileged: false` (or omit) | Privileged = all host capabilities + device access |
| No hostPath volumes | Avoid `hostPath` | Direct host filesystem access bypasses all isolation |
| No hostNetwork | `hostNetwork: false` | Host network bypasses NetworkPolicy, sees all traffic |
| No hostPID | `hostPID: false` | Host PID namespace allows signaling host processes |
| Seccomp profile | `seccompProfile.type: RuntimeDefault` | Blocks dangerous syscalls (ptrace, mount, unshare) |

## Network Hardening

| Control | Requirement | Why It Matters |
|---------|-------------|----------------|
| NetworkPolicy per namespace | Default-deny ingress + egress | Without policy, any pod can reach any other pod |
| Limit egress | Explicit egress rules | Prevents data exfiltration, C2 communication |
| TLS everywhere | mTLS between services | Prevents MITM, credential sniffing |
| Separate control plane | Restrict API server access | API server is the primary attack target |

## Authentication and Authorization

| Control | Requirement | Why It Matters |
|---------|-------------|----------------|
| Disable SA token auto-mount | `automountServiceAccountToken: false` | Mounted tokens enable K8s API access from pods |
| Least-privilege RBAC | Namespace-scoped Roles, not ClusterRoles | ClusterRoles affect every namespace |
| No wildcard permissions | Avoid `"*"` in verbs or resources | Wildcards grant future permissions too |
| No secret access unless needed | Remove `secrets` from RBAC rules | Secret access = credential access |
| Bind roles to specific SAs | Not to groups or users | Specific bindings are easier to audit |

## Audit and Logging

| Control | Requirement | Why It Matters |
|---------|-------------|----------------|
| Enable audit logging | Audit policy configured | Detect credential theft, unauthorized access |
| Log API access | Metadata + RequestResponse | Track who accessed what and when |
| Centralize logs | Forward to SIEM | Prevent log tampering on compromised nodes |

## Image Security

| Control | Requirement | Why It Matters |
|---------|-------------|----------------|
| Use image digests | `image: name@sha256:...` | Tags are mutable, digests are not |
| No `latest` tag | Explicit version tags | `latest` is unpredictable and unauditable |
| Scan images | Vulnerability scanning in CI/CD | Known CVEs in base images |
| Use minimal images | distroless, scratch, alpine | Fewer binaries = smaller attack surface |

## Secret Management

| Control | Requirement | Why It Matters |
|---------|-------------|----------------|
| No secrets in env vars | Use volume-mounted Secrets | Env vars leak to logs, kubectl describe, /proc |
| No secrets in args | Never pass secrets as CLI args | Visible in /proc/cmdline, ps output |
| No secrets in manifests | Use external secret managers | Manifests in git = secrets in git history |
| Enable encryption at rest | EncryptionConfiguration for etcd | Protects secrets stored in etcd |
| Rotate secrets | Automated rotation | Limits window of compromised credentials |
