# Kubernetes Resource Cross-Reference Map

Complete mapping of how Kubernetes resources reference each other. Use this to systematically trace every dependency.

## Reference Types

### By Name (exact string match)

| Source Kind | Source Field | Target Kind | Namespace Scoped |
|-------------|------------|-------------|------------------|
| Deployment/StatefulSet/DaemonSet/Job/CronJob | `spec.template.spec.serviceAccountName` | ServiceAccount | Yes |
| Deployment/StatefulSet/DaemonSet/Job/CronJob | `spec.template.spec.volumes[].configMap.name` | ConfigMap | Yes |
| Deployment/StatefulSet/DaemonSet/Job/CronJob | `spec.template.spec.volumes[].secret.secretName` | Secret | Yes |
| Deployment/StatefulSet/DaemonSet/Job/CronJob | `spec.template.spec.volumes[].persistentVolumeClaim.claimName` | PersistentVolumeClaim | Yes |
| Deployment/StatefulSet/DaemonSet/Job/CronJob | `spec.template.spec.volumes[].projected.sources[].configMap.name` | ConfigMap | Yes |
| Deployment/StatefulSet/DaemonSet/Job/CronJob | `spec.template.spec.volumes[].projected.sources[].secret.name` | Secret | Yes |
| Deployment/StatefulSet/DaemonSet/Job/CronJob | `spec.template.spec.imagePullSecrets[].name` | Secret | Yes |
| Container | `env[].valueFrom.configMapKeyRef.name` | ConfigMap | Yes |
| Container | `env[].valueFrom.configMapKeyRef.key` | ConfigMap `.data` key | Yes |
| Container | `env[].valueFrom.secretKeyRef.name` | Secret | Yes |
| Container | `env[].valueFrom.secretKeyRef.key` | Secret `.data` key | Yes |
| Container | `envFrom[].configMapRef.name` | ConfigMap | Yes |
| Container | `envFrom[].secretRef.name` | Secret | Yes |
| Ingress | `spec.rules[].http.paths[].backend.service.name` | Service | Yes |
| Ingress | `spec.tls[].secretName` | Secret (TLS) | Yes |
| Ingress | `spec.ingressClassName` | IngressClass | No |
| Route (OpenShift) | `spec.to.name` | Service | Yes |
| Service | (via selector, see below) | Pod | Yes |
| RoleBinding | `roleRef.name` | Role | Yes |
| ClusterRoleBinding | `roleRef.name` | ClusterRole | No |
| RoleBinding/ClusterRoleBinding | `subjects[].name` (kind: ServiceAccount) | ServiceAccount | Yes |
| HorizontalPodAutoscaler | `spec.scaleTargetRef.name` | Deployment/StatefulSet | Yes |
| PodDisruptionBudget | (via selector, see below) | Pod | Yes |
| NetworkPolicy | (via selector, see below) | Pod | Yes |
| CronJob | `spec.jobTemplate.spec.template.spec.*` | Same as Deployment template | Yes |
| VolumeSnapshot | `spec.source.persistentVolumeClaimName` | PersistentVolumeClaim | Yes |

### By Label Selector (key-value match)

| Source Kind | Source Field | Target Kind | Match Rule |
|-------------|------------|-------------|------------|
| Service | `spec.selector` | Pod (via Deployment template) | ALL selector labels must exist on Pod |
| NetworkPolicy | `spec.podSelector.matchLabels` | Pod | ALL labels must match |
| NetworkPolicy | `spec.ingress[].from[].podSelector` | Pod | Source pods for ingress rules |
| NetworkPolicy | `spec.egress[].to[].podSelector` | Pod | Destination pods for egress rules |
| PodDisruptionBudget | `spec.selector.matchLabels` | Pod | ALL labels must match |
| HorizontalPodAutoscaler | (via scaleTargetRef) | Deployment/StatefulSet | Name match, not label |

### By Port (numeric or named match)

| Source Kind | Source Field | Target Kind | Target Field |
|-------------|------------|-------------|--------------|
| Service | `spec.ports[].targetPort` | Pod | `spec.containers[].ports[].containerPort` or port name |
| Ingress | `spec.rules[].http.paths[].backend.service.port.number` | Service | `spec.ports[].port` |
| Ingress | `spec.rules[].http.paths[].backend.service.port.name` | Service | `spec.ports[].name` |
| Route | `spec.port.targetPort` | Service | `spec.ports[].name` or `spec.ports[].port` |
| NetworkPolicy | `spec.ingress[].ports[].port` | Pod | `spec.containers[].ports[].containerPort` |

## Validation Algorithm

For each manifest set, follow this order:

1. **Inventory**: List all resources by kind, name, namespace
2. **Selector Resolution**: For each Service/NetworkPolicy/PDB, find matching Pods
3. **Name Resolution**: For each name reference, verify target exists
4. **Port Resolution**: For each port reference, verify target port exists
5. **RBAC Chain**: For each serviceAccountName, trace SA -> RoleBinding -> Role
6. **Namespace Check**: Verify all cross-references are in the same namespace
7. **Orphan Detection**: Find resources not referenced by anything (potential dead config)
