# ArgoCD sync-time manifest review — requirements

## Scope

These requirements define checks performed by ArgoCD at sync time, after a manifest diff has been received. They are limited to evaluations that require live cluster state. Checks that can be resolved from the manifest file alone belong in the CI/CD pipeline and are explicitly out of scope here.

---

## Guiding principle

> A check belongs in this layer if and only if it requires a live cluster query (`kubectl get` or equivalent) to evaluate. If the check needs only the manifest file, it belongs in CI.

---

## Hard block checks

A hard block aborts the sync immediately. No human confirmation can override it. The operator must resolve the conflict in the manifest before re-triggering sync.

### HB-01 — Immutable field conflict

- **Trigger:** The incoming manifest changes a field that is immutable on the live resource (e.g. `spec.selector` or `spec.template.metadata.labels` on a Deployment or StatefulSet).
- **Detection:** Diff the incoming manifest against the live resource via the Kubernetes API. Flag any field listed as immutable in the resource's OpenAPI schema.
- **Action:** Abort sync. Surface the conflicting field name and current vs proposed value in the sync error output.

### HB-02 — PVC storage conflict

- **Trigger:** The incoming manifest changes `spec.storageClassName` or decreases `spec.resources.requests.storage` on an existing PersistentVolumeClaim.
- **Detection:** Fetch the live PVC and compare both fields.
- **Action:** Abort sync. Storage class changes and storage size reductions are not supported by the Kubernetes API on bound PVCs and will hard-fail at apply time.

### HB-03 — Service port removal

- **Trigger:** A port present on the live Service object is absent from the incoming manifest.
- **Detection:** Fetch the live Service and diff `spec.ports` against the incoming manifest.
- **Action:** Abort sync. Removing a port while clients may be connected is a breaking change that cannot be safely applied without a coordinated cutover.

---

## Availability pause checks

An availability pause suspends the sync and requires explicit operator confirmation before proceeding. These checks indicate a risk of degraded service but are not guaranteed failures.

### AP-01 — PodDisruptionBudget violation

- **Trigger:** The rollout strategy (e.g. `maxUnavailable`) combined with the current number of available pods would breach the `minAvailable` or `maxUnavailable` constraint defined in any matching PodDisruptionBudget.
- **Detection:** Fetch all PDBs in the namespace whose `selector` matches the workload's pod labels. Compute whether the proposed update would violate any constraint given current pod availability.
- **Action:** Pause sync. Display the PDB name, the constraint, and the current available pod count.

### AP-02 — Probe removal

- **Trigger:** A `livenessProbe` or `readinessProbe` present on a container in the live resource is absent from the incoming manifest.
- **Detection:** Diff `spec.containers[*].livenessProbe` and `spec.containers[*].readinessProbe` between the live resource and the incoming manifest for each container by name.
- **Action:** Pause sync. Identify the container name and probe type that was removed.

---

## Blast radius pause checks

A blast radius pause suspends the sync and requires explicit operator confirmation before proceeding. These checks indicate a change whose failure mode extends beyond the target workload or namespace.

### BR-01 — Cluster-scoped resource change

- **Trigger:** The incoming manifest targets a cluster-scoped resource kind: `CustomResourceDefinition`, `ClusterRole`, `ClusterRoleBinding`, or `StorageClass`.
- **Detection:** Inspect `apiVersion` and `kind` in the incoming manifest. Cross-reference against the list of cluster-scoped kinds via the API server's discovery endpoint.
- **Action:** Pause sync. Display the resource kind, name, and a summary of the fields that changed.

### BR-02 — Shared ConfigMap modification

- **Trigger:** The incoming manifest modifies a ConfigMap that is referenced by more than one workload in the cluster.
- **Detection:** Fetch all Deployments, StatefulSets, DaemonSets, and CronJobs across all namespaces. Identify those referencing the ConfigMap by name in `spec.template.spec.volumes`, `envFrom`, or `env[*].valueFrom.configMapKeyRef`. Flag if the count of referencing workloads is greater than one.
- **Action:** Pause sync. List the referencing workload names and namespaces so the operator can assess downstream impact.

---

## Post-sync behaviour

After a successful sync, ArgoCD must:

1. Run configured `PostSync` health checks and report pass/fail.
2. Retain the pre-sync live resource state as a rollback snapshot for the duration of the `rollbackWindowSeconds` configured on the Application.
3. Emit a structured audit event containing: sync timestamp, manifest digest, operator identity (if confirmation was required), checks that fired, and final outcome.

---

## Out of scope

The following are explicitly handled upstream and must not be re-implemented here:

| Concern | Owner |
|---|---|
| Schema validation (kubeval / kubeconform) | CI pipeline |
| Plaintext secret detection | CI pipeline — secret scanning |
| Mutable image tag enforcement | CI pipeline — image policy |
| Missing resource limits / requests | CI pipeline — linting (kube-score, polaris) |
| RBAC escalation policy | CI pipeline — OPA / conftest |
| Replica count decisions | Rollout manager |
| HPA bound changes | Rollout manager |
| Environment promotion decisions | Rollout manager |
| Human approval workflow | Rollout manager |
