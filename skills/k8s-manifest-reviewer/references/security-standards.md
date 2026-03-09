# Pod Security Standards

Complete Pod Security Standards from official Kubernetes documentation.

## Overview

Three security profiles with cumulative restrictions:

| Profile | Description | Use Case |
|---------|-------------|----------|
| **Privileged** | Unrestricted | Trusted system workloads, infrastructure |
| **Baseline** | Minimally restrictive, prevents privilege escalation | Common containerized workloads |
| **Restricted** | Heavily restrictive, hardening best practices | Security-critical applications |

## Privileged Profile

**Entirely unrestricted** - no restrictions applied.

Use only for:
- Trusted system workloads
- Infrastructure components
- Node-level agents

## Baseline Profile

Prevents known privilege escalations. **Minimum acceptable for production.**

### Baseline Controls

#### 1. HostProcess (Windows)

**Forbidden**: Windows HostProcess containers

```yaml
# ❌ VIOLATION
spec:
  securityContext:
    windowsOptions:
      hostProcess: true

# ✅ COMPLIANT
spec:
  securityContext:
    windowsOptions:
      hostProcess: false  # or omitted
```

#### 2. Host Namespaces

**Forbidden**: Sharing host namespaces

```yaml
# ❌ VIOLATION
spec:
  hostNetwork: true
  hostPID: true
  hostIPC: true

# ✅ COMPLIANT
spec:
  hostNetwork: false  # or omitted
  hostPID: false      # or omitted
  hostIPC: false      # or omitted
```

**Impact**: Host namespace access allows container escape

#### 3. Privileged Containers

**Forbidden**: Privileged containers

```yaml
# ❌ VIOLATION
spec:
  containers:
  - name: app
    securityContext:
      privileged: true

# ✅ COMPLIANT
spec:
  containers:
  - name: app
    securityContext:
      privileged: false  # or omitted
```

**Impact**: Privileged mode gives full host access

#### 4. Capabilities

**Restricted**: Only safe capabilities allowed

**Allowed capabilities**:
- `AUDIT_WRITE`
- `CHOWN`
- `DAC_OVERRIDE`
- `FOWNER`
- `FSETID`
- `KILL`
- `MKNOD`
- `NET_BIND_SERVICE`
- `SETFCAP`
- `SETGID`
- `SETPCAP`
- `SETUID`
- `SYS_CHROOT`

```yaml
# ❌ VIOLATION
spec:
  containers:
  - name: app
    securityContext:
      capabilities:
        add:
        - SYS_ADMIN  # Not in allowed list

# ✅ COMPLIANT
spec:
  containers:
  - name: app
    securityContext:
      capabilities:
        drop:
        - ALL
        add:
        - NET_BIND_SERVICE  # Allowed
```

**Best practice**: Drop all, add only what's needed

#### 5. HostPath Volumes

**Forbidden**: HostPath volumes

```yaml
# ❌ VIOLATION
spec:
  volumes:
  - name: host-vol
    hostPath:
      path: /var/lib/data

# ✅ COMPLIANT
spec:
  volumes:
  - name: data
    emptyDir: {}
```

**Impact**: HostPath provides host filesystem access

#### 6. Host Ports

**Forbidden**: Host port binding

```yaml
# ❌ VIOLATION
spec:
  containers:
  - name: app
    ports:
    - containerPort: 8080
      hostPort: 8080

# ✅ COMPLIANT
spec:
  containers:
  - name: app
    ports:
    - containerPort: 8080  # No hostPort
```

**Impact**: Locks pod to specific node, port conflicts

**Alternative**: Use Service with NodePort or LoadBalancer

#### 7. AppArmor

**Restricted**: Only safe AppArmor profiles

**Allowed values**:
- `RuntimeDefault`
- `Localhost`
- Undefined/empty

```yaml
# ❌ VIOLATION
spec:
  securityContext:
    appArmorProfile:
      type: Unconfined

# ✅ COMPLIANT
spec:
  securityContext:
    appArmorProfile:
      type: RuntimeDefault
```

#### 8. SELinux

**Restricted**: User and role options

```yaml
# ❌ VIOLATION
spec:
  securityContext:
    seLinuxOptions:
      user: "custom_u"  # Custom user forbidden

# ✅ COMPLIANT
spec:
  securityContext:
    seLinuxOptions:
      type: "container_t"  # Allowed types only
```

**Allowed SELinux types**:
- `container_t`
- `container_init_t`
- `container_kvm_t`
- `container_engine_t`

#### 9. /proc Mount Type

**Restricted**: Default proc mount only

```yaml
# ❌ VIOLATION
spec:
  containers:
  - name: app
    securityContext:
      procMount: Unmasked

# ✅ COMPLIANT
spec:
  containers:
  - name: app
    securityContext:
      procMount: Default  # or omitted
```

#### 10. Seccomp

**Restricted**: Safe seccomp profiles only

**Allowed values**:
- `RuntimeDefault`
- `Localhost`
- Undefined

```yaml
# ❌ VIOLATION
spec:
  securityContext:
    seccompProfile:
      type: Unconfined

# ✅ COMPLIANT
spec:
  securityContext:
    seccompProfile:
      type: RuntimeDefault
```

#### 11. Sysctls

**Restricted**: Safe sysctls only

**Allowed sysctls**:
- `kernel.shm_rmid_forced`
- `net.ipv4.ip_local_port_range`
- `net.ipv4.ip_unprivileged_port_start`
- `net.ipv4.tcp_syncookies`
- `net.ipv4.ping_group_range`
- `net.ipv4.ip_local_reserved_ports` (v1.27+)
- `net.ipv4.tcp_keepalive_time` (v1.29+)
- `net.ipv4.tcp_fin_timeout` (v1.29+)
- `net.ipv4.tcp_keepalive_intvl` (v1.29+)
- `net.ipv4.tcp_keepalive_probes` (v1.29+)

```yaml
# ❌ VIOLATION
spec:
  securityContext:
    sysctls:
    - name: kernel.shm_all
      value: "1"

# ✅ COMPLIANT
spec:
  securityContext:
    sysctls:
    - name: net.ipv4.ip_local_port_range
      value: "1024 65535"
```

## Restricted Profile

**All Baseline controls PLUS additional hardening.**

### Additional Restricted Controls

#### 1. Volume Types

**Restricted**: Only safe volume types allowed

**Allowed volume types**:
- `configMap`
- `csi`
- `downwardAPI`
- `emptyDir`
- `ephemeral`
- `persistentVolumeClaim`
- `projected`
- `secret`

**Forbidden volume types**:
- `hostPath`
- `gcePersistentDisk`
- `awsElasticBlockStore`
- `nfs`
- `iscsi`
- `flexVolume`
- `cinder`
- etc.

```yaml
# ❌ VIOLATION
spec:
  volumes:
  - name: data
    nfs:
      server: nfs.example.com
      path: /data

# ✅ COMPLIANT
spec:
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: data-pvc
```

#### 2. Privilege Escalation

**Required**: Must explicitly prevent privilege escalation

```yaml
# ❌ VIOLATION
spec:
  containers:
  - name: app
    # Missing allowPrivilegeEscalation

# ✅ COMPLIANT
spec:
  containers:
  - name: app
    securityContext:
      allowPrivilegeEscalation: false  # Must be explicitly false
```

**Critical**: Must be set for ALL containers, initContainers, ephemeralContainers

#### 3. Running as Non-Root

**Required**: Must run as non-root user

```yaml
# ❌ VIOLATION
spec:
  containers:
  - name: app
    # No runAsNonRoot set

# ✅ COMPLIANT (Option 1 - Pod level)
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
  containers:
  - name: app

# ✅ COMPLIANT (Option 2 - Container level)
spec:
  containers:
  - name: app
    securityContext:
      runAsNonRoot: true
      runAsUser: 1000
```

**Note**: At least one of pod-level or container-level must be set

#### 4. Restricted Capabilities

**Required**: Drop all capabilities

```yaml
# ❌ VIOLATION (Baseline allows some capabilities)
spec:
  containers:
  - name: app
    securityContext:
      capabilities:
        add:
        - NET_BIND_SERVICE

# ✅ COMPLIANT (Restricted requires dropping all)
spec:
  containers:
  - name: app
    securityContext:
      capabilities:
        drop:
        - ALL
      # No 'add' allowed in Restricted
```

**Exception**: Restricted still allows the Baseline-approved capabilities if needed, but best practice is to drop ALL

## Complete Baseline Example

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: baseline-compliant
spec:
  securityContext:
    runAsUser: 1000
    runAsGroup: 3000
    fsGroup: 2000
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: app
    image: myapp:1.0
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop:
        - ALL
        add:
        - NET_BIND_SERVICE
      readOnlyRootFilesystem: true
    ports:
    - containerPort: 8080
    volumeMounts:
    - name: cache
      mountPath: /cache
    - name: config
      mountPath: /config
  volumes:
  - name: cache
    emptyDir: {}
  - name: config
    configMap:
      name: app-config
```

## Complete Restricted Example

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: restricted-compliant
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 3000
    fsGroup: 2000
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: app
    image: myapp:1.0
    securityContext:
      runAsNonRoot: true
      allowPrivilegeEscalation: false
      capabilities:
        drop:
        - ALL
      readOnlyRootFilesystem: true
    resources:
      requests:
        cpu: "100m"
        memory: "128Mi"
      limits:
        cpu: "500m"
        memory: "256Mi"
    ports:
    - containerPort: 8080
    volumeMounts:
    - name: cache
      mountPath: /cache
    - name: config
      mountPath: /config
  volumes:
  - name: cache
    emptyDir: {}
  - name: config
    configMap:
      name: app-config
```

## Checking Compliance

### kubectl Commands

```bash
# Check security context
kubectl get pod <name> -n <namespace> -o jsonpath='{.spec.securityContext}'

# Check container security context
kubectl get pod <name> -n <namespace> -o jsonpath='{.spec.containers[*].securityContext}'

# Check for privileged containers
kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].securityContext.privileged}{"\n"}{end}' | grep true

# Check for host namespaces
kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.hostNetwork}{"\t"}{.spec.hostPID}{"\n"}{end}' | grep true

# Check runAsNonRoot
kubectl get pod <name> -n <namespace> -o jsonpath='{.spec.containers[*].securityContext.runAsNonRoot}'
```

## Common Violations and Fixes

### Violation 1: Running as Root

```yaml
# ❌ CURRENT
spec:
  containers:
  - name: app
    image: myapp:1.0

# ✅ FIX
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 3000
    fsGroup: 2000
  containers:
  - name: app
    image: myapp:1.0
```

### Violation 2: Privileged Container

```yaml
# ❌ CURRENT
spec:
  containers:
  - name: app
    securityContext:
      privileged: true

# ✅ FIX
spec:
  containers:
  - name: app
    securityContext:
      privileged: false
      capabilities:
        drop:
        - ALL
        add:
        - NET_BIND_SERVICE  # Only if needed
```

### Violation 3: Host Namespace

```yaml
# ❌ CURRENT
spec:
  hostNetwork: true
  hostPID: true

# ✅ FIX
spec:
  hostNetwork: false  # or omit
  hostPID: false      # or omit
```

### Violation 4: HostPath Volume

```yaml
# ❌ CURRENT
spec:
  volumes:
  - name: data
    hostPath:
      path: /var/lib/app

# ✅ FIX
spec:
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: app-data-pvc
```

### Violation 5: Missing Security Controls

```yaml
# ❌ CURRENT (missing multiple controls)
spec:
  containers:
  - name: app
    image: myapp:1.0

# ✅ FIX (Restricted-compliant)
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: app
    image: myapp:1.0
    securityContext:
      runAsNonRoot: true
      allowPrivilegeEscalation: false
      capabilities:
        drop:
        - ALL
      readOnlyRootFilesystem: true
```

## Enforcement with Pod Security Admission

Apply policies using namespace labels:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: production
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: latest
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

**Modes**:
- `enforce`: Reject non-compliant pods
- `audit`: Log violations (allow pod)
- `warn`: Show warnings (allow pod)

## Migration Strategy

**Step 1**: Start with audit mode
```yaml
labels:
  pod-security.kubernetes.io/audit: baseline
```

**Step 2**: Address violations

**Step 3**: Enable warn mode
```yaml
labels:
  pod-security.kubernetes.io/warn: baseline
```

**Step 4**: Enforce when ready
```yaml
labels:
  pod-security.kubernetes.io/enforce: baseline
```

**Step 5**: Progress to restricted
```yaml
labels:
  pod-security.kubernetes.io/enforce: restricted
```

## Quick Reference

| Control | Baseline | Restricted |
|---------|----------|------------|
| Privileged containers | ❌ Forbidden | ❌ Forbidden |
| Host namespaces | ❌ Forbidden | ❌ Forbidden |
| HostPath volumes | ❌ Forbidden | ❌ Forbidden |
| Host ports | ❌ Forbidden | ❌ Forbidden |
| Capabilities | ⚠️ Limited list | ❌ Must drop ALL |
| runAsNonRoot | - | ✅ Required |
| allowPrivilegeEscalation | - | ❌ Must be false |
| Volume types | - | ⚠️ Limited list |
| Seccomp | ⚠️ RuntimeDefault/Localhost | ⚠️ RuntimeDefault/Localhost |

## Official Documentation

- Pod Security Standards: https://kubernetes.io/docs/concepts/security/pod-security-standards/
- Pod Security Admission: https://kubernetes.io/docs/concepts/security/pod-security-admission/
