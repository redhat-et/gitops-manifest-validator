# CIS Kubernetes Benchmark v1.8 - Manifest Control Mapping

Controls 5.2.x (Pod Security Policies / Pod Security Standards) mapped to specific manifest fields.

**CRITICAL RULES**:
- Check ALL container types: `containers`, `initContainers`, and `ephemeralContainers`
- Absent fields use Kubernetes defaults. Key insecure defaults:
  - `privileged`: defaults to `false` (safe)
  - `allowPrivilegeEscalation`: defaults to `true` (UNSAFE - absence = FAIL for 5.2.5)
  - `readOnlyRootFilesystem`: defaults to `false` (UNSAFE - absence = FAIL for 5.2.9)
  - `runAsNonRoot`: defaults to `false` (UNSAFE - absence = FAIL for 5.2.6 unless runAsUser is non-zero)
  - `automountServiceAccountToken`: defaults to `true` (UNSAFE - absence = FAIL for 5.2.12)
- A PASS requires explicit evidence (the field is set to the correct value). Do not infer compliance from absence unless the default is the secure value.

## Control-to-Field Mapping

### 5.2.1: Minimize admission of privileged containers

| Field | Required Value | Location |
|-------|---------------|----------|
| `securityContext.privileged` | `false` or absent | `spec.containers[*].securityContext` |
| `securityContext.privileged` | `false` or absent | `spec.initContainers[*].securityContext` |

**FAIL if**: Any container has `privileged: true`
**Evidence**: Quote the exact `securityContext` block showing the value.

### 5.2.2: Minimize admission of containers wishing to share the host process ID namespace

| Field | Required Value | Location |
|-------|---------------|----------|
| `hostPID` | `false` or absent | `spec` (Pod level) |

**FAIL if**: `hostPID: true`

### 5.2.3: Minimize admission of containers wishing to share the host IPC namespace

| Field | Required Value | Location |
|-------|---------------|----------|
| `hostIPC` | `false` or absent | `spec` (Pod level) |

**FAIL if**: `hostIPC: true`

### 5.2.4: Minimize admission of containers wishing to share the host network namespace

| Field | Required Value | Location |
|-------|---------------|----------|
| `hostNetwork` | `false` or absent | `spec` (Pod level) |

**FAIL if**: `hostNetwork: true`

### 5.2.5: Minimize admission of containers with allowPrivilegeEscalation

| Field | Required Value | Location |
|-------|---------------|----------|
| `securityContext.allowPrivilegeEscalation` | `false` | `spec.containers[*].securityContext` |
| `securityContext.allowPrivilegeEscalation` | `false` | `spec.initContainers[*].securityContext` |

**FAIL if**: `allowPrivilegeEscalation: true` OR field is absent (defaults to `true`)
**Note**: Default is `true` when not set. Absence is a FAIL.

### 5.2.6: Minimize the admission of root containers

| Field | Required Value | Location |
|-------|---------------|----------|
| `securityContext.runAsNonRoot` | `true` | Pod level OR container level |
| `securityContext.runAsUser` | non-zero value | Pod level OR container level |

**FAIL if**: `runAsNonRoot` is `false` or absent AND `runAsUser` is `0` or absent.
**PASS if**: Either `runAsNonRoot: true` OR `runAsUser` is set to a non-zero value at Pod or container level.

### 5.2.7: Minimize admission of containers with added capabilities

| Field | Required Value | Location |
|-------|---------------|----------|
| `securityContext.capabilities.add` | empty or absent | `spec.containers[*].securityContext` |
| `securityContext.capabilities.drop` | should include `ALL` | `spec.containers[*].securityContext` |

**FAIL if**: `capabilities.add` contains any capability (especially dangerous ones: `SYS_ADMIN`, `NET_ADMIN`, `SYS_PTRACE`, `SYS_RAWIO`, `SYS_MODULE`)
**Best practice**: `drop: [ALL]` then selectively add only required capabilities.

### 5.2.8: Minimize admission of containers with capabilities allowing NET_RAW

| Field | Required Value | Location |
|-------|---------------|----------|
| `securityContext.capabilities.drop` | must include `NET_RAW` or `ALL` | `spec.containers[*].securityContext` |

**FAIL if**: `NET_RAW` is not in `capabilities.drop` AND `ALL` is not in `capabilities.drop`

### 5.2.9: Minimize admission of containers with added capabilities assigned writable filesystem

| Field | Required Value | Location |
|-------|---------------|----------|
| `securityContext.readOnlyRootFilesystem` | `true` | `spec.containers[*].securityContext` |

**FAIL if**: `readOnlyRootFilesystem` is `false` or absent (defaults to `false`)

### 5.2.10: Minimize host path volumes

| Field | Required Value | Location |
|-------|---------------|----------|
| `volumes[*].hostPath` | absent | `spec.volumes` |

**FAIL if**: Any volume uses `hostPath`

### 5.2.11: Minimize admission of containers that use hostPort

| Field | Required Value | Location |
|-------|---------------|----------|
| `ports[*].hostPort` | absent or `0` | `spec.containers[*].ports` |

**FAIL if**: Any container port specifies a non-zero `hostPort`

### 5.2.12: Minimize automounting of service account tokens

| Field | Required Value | Location |
|-------|---------------|----------|
| `automountServiceAccountToken` | `false` | `spec` (Pod level) or ServiceAccount |

**FAIL if**: `automountServiceAccountToken` is `true` or absent (defaults to `true`) AND the workload does not require API server access.

## Evidence Collection Template

For each control, collect:

```
Control: CIS [id] - [title]
Status: PASS | FAIL
Resource: [apiVersion] [kind] [namespace/name]
Field Path: spec.containers[0].securityContext.privileged
Actual Value: true
Required Value: false or absent
Timestamp: [analysis date]
```
