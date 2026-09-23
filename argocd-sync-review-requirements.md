# GitOps manifest review — requirements

## Scope

These requirements define checks performed during the pull request workflow, before changes are merged and synced. By shifting evaluation left into the CI layer, teams catch blast-radius issues at proposal time — when the cost of correction is lowest and the full review context (diff, approvers, discussion) is available.

Because a Git repository has no inherent awareness of live cluster state, the CI process integrates with a cluster management hub (e.g. Red Hat Advanced Cluster Management / ACM) to query running environments. This gives the PR check access to the same live-state information that would otherwise only be available at sync time, without coupling the validation logic to the sync engine.

---

## Guiding principle

> Evaluate every proposed change against live cluster state during the PR review cycle, not at sync time. The pull request is where changes are proposed, reviewed, and approved — blast-radius analysis belongs in that same workflow.

---

## Integration model

### PR trigger

The check runs as a CI job on pull requests that modify Kubernetes manifests. It posts its findings — hard blocks, availability warnings, blast-radius warnings, and recommendations — as structured comments on the PR.

### Live cluster access via ACM

The CI job queries ACM (or an equivalent hub) to obtain live resource state from managed clusters. ACM provides:

- **Cluster inventory:** which clusters and namespaces the manifests target.
- **Live resource state:** current spec of Deployments, StatefulSets, Services, PVCs, PDBs, ConfigMaps, and cluster-scoped resources across managed clusters.
- **Workload cross-references:** which workloads reference a given ConfigMap, Secret, or other shared resource.

The CI job resolves the target cluster(s) from the manifest path, Application definition, or a mapping configuration, then queries ACM for the specific resources needed by each check.

### PR comment output

Results are posted as a structured PR comment containing:

1. **Hard blocks** — issues that must be resolved before merge. The CI check should report a failing status.
2. **Availability warnings** — risks of degraded service that reviewers should evaluate.
3. **Blast-radius warnings** — changes whose failure mode extends beyond the target workload or namespace.
4. **Recommendations** — suggested mitigations or sequencing for flagged changes.

---

## Hard block checks

A hard block marks the PR check as failed. The issue must be resolved in the PR before merge.

### HB-01 — Immutable field conflict

- **Trigger:** The incoming manifest changes a field that is immutable on the live resource (e.g. `spec.selector` or `spec.template.metadata.labels` on a Deployment or StatefulSet).
- **Detection:** Diff the incoming manifest against the live resource fetched via ACM. Flag any field listed as immutable in the resource's OpenAPI schema.
- **PR output:** Report the conflicting field name, current vs proposed value, and the target cluster(s) affected. Recommend a delete-and-recreate strategy if the change is intentional.

### HB-02 — PVC storage conflict

- **Trigger:** The incoming manifest changes `spec.storageClassName` or decreases `spec.resources.requests.storage` on an existing PersistentVolumeClaim.
- **Detection:** Fetch the live PVC via ACM and compare both fields.
- **PR output:** Report the conflict and affected cluster(s). Note that storage class changes and size reductions are not supported by the Kubernetes API on bound PVCs and will hard-fail at apply time.

### HB-03 — Service port removal

- **Trigger:** A port present on the live Service object is absent from the incoming manifest.
- **Detection:** Fetch the live Service via ACM and diff `spec.ports` against the incoming manifest.
- **PR output:** Report the removed port(s) and affected cluster(s). Recommend a coordinated cutover plan if the removal is intentional.

---

## Availability warning checks

An availability warning does not block merge but is surfaced prominently in the PR comment. Reviewers should assess the risk before approving.

### AW-01 — PodDisruptionBudget violation

- **Trigger:** The rollout strategy (e.g. `maxUnavailable`) combined with the current number of available pods would breach the `minAvailable` or `maxUnavailable` constraint defined in any matching PodDisruptionBudget.
- **Detection:** Fetch all PDBs in the namespace (via ACM) whose `selector` matches the workload's pod labels. Compute whether the proposed update would violate any constraint given current pod availability.
- **PR output:** Display the PDB name, the constraint, current available pod count, and affected cluster(s). Recommend adjusting the rollout strategy or scaling up before merging.

### AW-02 — Probe removal

- **Trigger:** A `livenessProbe` or `readinessProbe` present on a container in the live resource is absent from the incoming manifest.
- **Detection:** Diff `spec.containers[*].livenessProbe` and `spec.containers[*].readinessProbe` between the live resource (via ACM) and the incoming manifest for each container by name.
- **PR output:** Identify the container name and probe type removed, and the affected cluster(s). Recommend confirming the removal is intentional and not an accidental omission.

---

## Blast radius warning checks

A blast-radius warning does not block merge but is surfaced prominently in the PR comment. These indicate changes whose failure mode extends beyond the target workload or namespace.

### BR-01 — Cluster-scoped resource change

- **Trigger:** The incoming manifest targets a cluster-scoped resource kind: `CustomResourceDefinition`, `ClusterRole`, `ClusterRoleBinding`, or `StorageClass`.
- **Detection:** Inspect `apiVersion` and `kind` in the incoming manifest. Cross-reference against the list of cluster-scoped kinds via ACM's API discovery data.
- **PR output:** Display the resource kind, name, a summary of the fields that changed, and all clusters that would be affected. Recommend a staged rollout across clusters if multiple are targeted.

### BR-02 — Shared ConfigMap modification

- **Trigger:** The incoming manifest modifies a ConfigMap that is referenced by more than one workload in the cluster.
- **Detection:** Query ACM for all Deployments, StatefulSets, DaemonSets, and CronJobs across the target cluster(s). Identify those referencing the ConfigMap by name in `spec.template.spec.volumes`, `envFrom`, or `env[*].valueFrom.configMapKeyRef`. Flag if the count of referencing workloads is greater than one.
- **PR output:** List the referencing workload names and namespaces so reviewers can assess downstream impact. Recommend notifying owners of dependent workloads before merging.

---

## Post-merge behaviour

After the PR is merged and the change syncs:

1. The sync engine (ArgoCD) runs configured `PostSync` health checks and reports pass/fail.
2. The pre-sync live resource state is retained as a rollback snapshot for the duration of the `rollbackWindowSeconds` configured on the Application.
3. A structured audit event is emitted containing: sync timestamp, manifest digest, PR reference, checks that fired during the PR review, and final sync outcome.

---

## Out of scope

The following are explicitly handled elsewhere and must not be re-implemented here:

| Concern | Owner |
|---|---|
| Schema validation (kubeval / kubeconform) | CI pipeline — manifest validator |
| Plaintext secret detection | CI pipeline — secret scanning |
| Mutable image tag enforcement | CI pipeline — image policy |
| Missing resource limits / requests | CI pipeline — linting (kube-score, polaris) |
| RBAC escalation policy | CI pipeline — OPA / conftest |
| Replica count decisions | Rollout manager |
| HPA bound changes | Rollout manager |
| Environment promotion decisions | Rollout manager |
| Human approval workflow | Rollout manager |
