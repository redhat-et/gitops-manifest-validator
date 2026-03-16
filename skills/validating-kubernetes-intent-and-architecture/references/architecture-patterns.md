# Kubernetes Multi-Container Pod Patterns

## Sidecar Pattern

**Definition:** A helper container that extends/enhances the main container without modifying it.

**Identifying signals:**
- Secondary container shares a volume with the main container
- Secondary container has significantly fewer resources than the main container
- Secondary container name suggests auxiliary function (e.g., `log-agent`, `proxy`, `sync`)
- Secondary container does not expose ports (or only exposes metrics ports like 9090/9100)

**Common examples:**
- Log shipper (Fluentd/Filebeat reading from shared volume)
- Service mesh proxy (Envoy/Istio sidecar)
- Config reloader (watching ConfigMap changes)
- TLS termination proxy

**Questions to ask when detected:**
- Is this a standard infrastructure sidecar (e.g., Istio auto-injected) or custom?
- Does the sidecar lifecycle match the main container? (Should it survive main container restart?)
- Are resource requests proportional? (Sidecar should typically be 10-20% of main container)

## Init Container Pattern

**Definition:** A container that runs to completion before the main containers start.

**Identifying signals:**
- Listed under `initContainers` (not `containers`)
- Uses `command` or `args` for one-time operations
- Often has database/migration-related images
- May reference external services (databases, APIs)

**Common examples:**
- Database schema migration
- Configuration generation
- Dependency readiness check (wait-for-service)
- File/permission setup

**Questions to ask when detected:**
- What happens if the init container fails? Is the failure mode acceptable?
- Does it have a timeout? Init containers can block Pod startup indefinitely.
- Does it modify shared volumes that main containers depend on?
- Is the init container idempotent? (Critical for Pod restarts)

## Ambassador Pattern

**Definition:** A proxy container that handles outbound connections on behalf of the main container.

**Identifying signals:**
- Container name includes "proxy", "gateway", "ambassador"
- Container binds to localhost ports
- Main container connects to localhost instead of external services
- Container image is a known proxy (HAProxy, Envoy, custom proxy)

**Common examples:**
- Database connection pooling proxy (PgBouncer)
- API gateway for external service access
- Protocol translation (gRPC to REST)

**Questions to ask when detected:**
- Why not use a separate Service/Deployment for the proxy?
- Is the proxy introducing a single point of failure within the Pod?
- Are connection pool sizes configured appropriately for the replica count?

## Adapter Pattern

**Definition:** A container that transforms the main container's output into a standardized format.

**Identifying signals:**
- Container reads from shared volume in read-only mode
- Container exposes metrics or monitoring ports (9090, 9100, 8081)
- Container image references "exporter", "adapter", "converter"
- Container has minimal resource requirements

**Common examples:**
- Prometheus metrics exporter
- Log format converter
- Data format normalizer

**Questions to ask when detected:**
- Could this be a standalone Deployment (especially if multiple Pods need the same adapter)?
- Is the adapter stateless? If so, scaling independently might be better.
- Does the adapter add latency to the data path?

## When NOT to Use Multi-Container Pods

A multi-container Pod is wrong when:
- **Containers scale independently** -- use separate Deployments
- **Containers have different lifecycle requirements** -- one needs rolling updates, the other doesn't
- **Containers don't share data** -- no shared volumes or localhost communication
- **Container failure shouldn't affect the other** -- separate Pods with separate restart policies
- **Containers are different services** -- microservices should not be co-located

## Pattern Decision Matrix

| Signal | Likely Pattern | Key Question |
|--------|---------------|--------------|
| Shared volume, writes by one, reads by other | Sidecar or Adapter | Who is the "main" container? |
| initContainers entry | Init Container | Is the operation idempotent? |
| localhost-only ports | Ambassador | Why not a separate Service? |
| Metrics/monitoring port only | Adapter | Could this be a standalone exporter? |
| Same image, different args | Unclear -- investigate | Are these really different functions or misconfigured replicas? |
| All containers expose external ports | Likely wrong pattern | These should probably be separate Deployments |
