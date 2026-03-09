# kube-linter Checks Reference

Common kube-linter checks with descriptions and fixes.

**Source**: [kube-linter Documentation](https://docs.kubelinter.io/)

---

## Security Checks

| Check Name | Description | Fix |
|------------|-------------|-----|
| `privileged-container` | Container runs in privileged mode | Set `securityContext.privileged: false` |
| `run-as-non-root` | Container may run as root | Add `securityContext.runAsNonRoot: true` |
| `no-read-only-root-fs` | Root filesystem is writable | Add `securityContext.readOnlyRootFilesystem: true` |
| `host-ipc` | Pod uses host IPC namespace | Remove or set `hostIPC: false` |
| `host-network` | Pod uses host network | Remove or set `hostNetwork: false` |
| `host-pid` | Pod uses host PID namespace | Remove or set `hostPID: false` |
| `writable-host-mount` | HostPath volume is writable | Set `readOnly: true` on hostPath mount |
| `drop-net-raw-capability` | NET_RAW capability not dropped | Drop NET_RAW in `securityContext.capabilities.drop` |

---

## Resource Management

| Check Name | Description | Fix |
|------------|-------------|-----|
| `unset-cpu-requirements` | No CPU requests/limits set | Add `resources.requests.cpu` and `resources.limits.cpu` |
| `unset-memory-requirements` | No memory requests/limits set | Add `resources.requests.memory` and `resources.limits.memory` |
| `no-liveness-probe` | Missing liveness probe | Add `livenessProbe` configuration |
| `no-readiness-probe` | Missing readiness probe | Add `readinessProbe` configuration |

---

## Best Practices

| Check Name | Description | Fix |
|------------|-------------|-----|
| `latest-tag` | Image uses 'latest' tag | Pin to specific version (e.g., `nginx:1.25.3`) |
| `required-label-owner` | Missing 'owner' label | Add `metadata.labels.owner` |
| `required-annotation-email` | Missing contact email annotation | Add `metadata.annotations.email` |
| `default-service-account` | Using default ServiceAccount | Create and use dedicated ServiceAccount |
| `no-anti-affinity` | No pod anti-affinity rules | Add anti-affinity for HA |

---

## Deprecated APIs

| Check Name | Description | Fix |
|------------|-------------|-----|
| `no-extensions-v1beta` | Using deprecated extensions/v1beta | Update to stable API version |
| `no-deprecated-api` | Using deprecated API version | Migrate to current API version |

---

## All kube-linter Checks

List all checks with:
```bash
kube-linter checks list
```

Get check details:
```bash
kube-linter checks describe <check-name>
```

---

## Configuring Checks

### Enable All Checks

```yaml
# .kube-linter.yaml
checks:
  addAllBuiltIn: true
```

### Exclude Specific Checks

```yaml
checks:
  doNotAutoAddDefaults: true
  include:
    - privileged-container
    - run-as-non-root
    - no-read-only-root-fs
  exclude:
    - unset-cpu-requirements
    - latest-tag
```

### Ignore via Annotations

In manifest:
```yaml
metadata:
  annotations:
    ignore-check.kube-linter.io/no-read-only-root-fs: "Legacy app requires writable filesystem"
    ignore-check.kube-linter.io/unset-cpu-requirements: "Batch job with variable CPU needs"
```

---

## Check Severity Mapping

| kube-linter Severity | Our Mapping |
|---------------------|-------------|
| Error | critical |
| Warning | warning |
| Info | info |

---

## Common Exclusions

### Development/Testing

```yaml
# Relax requirements for dev/test
exclude:
  - unset-cpu-requirements
  - unset-memory-requirements
  - no-liveness-probe
  - no-readiness-probe
  - latest-tag
```

### Legacy Applications

```yaml
# For apps that can't be easily changed
exclude:
  - no-read-only-root-fs
  - run-as-non-root
  - drop-net-raw-capability
```

### Batch Jobs

```yaml
# For one-off jobs
exclude:
  - no-liveness-probe
  - no-readiness-probe
  - no-anti-affinity
```

---

## References

- [kube-linter Checks Documentation](https://docs.kubelinter.io/#/generated/checks)
- [Configuring kube-linter](https://github.com/stackrox/kube-linter/blob/main/docs/configuring-kubelinter.md)
- [kube-linter GitHub](https://github.com/stackrox/kube-linter)
