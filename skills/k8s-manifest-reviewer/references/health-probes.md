# Health Probes Configuration

Comprehensive guide to liveness, readiness, and startup probes based on official Kubernetes documentation.

## Overview

Three types of health probes for container lifecycle management:

| Probe Type | Purpose | Failure Action |
|------------|---------|----------------|
| **Liveness** | Detect deadlocks, restart broken containers | Kill and restart container |
| **Readiness** | Control traffic routing to pods | Remove from Service endpoints |
| **Startup** | Handle slow-starting applications | Delay other probes until started |

## Liveness Probes

**Purpose**: Determine when to restart a container

**Use when**: Application can enter broken state (deadlock, infinite loop) that requires restart

### Liveness Probe Example

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: liveness-http
spec:
  containers:
  - name: app
    image: myapp:1.0
    livenessProbe:
      httpGet:
        path: /healthz
        port: 8080
        httpHeaders:
        - name: Custom-Header
          value: Awesome
      initialDelaySeconds: 15
      periodSeconds: 20
      timeoutSeconds: 1
      successThreshold: 1
      failureThreshold: 3
```

**How it works**:
- Kubelet sends HTTP GET to `/healthz:8080` every 20 seconds
- First probe after 15 seconds (initial delay)
- Success if status code 200-399
- Failure if timeout (1s) or non-2xx/3xx status
- Restart after 3 consecutive failures

### Liveness Probe Best Practices

**1. Use lightweight checks**:
```yaml
# ✅ GOOD: Simple health endpoint
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
  periodSeconds: 10

# ❌ BAD: Expensive operation
livenessProbe:
  httpGet:
    path: /full-system-check  # Database queries, external APIs
    port: 8080
```

**2. Higher failure threshold than readiness**:
```yaml
# Liveness: 3 failures × 10s = 30s before restart
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
  periodSeconds: 10
  failureThreshold: 3

# Readiness: 2 failures × 5s = 10s before removing from service
readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  periodSeconds: 5
  failureThreshold: 2
```

**3. Avoid external dependencies**:
```yaml
# ✅ GOOD: Check app health only
GET /healthz
→ Check: Can app process requests?
→ Return: 200 OK

# ❌ BAD: Check external dependencies
GET /healthz
→ Check: Database reachable? Cache available?
→ Problem: Restarts won't fix external issues
```

**4. Set appropriate initial delay**:
```yaml
# For fast-starting apps
livenessProbe:
  initialDelaySeconds: 10

# For slow-starting apps (use startupProbe instead)
livenessProbe:
  initialDelaySeconds: 60  # Or use startupProbe
```

## Readiness Probes

**Purpose**: Determine when container is ready to accept traffic

**Use when**: Application needs time to load data, warm caches, or initialize before serving

### Readiness Probe Example

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: readiness-http
spec:
  containers:
  - name: app
    image: myapp:1.0
    readinessProbe:
      httpGet:
        path: /ready
        port: 8080
      initialDelaySeconds: 5
      periodSeconds: 5
      timeoutSeconds: 1
      successThreshold: 1
      failureThreshold: 2
```

**How it works**:
- Kubelet sends HTTP GET to `/ready:8080` every 5 seconds
- Pod added to Service endpoints only when ready
- Removed from endpoints on failure
- Container NOT restarted on failure

### Readiness Probe Best Practices

**1. Check application readiness, not just process**:
```yaml
# ✅ GOOD: Check if app can serve requests
GET /ready
→ Check: Data loaded? Connections established? Caches warm?
→ Return: 200 when truly ready

# ❌ BAD: Just check if process alive
GET /ready
→ Return: Always 200 if process running
```

**2. Lower failure threshold than liveness**:
```yaml
# Readiness: Remove from LB quickly
readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  periodSeconds: 5
  failureThreshold: 2  # 10 seconds total

# Liveness: Wait longer before restart
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
  periodSeconds: 10
  failureThreshold: 3  # 30 seconds total
```

**3. Include external dependency checks**:
```yaml
# For readiness, checking dependencies is appropriate
GET /ready
→ Check: Database connection pool ready?
→ Check: Required services available?
→ Check: Configuration loaded?
→ Return: 200 only when all ready
```

**4. Use during rolling updates**:
```yaml
apiVersion: apps/v1
kind: Deployment
spec:
  replicas: 3
  strategy:
    rollingUpdate:
      maxUnavailable: 1
      maxSurge: 1
  template:
    spec:
      containers:
      - name: app
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
# New pods must pass readiness before old pods terminated
```

## Startup Probes

**Purpose**: Handle slow-starting applications without affecting liveness/readiness probes

**Use when**: Application takes > 30 seconds to start

### Startup Probe Example

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: startup-http
spec:
  containers:
  - name: slow-app
    image: slow-app:1.0
    startupProbe:
      httpGet:
        path: /startup
        port: 8080
      initialDelaySeconds: 0
      periodSeconds: 10
      failureThreshold: 30  # 30 × 10s = 5 minutes max startup time
    livenessProbe:
      httpGet:
        path: /healthz
        port: 8080
      periodSeconds: 10
      failureThreshold: 3
    readinessProbe:
      httpGet:
        path: /ready
        port: 8080
      periodSeconds: 5
```

**How it works**:
- Startup probe runs first (every 10s, max 30 attempts = 5 min)
- Liveness and readiness probes disabled until startup succeeds
- Once startup succeeds, liveness and readiness take over
- Startup probe no longer runs after success

### Startup Probe Best Practices

**1. Use for slow-starting apps**:
```yaml
# Legacy Java app with long initialization
startupProbe:
  httpGet:
    path: /startup
    port: 8080
  periodSeconds: 10
  failureThreshold: 60  # 10 minutes max
```

**2. Calculate appropriate failure threshold**:
```
failureThreshold = maxStartupTime / periodSeconds

Example: App needs 5 minutes max
failureThreshold = 300s / 10s = 30
```

**3. Use same endpoint as liveness**:
```yaml
startupProbe:
  httpGet:
    path: /healthz  # Same as liveness
    port: 8080
  failureThreshold: 30
livenessProbe:
  httpGet:
    path: /healthz  # Same endpoint
    port: 8080
  failureThreshold: 3
```

## Probe Types

### 1. HTTP GET Probe

```yaml
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
    httpHeaders:
    - name: Authorization
      value: Bearer token
    scheme: HTTPS  # Default: HTTP
  periodSeconds: 10
```

**Success**: HTTP status 200-399

**Use when**: Application exposes HTTP endpoint

### 2. TCP Socket Probe

```yaml
livenessProbe:
  tcpSocket:
    port: 3306
  periodSeconds: 10
```

**Success**: TCP connection established

**Use when**: Application doesn't have HTTP endpoint (databases, caches)

### 3. Exec Command Probe

```yaml
livenessProbe:
  exec:
    command:
    - cat
    - /tmp/healthy
  periodSeconds: 10
```

**Success**: Command exit code 0

**Use when**: Need custom check logic

### 4. gRPC Probe (Kubernetes v1.24+)

```yaml
livenessProbe:
  grpc:
    port: 9090
    service: my.service.Health  # Optional
  periodSeconds: 10
```

**Success**: gRPC health check response `SERVING`

**Use when**: Application uses gRPC

## Configuration Parameters

| Parameter | Description | Default | Recommended |
|-----------|-------------|---------|-------------|
| `initialDelaySeconds` | Wait before first probe | 0 | Match app startup time |
| `periodSeconds` | How often to probe | 10 | 5-10 for readiness, 10-20 for liveness |
| `timeoutSeconds` | Probe timeout | 1 | 1-5 depending on endpoint |
| `successThreshold` | Consecutive successes required | 1 | Usually 1 |
| `failureThreshold` | Consecutive failures before action | 3 | 2-3 for readiness, 3-5 for liveness |

### Calculate Total Delay

```
Total time before action = initialDelaySeconds + (periodSeconds × failureThreshold)

Example:
initialDelaySeconds: 15
periodSeconds: 10
failureThreshold: 3
Total: 15 + (10 × 3) = 45 seconds before restart
```

## Complete Example with All Probes

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: complete-probes-example
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
      - name: web
        image: web-app:1.0
        ports:
        - containerPort: 8080

        # Startup: Handles slow initialization
        startupProbe:
          httpGet:
            path: /healthz
            port: 8080
          initialDelaySeconds: 0
          periodSeconds: 10
          failureThreshold: 30  # 5 minute max startup

        # Liveness: Restart if app deadlocks
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
          initialDelaySeconds: 0  # Startup probe handles delay
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3  # 30 seconds before restart

        # Readiness: Control traffic routing
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 0
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 2  # 10 seconds before removing from LB

        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            memory: 256Mi
```

## Common Patterns

### Pattern 1: Fast-Starting Web App

```yaml
# No startup probe needed
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
  initialDelaySeconds: 10
  periodSeconds: 10
  failureThreshold: 3

readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5
  failureThreshold: 2
```

### Pattern 2: Database

```yaml
# TCP socket probe
livenessProbe:
  tcpSocket:
    port: 5432
  initialDelaySeconds: 30
  periodSeconds: 10

readinessProbe:
  exec:
    command:
    - pg_isready
    - -U
    - postgres
  initialDelaySeconds: 10
  periodSeconds: 5
```

### Pattern 3: Legacy Application (Slow Start)

```yaml
startupProbe:
  httpGet:
    path: /healthz
    port: 8080
  periodSeconds: 10
  failureThreshold: 60  # 10 minute max

livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
  periodSeconds: 20
  failureThreshold: 3
```

### Pattern 4: gRPC Application

```yaml
livenessProbe:
  grpc:
    port: 9090
  initialDelaySeconds: 10
  periodSeconds: 10

readinessProbe:
  grpc:
    port: 9090
    service: myapp.v1.HealthService
  periodSeconds: 5
```

## Troubleshooting Probes

### Check Probe Failures

```bash
# View probe failures in events
kubectl describe pod <name> -n <namespace>

# Look for:
# - "Liveness probe failed"
# - "Readiness probe failed"
# - "Startup probe failed"

# Check pod conditions
kubectl get pod <name> -n <namespace> -o jsonpath='{.status.conditions[?(@.type=="Ready")]}'
```

### Common Issues

**Issue 1: Continuous restarts (CrashLoopBackOff)**
```
Cause: Liveness probe failing too quickly
Fix: Increase initialDelaySeconds or failureThreshold
```

**Issue 2: Pods never become ready**
```
Cause: Readiness probe never succeeds
Fix: Check endpoint returns 200, verify dependencies available
```

**Issue 3: Traffic sent to unprepared pods**
```
Cause: Missing or misconfigured readiness probe
Fix: Add readiness probe checking actual readiness
```

### Test Probes Locally

```bash
# Simulate HTTP probe
curl -v http://localhost:8080/healthz

# Simulate TCP probe
nc -zv localhost 3306

# Simulate exec probe
docker exec <container> cat /tmp/healthy
```

## Decision Tree

```
Does app take >30s to start?
├─ YES → Use startupProbe (delays other probes)
└─ NO  → Use initialDelaySeconds on liveness/readiness

Can app enter broken state needing restart?
├─ YES → Use livenessProbe
└─ NO  → Skip liveness (process crash is enough)

Does app need warm-up before traffic?
├─ YES → Use readinessProbe
└─ NO  → Skip readiness (pod ready immediately)
```

## Official Documentation

- Configure Probes: https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/
- Pod Lifecycle: https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/
