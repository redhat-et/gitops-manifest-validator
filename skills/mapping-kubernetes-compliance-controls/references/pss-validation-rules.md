# Pod Security Standards - Validation Rules

Reference: https://kubernetes.io/docs/concepts/security/pod-security-standards/

## Critical Notes

- ALL container types must be checked: `containers`, `initContainers`, `ephemeralContainers`
- One failing container in ANY list downgrades the entire Pod
- `seccompProfile` is the most commonly missed Restricted requirement. A Pod that passes every other Restricted check but lacks `seccompProfile` is classified **Baseline**, not Restricted.
- Pod-level settings apply to all containers unless overridden at container level
- Container-level settings override Pod-level settings for that container only

## Classification Algorithm

Evaluate in order. A Pod's PSS level is the MOST restrictive level whose checks ALL pass:

1. Check ALL Baseline rules. If ANY Baseline rule fails -> level is **Privileged**
2. Check ALL Restricted rules. If ANY Restricted rule fails -> level is **Baseline**
3. If ALL Restricted rules pass -> level is **Restricted**

## Baseline Level Checks

A Pod FAILS Baseline (classified Privileged) if ANY of these are true:

### Host Namespaces
| Check | Fail Condition | Field Path |
|-------|---------------|------------|
| HostProcess | `spec.containers[*].securityContext.windowsOptions.hostProcess: true` | container or pod level |
| Host Namespaces | `spec.hostNetwork: true` | pod level |
| Host Namespaces | `spec.hostPID: true` | pod level |
| Host Namespaces | `spec.hostIPC: true` | pod level |

### Privileged Containers
| Check | Fail Condition | Field Path |
|-------|---------------|------------|
| Privileged | `spec.containers[*].securityContext.privileged: true` | any container |
| Privileged | `spec.initContainers[*].securityContext.privileged: true` | any init container |

### Capabilities
| Check | Fail Condition | Field Path |
|-------|---------------|------------|
| Capabilities | `capabilities.add` contains anything other than: `AUDIT_WRITE`, `CHOWN`, `DAC_OVERRIDE`, `FOWNER`, `FSETID`, `KILL`, `MKNOD`, `NET_BIND_SERVICE`, `SETFCAP`, `SETGID`, `SETPCAP`, `SETUID`, `SYS_CHROOT` | any container |

### HostPath Volumes
| Check | Fail Condition | Field Path |
|-------|---------------|------------|
| HostPath Volumes | `spec.volumes[*].hostPath` is set | pod level |

### Host Ports
| Check | Fail Condition | Field Path |
|-------|---------------|------------|
| Host Ports | `spec.containers[*].ports[*].hostPort` is set and non-zero | any container |

### AppArmor
| Check | Fail Condition | Field Path |
|-------|---------------|------------|
| AppArmor | Profile set to value other than `runtime/default` or `localhost/*` | annotation or securityContext |

### SELinux
| Check | Fail Condition | Field Path |
|-------|---------------|------------|
| SELinux | `seLinuxOptions.type` is set to anything other than empty, `container_t`, `container_init_t`, `container_kvm_t` | pod or container level |

### /proc Mount Type
| Check | Fail Condition | Field Path |
|-------|---------------|------------|
| /proc Mount | `spec.containers[*].securityContext.procMount` is set to anything other than `Default` | any container |

### Seccomp (Baseline)
| Check | Fail Condition | Field Path |
|-------|---------------|------------|
| Seccomp | `seccompProfile.type` is `Unconfined` | pod or container level |

### Sysctls
| Check | Fail Condition | Field Path |
|-------|---------------|------------|
| Sysctls | `spec.securityContext.sysctls` contains sysctl not in allowed list: `kernel.shm_rmid_forced`, `net.ipv4.ip_local_port_range`, `net.ipv4.ip_unprivileged_port_start`, `net.ipv4.tcp_syncookies`, `net.ipv4.ping_group_range` | pod level |

## Restricted Level Checks

A Pod classified as Baseline FAILS Restricted (stays Baseline) if ANY of these are true:

### Volume Types
| Check | Fail Condition | Field Path |
|-------|---------------|------------|
| Volume Types | Volume uses type other than: `configMap`, `csi`, `downwardAPI`, `emptyDir`, `ephemeral`, `persistentVolumeClaim`, `projected`, `secret` | `spec.volumes[*]` |

### Privilege Escalation
| Check | Fail Condition | Field Path |
|-------|---------------|------------|
| Privilege Escalation | `allowPrivilegeEscalation` is `true` or not set (defaults true) | any container |

### Running as Non-root
| Check | Fail Condition | Field Path |
|-------|---------------|------------|
| Running as Non-root | `runAsNonRoot` is not `true` at pod level AND not `true` at every container level | pod + container level |

### Running as Non-root User (v1.23+)
| Check | Fail Condition | Field Path |
|-------|---------------|------------|
| Non-root User | `runAsUser` is `0` | pod or container level |

### Seccomp (Restricted)
| Check | Fail Condition | Field Path |
|-------|---------------|------------|
| Seccomp | `seccompProfile.type` is not set to `RuntimeDefault` or `Localhost` at pod level, AND not set on every container | pod + container level |

### Capabilities (Restricted)
| Check | Fail Condition | Field Path |
|-------|---------------|------------|
| Capabilities (drop) | `capabilities.drop` does not include `ALL` | any container |
| Capabilities (add) | `capabilities.add` contains anything other than `NET_BIND_SERVICE` | any container |

## PSS Report Template

For each Pod/workload:

```
POD SECURITY STANDARDS ASSESSMENT
Resource: [kind/name] in [namespace]
Determined Level: [Restricted | Baseline | Privileged]

Baseline Checks:
  [PASS] Host Namespaces: hostNetwork=false, hostPID=false, hostIPC=false
  [PASS] Privileged: privileged=false
  [FAIL] Capabilities: adds SYS_ADMIN (not in Baseline allowed list)
  ...

Restricted Checks (if Baseline passed):
  [PASS] Privilege Escalation: allowPrivilegeEscalation=false
  [FAIL] Seccomp: seccompProfile not set (required: RuntimeDefault or Localhost)
  [PASS] Run as Non-root: runAsNonRoot=true
  ...

Fields blocking higher level:
  - securityContext.seccompProfile: not set (need RuntimeDefault or Localhost)
  - capabilities.drop: does not include ALL

Remediation to reach Restricted:
  1. Add spec.securityContext.seccompProfile.type: RuntimeDefault
  2. Add capabilities.drop: [ALL] to each container
```
