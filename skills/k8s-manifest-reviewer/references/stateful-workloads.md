# StatefulSet Patterns and Best Practices

Complete guide to StatefulSets for stateful workloads based on official Kubernetes documentation.

## When to Use StatefulSets

Use StatefulSets when you need:

1. **Stable, unique network identifiers** - Each pod has persistent hostname
2. **Stable, persistent storage** - Volumes persist across pod rescheduling
3. **Ordered deployment and scaling** - Pods created/deleted sequentially (0, 1, 2...)
4. **Ordered, automated rolling updates** - Updates respect pod ordering

## When NOT to Use StatefulSets

Use Deployment instead if:
- Application is stateless
- Pods are interchangeable
- Order doesn't matter
- Persistent storage not needed per-pod

## Required Components

### 1. Headless Service (REQUIRED)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
spec:
  clusterIP: None  # CRITICAL: Makes it headless
  selector:
    app: nginx
  ports:
  - port: 80
    name: web
```

**Purpose**: Provides stable network identity for pods

### 2. StatefulSet

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: web
spec:
  serviceName: "nginx-service"  # MUST reference headless service
  replicas: 3
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:1.19
        ports:
        - containerPort: 80
          name: web
        volumeMounts:
        - name: data
          mountPath: /usr/share/nginx/html
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: [ "ReadWriteOncePod" ]  # Recommended
      storageClassName: "fast-ssd"
      resources:
        requests:
          storage: 10Gi
```

## Pod Identity

### Ordinal Index

Pods numbered sequentially: `<statefulset-name>-<ordinal>`

```
web-0
web-1
web-2
```

**Creation order**: 0, then 1, then 2
**Deletion order**: 2, then 1, then 0

### Customize Start Ordinal

```yaml
spec:
  ordinals:
    start: 5  # Pods will be: web-5, web-6, web-7
```

**Use when**: Migrating from existing system with specific numbering

### Stable Network Identity

**Pattern**: `<pod-name>.<service-name>.<namespace>.svc.cluster.local`

**Example**:
```
web-0.nginx-service.default.svc.cluster.local
web-1.nginx-service.default.svc.cluster.local
web-2.nginx-service.default.svc.cluster.local
```

**Access specific pod**:
```bash
# From within cluster
curl http://web-0.nginx-service:80

# Fully qualified
curl http://web-0.nginx-service.default.svc.cluster.local:80
```

## Storage Management

### VolumeClaimTemplates

Each pod gets its own PersistentVolumeClaim:

```yaml
volumeClaimTemplates:
- metadata:
    name: data
  spec:
    accessModes: [ "ReadWriteOncePod" ]  # Secure: one pod only
    storageClassName: "fast-ssd"
    resources:
      requests:
        storage: 10Gi
```

**Result**: Creates PVCs named `<claim-name>-<pod-name>`:
```
data-web-0
data-web-1
data-web-2
```

### Access Modes

| Mode | Description | Use Case |
|------|-------------|----------|
| `ReadWriteOncePod` | Single pod read-write (recommended) | Databases, stateful apps |
| `ReadWriteOnce` | Single node read-write (deprecated for StatefulSets) | Legacy |
| `ReadOnlyMany` | Multiple pods read-only | Shared config |

**Security**: Use `ReadWriteOncePod` to prevent multi-pod access bugs

### PVC Lifecycle

**IMPORTANT**: PVCs are NOT automatically deleted when StatefulSet is deleted

**Manual cleanup required**:
```bash
# Before deleting StatefulSet (optional: scale to 0)
kubectl scale statefulset web --replicas=0

# Delete StatefulSet (keeps PVCs)
kubectl delete statefulset web

# List orphaned PVCs
kubectl get pvc | grep web

# Delete PVCs manually
kubectl delete pvc data-web-0 data-web-1 data-web-2

# Or delete all PVCs for a label
kubectl delete pvc -l app=nginx
```

**Retain PVCs if**:
- Data recovery needed
- Recreating StatefulSet with same data
- Backup/migration in progress

## Pod Management Policies

### OrderedReady (Default)

```yaml
spec:
  podManagementPolicy: OrderedReady
```

**Behavior**:
- Pods created sequentially: 0 → 1 → 2
- Each pod must be Running and Ready before next starts
- Deletion reverse order: 2 → 1 → 0
- **Safer** but slower

**Use for**:
- Databases with leader election
- Applications requiring strict ordering
- Clustered stateful apps (Zookeeper, Consul)

### Parallel

```yaml
spec:
  podManagementPolicy: Parallel
```

**Behavior**:
- All pods created simultaneously
- No ordering guarantees
- **Faster** but less controlled

**Use for**:
- Independent stateful services
- Parallel data processing
- When ordering doesn't matter

## Update Strategies

### RollingUpdate (Default)

```yaml
spec:
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      partition: 0  # Update all pods
```

**Behavior**:
- Updates pods in reverse ordinal order: N-1 → N-2 → ... → 0
- Waits for each pod to be Running and Ready
- Preserves pod identity and storage

### Partition Updates (Staged Rollouts)

```yaml
spec:
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      partition: 2  # Only update pods >= ordinal 2
```

**Example with 4 replicas** (web-0, web-1, web-2, web-3):
```yaml
partition: 2
# Updates: web-2, web-3
# Unchanged: web-0, web-1
```

**Use for**:
- Canary deployments (test new version on subset)
- Staged rollouts
- A/B testing

**Process**:
```bash
# 1. Set partition to test 1 pod
kubectl patch statefulset web -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":3}}}}'

# 2. Update image
kubectl set image statefulset/web nginx=nginx:1.20

# 3. Only web-3 updates; verify it works

# 4. Lower partition to update more
kubectl patch statefulset web -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":2}}}}'

# 5. Now web-2 and web-3 updated; verify

# 6. Update all
kubectl patch statefulset web -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":0}}}}'
```

### OnDelete

```yaml
spec:
  updateStrategy:
    type: OnDelete
```

**Behavior**:
- Pods NOT automatically updated
- Only update when manually deleted
- Maximum control

**Use for**:
- Manual orchestration required
- Complex update procedures
- High-risk updates

## Graceful Scaling

### Scale Up (Safe)

```bash
kubectl scale statefulset web --replicas=5

# Adds: web-3, web-4 (in order if OrderedReady)
```

### Scale Down (Requires Care)

```bash
# ✅ GOOD: Scale to 0 before deletion
kubectl scale statefulset web --replicas=0

# Wait for all pods terminated
kubectl get pods -l app=nginx --watch

# Then delete StatefulSet
kubectl delete statefulset web

# ❌ BAD: Delete without scaling
kubectl delete statefulset web
# Pods may not terminate gracefully
```

### terminationGracePeriodSeconds

```yaml
spec:
  template:
    spec:
      terminationGracePeriodSeconds: 30  # Default
```

**For databases/stateful apps**:
```yaml
terminationGracePeriodSeconds: 120  # 2 minutes for graceful shutdown
```

**Purpose**: Time for app to:
- Flush data to disk
- Close connections
- Deregister from cluster
- Complete in-flight requests

## Production Patterns

### Pattern 1: MySQL/PostgreSQL Database

```yaml
apiVersion: v1
kind: Service
metadata:
  name: mysql
spec:
  clusterIP: None
  selector:
    app: mysql
  ports:
  - port: 3306
    name: mysql
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mysql
spec:
  serviceName: mysql
  replicas: 3
  selector:
    matchLabels:
      app: mysql
  template:
    metadata:
      labels:
        app: mysql
    spec:
      terminationGracePeriodSeconds: 60
      securityContext:
        runAsNonRoot: true
        runAsUser: 999
        fsGroup: 999
      containers:
      - name: mysql
        image: mysql:8.0
        ports:
        - containerPort: 3306
          name: mysql
        env:
        - name: MYSQL_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-secret
              key: password
        resources:
          requests:
            cpu: 500m
            memory: 1Gi
          limits:
            memory: 2Gi
        volumeMounts:
        - name: data
          mountPath: /var/lib/mysql
        livenessProbe:
          exec:
            command:
            - mysqladmin
            - ping
            - -h
            - localhost
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          exec:
            command:
            - mysql
            - -h
            - localhost
            - -e
            - "SELECT 1"
          initialDelaySeconds: 10
          periodSeconds: 5
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: [ "ReadWriteOncePod" ]
      storageClassName: fast-ssd
      resources:
        requests:
          storage: 100Gi
```

### Pattern 2: Distributed Cache (Redis)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: redis
spec:
  clusterIP: None
  selector:
    app: redis
  ports:
  - port: 6379
    name: redis
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: redis
spec:
  serviceName: redis
  replicas: 3
  podManagementPolicy: Parallel  # Faster startup
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:
      - name: redis
        image: redis:7.0
        command:
        - redis-server
        - --appendonly
        - "yes"
        - --requirepass
        - "$(REDIS_PASSWORD)"
        env:
        - name: REDIS_PASSWORD
          valueFrom:
            secretKeyRef:
              name: redis-secret
              key: password
        ports:
        - containerPort: 6379
          name: redis
        resources:
          requests:
            cpu: 100m
            memory: 256Mi
          limits:
            memory: 512Mi
        volumeMounts:
        - name: data
          mountPath: /data
        livenessProbe:
          tcpSocket:
            port: 6379
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          exec:
            command:
            - redis-cli
            - ping
          initialDelaySeconds: 10
          periodSeconds: 5
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: [ "ReadWriteOncePod" ]
      resources:
        requests:
          storage: 10Gi
```

### Pattern 3: Message Queue (RabbitMQ)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: rabbitmq
spec:
  clusterIP: None
  selector:
    app: rabbitmq
  ports:
  - port: 5672
    name: amqp
  - port: 15672
    name: management
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: rabbitmq
spec:
  serviceName: rabbitmq
  replicas: 3
  podManagementPolicy: OrderedReady  # Leader election needs order
  selector:
    matchLabels:
      app: rabbitmq
  template:
    metadata:
      labels:
        app: rabbitmq
    spec:
      containers:
      - name: rabbitmq
        image: rabbitmq:3.11-management
        env:
        - name: RABBITMQ_DEFAULT_USER
          value: admin
        - name: RABBITMQ_DEFAULT_PASS
          valueFrom:
            secretKeyRef:
              name: rabbitmq-secret
              key: password
        - name: RABBITMQ_ERLANG_COOKIE
          valueFrom:
            secretKeyRef:
              name: rabbitmq-secret
              key: erlang-cookie
        ports:
        - containerPort: 5672
          name: amqp
        - containerPort: 15672
          name: management
        resources:
          requests:
            cpu: 200m
            memory: 512Mi
          limits:
            memory: 1Gi
        volumeMounts:
        - name: data
          mountPath: /var/lib/rabbitmq
        livenessProbe:
          exec:
            command:
            - rabbitmq-diagnostics
            - ping
          initialDelaySeconds: 60
          periodSeconds: 30
        readinessProbe:
          exec:
            command:
            - rabbitmq-diagnostics
            - check_running
          initialDelaySeconds: 20
          periodSeconds: 10
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: [ "ReadWriteOncePod" ]
      resources:
        requests:
          storage: 20Gi
```

## Common Issues and Solutions

### Issue 1: Pods Not Starting in Order

**Symptom**: All pods pending or creating simultaneously

**Check**:
```bash
kubectl describe statefulset web

# Look for podManagementPolicy
```

**Fix**: Use OrderedReady
```yaml
spec:
  podManagementPolicy: OrderedReady  # Explicit
```

### Issue 2: PVCs Not Created

**Symptom**: Pods stuck in Pending, events show volume mount issues

**Check**:
```bash
kubectl get pvc | grep web

# Should see: data-web-0, data-web-1, etc.
```

**Common causes**:
- StorageClass doesn't exist
- No available PersistentVolumes
- Insufficient storage quota

**Fix**:
```bash
# Check StorageClass exists
kubectl get storageclass

# Check PV availability
kubectl get pv
```

### Issue 3: Pod Identity Lost After Rescheduling

**Symptom**: Pod gets new name after deletion/rescheduling

**Cause**: StatefulSet was deleted OR using Deployment instead

**Verify**:
```bash
# StatefulSet pods keep identity
kubectl get pods -l app=nginx
# Should see: web-0, web-1, web-2 (consistent names)

# Deployment pods get random suffixes
# Would see: web-abc123, web-def456 (changing names)
```

### Issue 4: Volume Already in Use

**Error**: `Volume is already attached to node X`

**Cause**: Using `ReadWriteOnce` with pod rescheduled to different node

**Fix**: Use `ReadWriteOncePod` or cloud-specific multi-attach
```yaml
volumeClaimTemplates:
- spec:
    accessModes: [ "ReadWriteOncePod" ]  # Prevents this issue
```

## StatefulSet Checklist

Production readiness review:

- [ ] Headless Service defined with clusterIP: None
- [ ] serviceName in StatefulSet matches Service name
- [ ] VolumeClaimTemplates use ReadWriteOncePod
- [ ] Appropriate storageClassName for workload
- [ ] terminationGracePeriodSeconds sufficient (60-120s for databases)
- [ ] Liveness and readiness probes configured
- [ ] Resource requests and limits defined
- [ ] Security context applied (runAsNonRoot)
- [ ] Pod management policy appropriate (OrderedReady for most)
- [ ] Update strategy configured (RollingUpdate with partition for staged rollouts)
- [ ] PodDisruptionBudget defined for production
- [ ] Documented PVC cleanup procedure

## Comparison: StatefulSet vs Deployment

| Aspect | StatefulSet | Deployment |
|--------|-------------|------------|
| **Pod names** | Deterministic (web-0, web-1) | Random suffix |
| **Network identity** | Stable DNS names | Load-balanced Service only |
| **Storage** | Persistent per-pod (VolumeClaimTemplates) | Shared or ephemeral |
| **Ordering** | Guaranteed (0→1→2) | Simultaneous |
| **Scaling** | Sequential | Parallel |
| **Updates** | Reverse order (2→1→0) | Rolling random |
| **Use case** | Databases, caches, queues | Web apps, APIs, workers |

## Official Documentation

- StatefulSets: https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/
- StatefulSet Basics Tutorial: https://kubernetes.io/docs/tutorials/stateful-application/basic-stateful-set/
- Run Replicated Stateful Application: https://kubernetes.io/docs/tasks/run-application/run-replicated-stateful-application/
