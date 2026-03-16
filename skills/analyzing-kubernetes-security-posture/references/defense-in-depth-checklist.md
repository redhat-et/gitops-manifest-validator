# Defense-in-Depth Checklist for Kubernetes Manifests

## Layer 1: Container Isolation

- [ ] `securityContext.runAsNonRoot: true`
- [ ] `securityContext.runAsUser` set to non-root UID (>= 1000)
- [ ] `securityContext.runAsGroup` set to non-root GID
- [ ] `securityContext.readOnlyRootFilesystem: true`
- [ ] `securityContext.allowPrivilegeEscalation: false`
- [ ] `securityContext.privileged` is NOT true
- [ ] `securityContext.capabilities.drop: ["ALL"]`
- [ ] Only minimally required capabilities added back
- [ ] `securityContext.seccompProfile.type: RuntimeDefault` (or Localhost)
- [ ] No `hostPID`, `hostIPC`, or `hostNetwork`

**Failure mode**: Without container isolation, a compromised process has full host-level access. One missing control may be sufficient for escape when combined with a kernel vulnerability.

## Layer 2: Volume Security

- [ ] No `hostPath` volumes (use PersistentVolumeClaims instead)
- [ ] No Docker socket mounts (`/var/run/docker.sock`)
- [ ] Sensitive volume mounts are `readOnly: true`
- [ ] emptyDir volumes have `sizeLimit` set
- [ ] No writable mounts to paths containing executables

**Failure mode**: Host filesystem access bypasses all container isolation. Docker socket access is equivalent to root on the host.

## Layer 3: Network Segmentation

- [ ] NetworkPolicy exists in the namespace
- [ ] Default-deny ingress policy applied
- [ ] Default-deny egress policy applied
- [ ] Explicit ingress rules allow only required sources
- [ ] Explicit egress rules allow only required destinations
- [ ] Egress to cloud metadata (169.254.169.254) blocked
- [ ] Egress to kubelet (port 10250) blocked

**Failure mode**: Without NetworkPolicy, any compromised pod can reach every other pod, the K8s API server, cloud metadata endpoints, and external C2 servers.

## Layer 4: Identity and Access

- [ ] `automountServiceAccountToken: false` (unless K8s API access needed)
- [ ] Dedicated ServiceAccount per workload (not `default`)
- [ ] RBAC uses namespace-scoped Roles (not ClusterRoles) where possible
- [ ] No wildcard (`"*"`) permissions in RBAC rules
- [ ] No `secrets` access unless specifically required
- [ ] No `create pods` or `create deployments` permission (prevents workload injection)
- [ ] ClusterRoleBindings audited and minimized

**Failure mode**: Auto-mounted tokens combined with broad RBAC enable cluster-wide credential theft. Wildcard permissions grant access to resources that do not exist yet.

## Layer 5: Secret Management

- [ ] No secrets in plain-text environment variables
- [ ] No secrets in command-line arguments
- [ ] No secrets hardcoded in container images
- [ ] Secrets use K8s Secret resources with `secretKeyRef` or volume mounts
- [ ] Sensitive Secret volumes mounted `readOnly: true`
- [ ] External secret management considered (Vault, AWS SM, etc.)

**Failure mode**: Plain-text secrets are exposed through kubectl describe, K8s API, etcd, /proc filesystem, audit logs, and crash dumps.

## Layer 6: Resource Boundaries

- [ ] CPU and memory `requests` set
- [ ] CPU and memory `limits` set
- [ ] `limits` >= `requests` (to avoid OOMKill under contention)
- [ ] LimitRange configured in namespace
- [ ] ResourceQuota configured in namespace

**Failure mode**: Without resource limits, a compromised container can consume all node resources (CPU, memory, disk), impacting every workload on the node.

## Layer 7: Image Security

- [ ] Image uses digest (sha256) not mutable tag
- [ ] No `latest` tag
- [ ] Image from trusted/private registry
- [ ] Minimal base image (distroless, scratch, alpine)
- [ ] `imagePullPolicy: Always` if using tags

**Failure mode**: Mutable tags allow silent image replacement. `latest` tag is unpredictable. Public images may contain known CVEs or supply chain compromises.

## Scoring

Count the checked items across all layers:

| Score | Rating | Meaning |
|-------|--------|---------|
| 40+ / 45 | Strong | Comprehensive defense-in-depth |
| 30-39 / 45 | Moderate | Key controls present but gaps exist |
| 20-29 / 45 | Weak | Multiple layers have gaps |
| < 20 / 45 | Critical | Insufficient security controls |

**Important**: Scoring is not linear. A single missing control in Layer 1 (container isolation) combined with a gap in Layer 3 (network segmentation) can be more dangerous than missing five controls across Layers 6 and 7.
