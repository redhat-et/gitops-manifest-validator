# Intent Validation Question Templates

## Purpose

When reviewing Kubernetes manifests, design decisions are often implicit. These question templates help surface unstated assumptions and validate that the manifest reflects deliberate intent rather than accidental configuration.

## Port Exposure Questions

### Unexplained ports
**Trigger:** Container exposes ports that don't have an obvious purpose based on the container name/image.

- "Port {port} is exposed on container '{name}'. What service or protocol runs on this port?"
- "Port 5432/3306/27017 (database port) is exposed on a non-database container. Is this container proxying database connections, or is this a misconfiguration?"
- "This Service uses type: LoadBalancer, which exposes ports publicly. Is public exposure intended for port {port} ({name})?"

### Multiple ports on one container
**Trigger:** Container exposes 3+ ports.

- "Container '{name}' exposes {count} ports. Can you describe what each port is for? (e.g., 8080=HTTP API, 9090=metrics, 8443=admin)"
- "Are all {count} ports intended to be externally accessible, or should some be internal-only?"

### Database ports on application containers
**Trigger:** Ports 5432, 3306, 27017, 6379, 9042, 7000, 5984 on non-database images.

- "Port {port} is commonly used by {database}. Is this container embedding a database, proxying connections, or is this port assignment unintentional?"

## Replica Count Questions

### Single replica in production
**Trigger:** replicas: 1 in a namespace containing "prod" or with labels indicating production.

- "This Deployment has a single replica in production. Is this intentional? If so, what is the recovery strategy when this Pod is evicted?"
- "Single replica with Recreate strategy means downtime during updates. Is zero-downtime not required, or is this a constraint that should be documented?"
- "Is this workload a singleton by design (e.g., leader election, file lock)? If so, consider StatefulSet or a Job instead."

### Lock file or PVC with single replica
**Trigger:** replicas: 1 AND (PVC with ReadWriteOnce OR env vars referencing lock files).

- "This Deployment uses a lock file/RWO volume with a single replica. This looks like a singleton pattern. Should this be a StatefulSet with a leader election sidecar instead?"
- "What happens if this Pod crashes and the lock file is stale? Is there a cleanup mechanism?"

### High replica count without HPA
**Trigger:** replicas > 10 without an associated HorizontalPodAutoscaler.

- "This Deployment has {count} static replicas. Is the load constant, or should this use HPA for dynamic scaling?"

## Architectural Pattern Questions

### Multi-container Pod classification
**Trigger:** Pod spec with 2+ containers (not counting init containers).

- "This Pod has {count} containers. What pattern does this implement? (sidecar, ambassador, adapter, or tightly-coupled services)"
- "Containers '{a}' and '{b}' share volume '{volume}'. Which container is the writer and which is the reader?"

### Init container dependency
**Trigger:** initContainers present.

- "Init container '{name}' runs before the main containers. What happens if it fails? Is the failure mode acceptable (Pod stays Pending indefinitely)?"
- "Does init container '{name}' need to be idempotent? If the Pod restarts, the init container runs again."

### Containers that should be separate Deployments
**Trigger:** Multiple containers all exposing application ports (not metrics/admin ports).

- "Containers '{a}' and '{b}' both expose application ports. Should these be separate Deployments so they can scale and update independently?"
- "These containers have different resource profiles ({a}: {resources_a}, {b}: {resources_b}). Would separate Deployments allow better bin-packing and scaling?"

## Strategy and Update Questions

### Recreate strategy in production
**Trigger:** strategy.type: Recreate in production namespace.

- "Recreate strategy causes downtime during updates. Is this required (e.g., exclusive resource access), or would RollingUpdate be acceptable?"

### Missing disruption budget
**Trigger:** Deployment with replicas > 1 but no PodDisruptionBudget.

- "No PodDisruptionBudget exists for this multi-replica Deployment. During node maintenance, all replicas could be evicted simultaneously. Is this acceptable?"

## Service Exposure Questions

### LoadBalancer type
**Trigger:** Service type: LoadBalancer.

- "This Service uses type: LoadBalancer, which provisions a cloud load balancer (additional cost). Is this intentional, or would ClusterIP/NodePort/Ingress be sufficient?"
- "LoadBalancer exposes all listed ports publicly. Should any ports (e.g., metrics, admin) be restricted?"

### ExternalName or headless service
**Trigger:** Service type: ExternalName or clusterIP: None.

- "This headless Service creates DNS records for each Pod. Is this for StatefulSet discovery, or is ClusterIP intended?"

## Resource Intent Questions

### No requests or limits
**Trigger:** Container without resource requests or limits.

- "Container '{name}' has no resource requests. This means it can be scheduled on any node and may be evicted first under pressure. Is this intentional for a best-effort workload?"

### Extremely high or low resources
**Trigger:** CPU > 4 cores or memory > 8Gi, or CPU < 10m or memory < 16Mi.

- "Container '{name}' requests {cpu} CPU and {memory} memory. Can you confirm this matches the workload's actual resource consumption?"
