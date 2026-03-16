# Kubernetes Attack Paths

Reference: MITRE ATT&CK for Containers, real-world incident analysis

## Attack Path 1: Container Escape to Host

**Entry**: Compromised application (RCE, SSRF, dependency vulnerability)

**Escalation chain**:
1. `privileged: true` -> full host capabilities, device access
2. OR `hostPath: /` -> read/write host filesystem directly
3. OR `docker.sock` mount -> spawn new privileged containers
4. OR `hostPID: true` + `nsenter` -> enter host PID namespace
5. OR `CAP_SYS_ADMIN` + unconfined seccomp -> mount host filesystem

**Impact**: Full node compromise, access to all pods on node, kubelet credentials

**Manifest indicators**:
```yaml
# Any ONE of these enables container escape
securityContext:
  privileged: true           # Full escape
  capabilities:
    add: ["SYS_ADMIN"]       # Mount-based escape
    add: ["SYS_PTRACE"]      # Process injection
volumes:
  - hostPath:
      path: /                # Host FS access
  - hostPath:
      path: /var/run/docker.sock  # Container runtime access
hostPID: true                # Host process namespace
hostNetwork: true            # Host network stack
```

## Attack Path 2: Lateral Movement via Kubernetes API

**Entry**: Pod with auto-mounted ServiceAccount token

**Escalation chain**:
1. Read token from `/var/run/secrets/kubernetes.io/serviceaccount/token`
2. Discover API server via `KUBERNETES_SERVICE_HOST` env var
3. Enumerate permissions: `kubectl auth can-i --list`
4. If `get secrets` -> harvest credentials from other namespaces
5. If `create pods` -> spawn privileged pod for node escape
6. If `patch deployments` -> inject sidecar into existing workloads

**Impact**: Cluster-wide credential theft, workload manipulation

**Manifest indicators**:
```yaml
# Risk factors for this path
spec:
  automountServiceAccountToken: true  # or not set (defaults to true)
  serviceAccountName: overprivileged-sa
# Combined with:
# - ClusterRole with broad permissions
# - No NetworkPolicy blocking API server access
```

## Attack Path 3: Lateral Movement via Network

**Entry**: Pod in namespace without NetworkPolicy

**Escalation chain**:
1. Scan internal network (all pods reachable by default)
2. Access databases using connection strings from environment
3. Access other services' metadata endpoints
4. Access cloud provider metadata (169.254.169.254) for IAM credentials
5. Access node kubelet API (10250) for container exec

**Impact**: Data exfiltration, service impersonation, cloud account compromise

**Manifest indicators**:
```yaml
# Risk factors for this path
# 1. No NetworkPolicy in namespace
# 2. Database credentials in env vars
env:
  - name: DB_HOST
    value: "postgres.production.svc.cluster.local"
  - name: DB_PASSWORD
    value: "plain-text-password"
# 3. No egress restrictions -> cloud metadata accessible
```

## Attack Path 4: Persistence via Writable Filesystem

**Entry**: Container running as root with writable filesystem

**Escalation chain**:
1. Download tools (curl/wget available in most images)
2. Replace application binaries with backdoored versions
3. Install cryptominers or reverse shells
4. Modify startup scripts for persistence across restarts
5. If hostPath mounted -> persist on host filesystem

**Impact**: Long-term unauthorized access, resource hijacking

**Manifest indicators**:
```yaml
# Risk combination
securityContext:
  # runAsNonRoot not set -> defaults to root
  # readOnlyRootFilesystem not set -> writable
  # No seccomp profile -> curl/wget/chmod available
```

## Attack Path 5: Secret Harvesting via Environment

**Entry**: Access to pod spec (K8s API, etcd, or process table)

**Escalation chain**:
1. `kubectl get pod -o yaml` reveals all env var values
2. OR access etcd directly -> all pod specs with secrets in plain text
3. OR `/proc/[pid]/environ` on the node -> container env vars
4. OR `/proc/[pid]/cmdline` -> secrets passed as arguments
5. Credentials enable access to external systems (databases, payment APIs, cloud)

**Impact**: Full credential compromise, external system access

**Manifest indicators**:
```yaml
# Direct secret exposure
env:
  - name: DB_PASSWORD
    value: "literal-password"        # Exposed in pod spec
  - name: API_KEY
    value: "sk_live_..."             # Payment API key
args:
  - "--password=secret"              # Visible in /proc/cmdline
# Should instead use:
env:
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: db-credentials
        key: password
```

## Compound Risk Matrix

Individual risks multiply when combined:

| Combination | Compound Risk |
|-------------|---------------|
| privileged + hostPath | Container escape + host FS write = node takeover |
| hostNetwork + no NetworkPolicy | Full network visibility + unrestricted movement |
| root + writable FS + no seccomp | Tool installation + binary replacement + privilege escalation |
| SA token + broad RBAC + no NetworkPolicy | API access + permissions + reachability = cluster compromise |
| secrets in env + no RBAC restriction | Anyone who can read pods can read production credentials |
| DaemonSet + any escape vector | Single vulnerability compromises ALL nodes simultaneously |
