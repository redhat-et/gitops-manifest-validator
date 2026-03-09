# Deployment Patterns and Best Practices

Production deployment strategies based on official Kubernetes documentation.

## Deployment Fundamentals

Deployments manage Pods and ReplicaSets for stateless applications with:
- Declarative updates
- Automated rollouts and rollbacks
- Scaling capabilities
- Self-healing

## Update Strategies

### RollingUpdate (Default)

Gradually replaces old Pods with new ones (zero downtime).

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1           # Max pods above desired during update
      maxUnavailable: 1     # Max pods below desired during update
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
      - name: nginx
        image: nginx:1.19.0
```

**Parameters**:

- `maxSurge`: Maximum extra pods during update
  - Absolute number: `maxSurge: 2`
  - Percentage: `maxSurge: 25%` (rounded up)

- `maxUnavailable`: Maximum pods unavailable during update
  - Absolute number: `maxUnavailable: 1`
  - Percentage: `maxUnavailable: 25%` (rounded down)

**Examples**:

```yaml
# Fast rollout (more resources)
strategy:
  rollingUpdate:
    maxSurge: 2           # Create 2 new pods immediately
    maxUnavailable: 0     # Never reduce available pods

# Conservative rollout (fewer resources)
strategy:
  rollingUpdate:
    maxSurge: 0           # No extra pods
    maxUnavailable: 1     # One at a time

# Balanced rollout (recommended)
strategy:
  rollingUpdate:
    maxSurge: 1
    maxUnavailable: 1
```

### Recreate Strategy

Terminates all existing Pods before creating new ones (causes downtime).

```yaml
spec:
  strategy:
    type: Recreate
```

**Use when**:
- Application cannot run multiple versions simultaneously
- Shared resources (database migrations) require exclusive access
- Downtime is acceptable

**Avoid when**:
- Production services requiring availability
- Rolling updates are feasible

## Rollout Management

### Triggering Rollouts

Rollouts triggered by `.spec.template` changes only:

```bash
# Update image (triggers rollout)
kubectl set image deployment/web-app nginx=nginx:1.20.0

# Edit deployment (triggers rollout if template changes)
kubectl edit deployment/web-app

# Apply updated YAML (triggers rollout if template changes)
kubectl apply -f deployment.yaml
```

**Note**: Scaling does NOT trigger rollouts

```bash
# This does NOT trigger rollout
kubectl scale deployment/web-app --replicas=5
```

### Monitor Rollout Status

```bash
# Watch rollout progress
kubectl rollout status deployment/web-app

# Output:
# Waiting for deployment "web-app" rollout to finish: 1 of 3 updated replicas are available...
# deployment "web-app" successfully rolled out
```

### Rollout History

```bash
# View rollout history
kubectl rollout history deployment/web-app

# View specific revision
kubectl rollout history deployment/web-app --revision=2

# Set revision limit
spec:
  revisionHistoryLimit: 10  # Default: 10
```

### Rollback

```bash
# Rollback to previous revision
kubectl rollout undo deployment/web-app

# Rollback to specific revision
kubectl rollout undo deployment/web-app --to-revision=2

# Verify rollback
kubectl rollout status deployment/web-app
```

### Pause/Resume Rollouts

```bash
# Pause rollout (apply multiple changes)
kubectl rollout pause deployment/web-app

# Make changes
kubectl set image deployment/web-app nginx=nginx:1.20.0
kubectl set resources deployment/web-app -c nginx --limits=cpu=200m,memory=512Mi

# Resume rollout (single rollout for all changes)
kubectl rollout resume deployment/web-app
```

## High Availability Patterns

### Pattern 1: Multiple Replicas

```yaml
spec:
  replicas: 3  # Minimum for HA
```

**Benefits**:
- Survive single pod failure
- Load distribution
- Rolling updates without downtime

**Calculation**:
- QA/Staging: 2 replicas
- Production: 3+ replicas
- High-traffic: 5+ replicas

### Pattern 2: PodDisruptionBudget

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: web-app-pdb
spec:
  minAvailable: 2  # or maxUnavailable: 1
  selector:
    matchLabels:
      app: web
```

**Use for**:
- Protection during cluster maintenance
- Node drains
- Voluntary disruptions

**Options**:
- `minAvailable: 2` - Keep at least 2 pods running
- `maxUnavailable: 1` - Disrupt max 1 pod at a time

### Pattern 3: Anti-Affinity Rules

```yaml
spec:
  template:
    spec:
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app
                  operator: In
                  values:
                  - web
              topologyKey: kubernetes.io/hostname
```

**Result**: Pods scheduled on different nodes when possible

**Levels**:
- `preferred...`: Soft anti-affinity (best effort)
- `required...`: Hard anti-affinity (mandatory)

## Resource Management

### Resource Requests and Limits

```yaml
spec:
  template:
    spec:
      containers:
      - name: app
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 256Mi
```

See `resource-optimization.md` for detailed guidance.

### Node Selection

```yaml
spec:
  template:
    spec:
      nodeSelector:
        disktype: ssd
        environment: production
```

**Use when**: Specific node requirements (GPU, SSD, etc.)

## Health Probes

```yaml
spec:
  template:
    spec:
      containers:
      - name: app
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
          initialDelaySeconds: 15
          periodSeconds: 20
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 10
```

See `health-probes.md` for detailed patterns.

## Production Deployment Template

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: production-app
  labels:
    app: production-app
    version: v1
spec:
  replicas: 3
  revisionHistoryLimit: 10
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0  # Zero downtime
  selector:
    matchLabels:
      app: production-app
  template:
    metadata:
      labels:
        app: production-app
        version: v1
    spec:
      # Security
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 2000
        seccompProfile:
          type: RuntimeDefault

      # Service account
      serviceAccountName: production-app-sa

      # Anti-affinity for HA
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app
                  operator: In
                  values:
                  - production-app
              topologyKey: kubernetes.io/hostname

      containers:
      - name: app
        image: production-app:1.0.0  # Specific version
        imagePullPolicy: IfNotPresent

        # Ports
        ports:
        - name: http
          containerPort: 8080
          protocol: TCP

        # Environment variables from ConfigMap/Secret
        envFrom:
        - configMapRef:
            name: app-config
        - secretRef:
            name: app-secrets

        # Resources
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            memory: 256Mi

        # Security context
        securityContext:
          allowPrivilegeEscalation: false
          runAsNonRoot: true
          capabilities:
            drop:
            - ALL
          readOnlyRootFilesystem: true

        # Health probes
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
          initialDelaySeconds: 15
          periodSeconds: 20
          timeoutSeconds: 5
          failureThreshold: 3

        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 10
          timeoutSeconds: 3
          failureThreshold: 2

        # Volumes
        volumeMounts:
        - name: cache
          mountPath: /cache
        - name: tmp
          mountPath: /tmp

      volumes:
      - name: cache
        emptyDir: {}
      - name: tmp
        emptyDir: {}
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: production-app-pdb
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: production-app
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: production-app-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: production-app
  minReplicas: 3
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

## Selector Best Practices

### Selector Immutability

**Warning**: Deployment selector is immutable after creation

```yaml
# ❌ CANNOT CHANGE after creation
spec:
  selector:
    matchLabels:
      app: web
```

**Must delete and recreate if selector needs to change**

### Unique Selectors

```yaml
# ❌ BAD: Overlapping selectors
# Deployment 1
selector:
  matchLabels:
    app: web

# Deployment 2 (CONFLICT!)
selector:
  matchLabels:
    app: web

# ✅ GOOD: Unique selectors
# Deployment 1
selector:
  matchLabels:
    app: web
    version: v1

# Deployment 2
selector:
  matchLabels:
    app: web
    version: v2
```

### Label Matching

```yaml
# Selector must match pod template labels
spec:
  selector:
    matchLabels:
      app: web
      tier: frontend
  template:
    metadata:
      labels:
        app: web        # Must include
        tier: frontend  # Must include
        version: v1     # Can have additional labels
```

## Common Deployment Patterns

### Blue-Green Deployment

```yaml
# Blue (current production)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-blue
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
      version: blue
  template:
    metadata:
      labels:
        app: myapp
        version: blue
    spec:
      containers:
      - name: app
        image: myapp:1.0.0
---
# Green (new version)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-green
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
      version: green
  template:
    metadata:
      labels:
        app: myapp
        version: green
    spec:
      containers:
      - name: app
        image: myapp:2.0.0
---
# Service (switch between blue/green)
apiVersion: v1
kind: Service
metadata:
  name: myapp
spec:
  selector:
    app: myapp
    version: blue  # Change to "green" to switch traffic
  ports:
  - port: 80
    targetPort: 8080
```

### Canary Deployment

```yaml
# Stable version (90% traffic)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-stable
spec:
  replicas: 9
  selector:
    matchLabels:
      app: myapp
      track: stable
  template:
    metadata:
      labels:
        app: myapp
        track: stable
    spec:
      containers:
      - name: app
        image: myapp:1.0.0
---
# Canary version (10% traffic)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-canary
spec:
  replicas: 1
  selector:
    matchLabels:
      app: myapp
      track: canary
  template:
    metadata:
      labels:
        app: myapp
        track: canary
    spec:
      containers:
      - name: app
        image: myapp:2.0.0
---
# Service (routes to both)
apiVersion: v1
kind: Service
metadata:
  name: myapp
spec:
  selector:
    app: myapp  # Matches both stable and canary
  ports:
  - port: 80
    targetPort: 8080
```

## Troubleshooting

### Check Deployment Status

```bash
# Overall status
kubectl get deployments

# Detailed description
kubectl describe deployment <name>

# Rollout status
kubectl rollout status deployment/<name>

# Recent events
kubectl get events --sort-by='.lastTimestamp' | grep <name>
```

### Common Issues

**Issue 1: Pods not updating**
```bash
# Check if template changed
kubectl rollout history deployment/<name>

# Force rollout by adding annotation
kubectl patch deployment <name> -p '{"spec":{"template":{"metadata":{"annotations":{"date":"'$(date +%s)'"}}}}}'
```

**Issue 2: ImagePullBackOff**
```bash
# Check image name and tag
kubectl describe pod <pod-name>

# Verify image exists
docker pull <image>

# Check image pull secrets
kubectl get secrets
```

**Issue 3: CrashLoopBackOff**
```bash
# Check logs
kubectl logs <pod-name>
kubectl logs <pod-name> --previous

# Check resource limits
kubectl describe pod <pod-name>

# Check liveness probe
kubectl describe pod <pod-name> | grep -A 10 Liveness
```

## Deployment Checklist

Production deployment review:

- [ ] Replicas ≥ 3 for high availability
- [ ] RollingUpdate strategy configured
- [ ] maxUnavailable = 0 for zero downtime
- [ ] Resource requests and limits defined
- [ ] Liveness and readiness probes configured
- [ ] Security context applied (runAsNonRoot, etc.)
- [ ] Specific image tags (not `latest`)
- [ ] PodDisruptionBudget defined
- [ ] Anti-affinity rules for pod distribution
- [ ] HPA configured if variable load
- [ ] Service account explicitly defined
- [ ] Labels follow convention (app, version, component)
- [ ] ConfigMaps/Secrets for configuration
- [ ] RevisionHistoryLimit set appropriately

## Official Documentation

- Deployments: https://kubernetes.io/docs/concepts/workloads/controllers/deployment/
- Rolling Updates: https://kubernetes.io/docs/tutorials/kubernetes-basics/update/update-intro/
- Scaling: https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#scaling-a-deployment
