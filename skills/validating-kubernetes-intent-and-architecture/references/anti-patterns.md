# Kubernetes Anti-Patterns

## Deployment Anti-Patterns

### 1. Deploying into the default namespace
**Signal:** `namespace: default` or no namespace specified.
**Problem:** No resource isolation, RBAC boundaries, or quota enforcement. Resources from different teams collide.
**Ask:** "Is the default namespace intentional, or should this deploy to a team/environment-specific namespace?"

### 2. Using latest tag or no tag
**Signal:** `image: myapp` or `image: myapp:latest`
**Problem:** Non-deterministic deployments. Different nodes may pull different versions. Rollbacks are impossible.
**Ask:** "This image uses ':latest' (or no tag). What specific version should be pinned?"

### 3. Missing health probes
**Signal:** No `livenessProbe` or `readinessProbe` defined.
**Problem:** Kubernetes cannot detect application failures or readiness. Traffic routes to unhealthy Pods.
**Ask:** "No health probes are defined. What endpoint or command indicates this application is healthy and ready to serve traffic?"

### 4. Privileged containers without justification
**Signal:** `securityContext.privileged: true` or `allowPrivilegeEscalation: true`
**Problem:** Container has full host access. Container escape = host compromise.
**Ask:** "This container runs in privileged mode. What specific host capability does it need? Can it use targeted capabilities instead?"

### 5. Running as root
**Signal:** No `runAsNonRoot: true` or `runAsUser` not set, or explicitly `runAsUser: 0`.
**Problem:** Filesystem exploits run with root privileges inside the container.
**Ask:** "This container runs as root. Does the application require root, or can it run as a non-root user?"

## Architecture Anti-Patterns

### 6. Distributed monolith
**Signal:** Multiple Deployments that always deploy together, share a database, and have synchronous call chains.
**Problem:** Complexity of microservices with none of the benefits. Failures cascade.
**Ask:** "These services appear tightly coupled (shared database, synchronous dependencies). Would a single Deployment be simpler and more reliable?"

### 7. Sidecar sprawl
**Signal:** Pod with 4+ containers, each with different concerns.
**Problem:** Pod becomes complex to debug, resource accounting is unclear, failure domain is too wide.
**Ask:** "This Pod has {count} containers. Can any of these run as separate Deployments? Each additional container increases the Pod's blast radius."

### 8. Stateful Deployment (should be StatefulSet)
**Signal:** Deployment with PVC using ReadWriteOnce, replicas: 1, or stable hostname requirements.
**Problem:** Deployment doesn't guarantee Pod identity, stable storage binding, or ordered startup/shutdown.
**Ask:** "This Deployment has characteristics of a stateful workload (RWO PVC, single replica). Should this be a StatefulSet?"

### 9. ConfigMap as database
**Signal:** ConfigMap with very large data entries (>1KB per key) or many keys (>20).
**Problem:** ConfigMap is stored in etcd with a 1MB limit. Large ConfigMaps cause API server pressure.
**Ask:** "This ConfigMap contains {size} of data. Should this be in a PersistentVolume or external configuration store instead?"

### 10. Hardcoded environment-specific values
**Signal:** Environment variables with literal hostnames, IP addresses, or credentials.
**Problem:** Manifest cannot be reused across environments. Secrets in plain text.
**Ask:** "This manifest contains hardcoded values ({examples}). Should these come from ConfigMaps, Secrets, or be parameterized for different environments?"

## Networking Anti-Patterns

### 11. Exposing internal ports via LoadBalancer
**Signal:** Service type: LoadBalancer with ports like 9090 (metrics), 8081 (admin), 5432 (database).
**Problem:** Internal services are publicly accessible. Attack surface unnecessarily expanded.
**Ask:** "Port {port} on a LoadBalancer Service is publicly accessible. Should this port be internal-only (ClusterIP) or protected by NetworkPolicy?"

### 12. No NetworkPolicy (implicit allow-all)
**Signal:** No NetworkPolicy resources in the manifest set.
**Problem:** Any Pod can communicate with any other Pod. No network segmentation.
**Ask:** "No NetworkPolicy is defined. Should this workload restrict ingress/egress traffic?"

### 13. hostNetwork or hostPort usage
**Signal:** `hostNetwork: true` or `hostPort` set on container ports.
**Problem:** Bypasses Kubernetes networking, limits scheduling, creates port conflicts.
**Ask:** "This Pod uses hostNetwork/hostPort. What specific requirement prevents using standard Kubernetes networking?"

## Storage Anti-Patterns

### 14. EmptyDir for persistent data
**Signal:** `emptyDir` volume used for data that appears to need persistence (data paths, database paths).
**Problem:** Data is lost when Pod is evicted/restarted.
**Ask:** "Volume '{name}' uses emptyDir for path '{path}'. Is this data ephemeral, or should it use a PersistentVolumeClaim?"

### 15. ReadWriteMany without need
**Signal:** PVC with `accessMode: ReadWriteMany` but only one Pod mounting it.
**Problem:** RWX storage is more expensive and has fewer provider options. Often a leftover from copy-paste.
**Ask:** "This PVC uses ReadWriteMany but appears to be mounted by a single Pod. Should this be ReadWriteOnce?"

## Scaling Anti-Patterns

### 16. Vertical scaling instead of horizontal
**Signal:** Single replica with very high resource requests (>4 CPU, >16Gi memory).
**Problem:** Single large Pod has no redundancy and is harder to schedule.
**Ask:** "This workload uses {cpu} CPU and {memory} memory in a single replica. Can it be refactored to scale horizontally with smaller replicas?"

### 17. HPA without resource requests
**Signal:** HPA targeting a Deployment where containers lack resource requests.
**Problem:** HPA cannot calculate utilization percentage without resource requests.
**Ask:** "HPA targets this Deployment but containers have no resource requests. HPA will not function. What CPU/memory requests should be set?"

## Security Anti-Patterns

### 18. Secrets in environment variables
**Signal:** Secret values referenced via `env[].valueFrom.secretKeyRef` without volume-mounted secrets.
**Problem:** Environment variables appear in process listings, crash dumps, and debug endpoints.
**Ask:** "Secrets are injected via environment variables. For sensitive credentials, consider volume-mounted secrets which are more secure. Is env-based injection required?"

### 19. No security context
**Signal:** No `securityContext` at Pod or container level.
**Problem:** Container runs with default permissions (often root, writable filesystem, all capabilities).
**Ask:** "No security context is defined. Should this container run as non-root with a read-only filesystem and dropped capabilities?"
