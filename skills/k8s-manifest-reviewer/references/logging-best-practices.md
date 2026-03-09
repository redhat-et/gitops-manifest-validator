# Logging Best Practices for Kubernetes

Production logging patterns based on official Kubernetes documentation.

## Kubernetes Logging Architecture

### Core Principle

**Logs should have separate storage and lifecycle independent of nodes, pods, or containers.**

Kubernetes does NOT provide native log storage - you must implement cluster-level logging.

## Container Logging Patterns

### Pattern 1: Standard Streams (Recommended)

Applications write to stdout and stderr:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app
spec:
  containers:
  - name: app
    image: myapp:1.0
    # Application writes to stdout/stderr
    # Kubernetes handles capture automatically
```

**Benefits**:
- Simple - no configuration needed
- Standard Kubernetes tooling works (`kubectl logs`)
- Container runtime handles rotation
- Works with log aggregation

**Application implementation**:
```python
# Python example
import logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s %(levelname)s %(message)s',
    stream=sys.stdout  # Write to stdout
)
logging.info("Application started")
```

### Pattern 2: Structured Logging (Recommended)

Use JSON format for better parsing:

```json
{
  "timestamp": "2024-01-15T10:30:45Z",
  "level": "INFO",
  "service": "api-server",
  "trace_id": "abc123",
  "message": "Request processed",
  "duration_ms": 145,
  "status_code": 200,
  "path": "/api/users"
}
```

**Benefits**:
- Easy parsing by log aggregators
- Queryable fields (filter by trace_id, status_code, etc.)
- Better analytics

**Application implementation**:
```python
import json
import sys

def log_structured(level, message, **kwargs):
    log_entry = {
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "level": level,
        "service": "api-server",
        "message": message,
        **kwargs
    }
    print(json.dumps(log_entry), file=sys.stdout)

log_structured("INFO", "Request processed",
               trace_id="abc123",
               duration_ms=145,
               status_code=200)
```

## Log Rotation

### Container Runtime Rotation

Kubelet manages container log rotation automatically:

**Configuration parameters** (in kubelet config):
```yaml
containerLogMaxSize: 10Mi      # Max size per log file
containerLogMaxFiles: 5        # Number of log files to retain
containerLogMaxWorkers: 2      # Concurrent rotation jobs
containerLogMonitorInterval: 10s  # Check interval
```

**Log file location**:
- Linux: `/var/log/pods/<namespace>_<pod-name>_<pod-uid>/<container>/`
- Windows: `C:\var\log\pods\<namespace>_<pod-name>_<pod-uid>\<container>\`

**Important limitation**:
```
kubectl logs only shows the LATEST log file.

If a pod writes 40 MiB and rotation happens at 10 MiB,
kubectl logs returns at most 10 MiB of data.
```

### Tune Rotation for High-Volume Workloads

```yaml
# Kubelet configuration
containerLogMaxSize: 100Mi    # Increase for high-volume apps
containerLogMaxFiles: 10      # More files = more retention
containerLogMaxWorkers: 4     # Parallel rotations for many pods
```

**Calculate retention**:
```
Total retention = containerLogMaxSize × containerLogMaxFiles

Example: 100Mi × 10 = 1000Mi (1 GiB) per container
```

## Accessing Logs

### kubectl logs

```bash
# Current logs
kubectl logs <pod-name>

# Specific container in multi-container pod
kubectl logs <pod-name> -c <container-name>

# Last N lines
kubectl logs <pod-name> --tail=100

# Follow logs (stream)
kubectl logs <pod-name> --follow

# Previous container instance (after crash/restart)
kubectl logs <pod-name> --previous

# All containers in pod
kubectl logs <pod-name> --all-containers=true

# Logs with timestamps
kubectl logs <pod-name> --timestamps

# Logs since time
kubectl logs <pod-name> --since=1h
kubectl logs <pod-name> --since-time=2024-01-15T10:00:00Z

# Logs for label selector
kubectl logs -l app=web --all-containers=true
```

### Limitations

**kubectl logs**:
- Only shows most recent log file (rotation limitation)
- Logs lost when pod deleted
- No historical search capabilities
- Limited to one pod at a time

**Solution**: Implement cluster-level logging

## Cluster-Level Logging Architectures

### Architecture 1: Node-Level Logging Agent (Recommended)

DaemonSet on each node collects logs:

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: fluentd
  namespace: kube-system
spec:
  selector:
    matchLabels:
      name: fluentd
  template:
    metadata:
      labels:
        name: fluentd
    spec:
      serviceAccountName: fluentd
      containers:
      - name: fluentd
        image: fluent/fluentd-kubernetes-daemonset:v1
        env:
        - name: FLUENT_ELASTICSEARCH_HOST
          value: "elasticsearch.logging.svc.cluster.local"
        - name: FLUENT_ELASTICSEARCH_PORT
          value: "9200"
        resources:
          requests:
            cpu: 100m
            memory: 200Mi
          limits:
            memory: 400Mi
        volumeMounts:
        - name: varlog
          mountPath: /var/log
        - name: containers
          mountPath: /var/lib/docker/containers
          readOnly: true
      volumes:
      - name: varlog
        hostPath:
          path: /var/log
      - name: containers
        hostPath:
          path: /var/lib/docker/containers
```

**Pros**:
- Low resource overhead (one agent per node)
- Transparent to applications
- Works with all pods

**Cons**:
- Requires node access
- Tied to node filesystem layout

**Common agents**:
- Fluentd / Fluent Bit
- Logstash
- Filebeat
- Vector

### Architecture 2: Sidecar Container

Log shipper as sidecar in each pod:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app-with-sidecar
spec:
  containers:
  - name: app
    image: myapp:1.0
    volumeMounts:
    - name: logs
      mountPath: /var/log/app
  - name: log-shipper
    image: fluent/fluent-bit:latest
    volumeMounts:
    - name: logs
      mountPath: /var/log/app
      readOnly: true
    - name: config
      mountPath: /fluent-bit/etc/
  volumes:
  - name: logs
    emptyDir: {}
  - name: config
    configMap:
      name: fluent-bit-config
```

**Pros**:
- Application-specific log processing
- Custom parsing per application
- Isolated from other pods

**Cons**:
- Higher resource overhead (per pod)
- More complex configuration

**Use when**:
- Application writes to files (not stdout)
- Need custom log parsing per app
- Strict isolation requirements

### Architecture 3: Direct Application Shipping

Application sends logs directly to backend:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app
spec:
  containers:
  - name: app
    image: myapp:1.0
    env:
    - name: LOG_ENDPOINT
      value: "https://logs.example.com"
    - name: LOG_API_KEY
      valueFrom:
        secretKeyRef:
          name: logging-secret
          key: api-key
```

**Pros**:
- No intermediate agents
- Application controls log format

**Cons**:
- Application complexity
- Coupling to log backend
- Network overhead per pod

**Use when**:
- Using SaaS logging (Datadog, New Relic, etc.)
- Small number of pods
- Application already has logging library

## System Component Logging

### Linux Nodes

System components (kubelet, container runtime) log to:

```bash
# View kubelet logs
journalctl -u kubelet

# View kubelet logs since time
journalctl -u kubelet --since "2024-01-15 10:00:00"

# Follow kubelet logs
journalctl -u kubelet -f

# View container runtime logs
journalctl -u containerd  # or docker
```

**Log location**: `/var/log/` (fallback if systemd not available)

### Windows Nodes

System component logs:
- Default: `C:\var\logs`
- Some deployments: `C:\var\log\kubelet`

## Best Practices

### 1. Always Use Stdout/Stderr

```yaml
# ✅ GOOD: Write to stdout
containers:
- name: app
  image: myapp:1.0
  # Application logs to stdout

# ❌ BAD: Write to files
containers:
- name: app
  image: myapp:1.0
  # Application writes to /var/log/app.log
  # Requires sidecar or volume mounts
```

### 2. Use Structured Logging

```json
// ✅ GOOD: Structured JSON
{"timestamp":"2024-01-15T10:30:45Z","level":"INFO","message":"User logged in","user_id":"123"}

// ❌ BAD: Unstructured text
2024-01-15 10:30:45 User 123 logged in
```

### 3. Include Context

**Essential fields**:
- Timestamp (ISO 8601 with timezone)
- Log level (DEBUG, INFO, WARN, ERROR, FATAL)
- Service/application name
- Correlation ID / Trace ID
- Message

**Optional but useful**:
- Pod name / hostname
- Namespace
- Version
- Source file/line (for errors)

```json
{
  "timestamp": "2024-01-15T10:30:45Z",
  "level": "ERROR",
  "service": "api-server",
  "version": "1.2.3",
  "pod": "api-server-abc123",
  "namespace": "production",
  "trace_id": "xyz789",
  "message": "Database connection failed",
  "error": "connection timeout",
  "duration_ms": 5000
}
```

### 4. Set Appropriate Log Levels

```
FATAL - Application cannot continue (exits)
ERROR - Operation failed but app continues
WARN  - Unexpected but handled
INFO  - Normal operations (default in production)
DEBUG - Detailed info (development only)
TRACE - Very detailed (development only)
```

**Production configuration**:
```yaml
env:
- name: LOG_LEVEL
  value: "INFO"  # Default production level
```

### 5. Avoid Logging Sensitive Data

```python
# ❌ BAD: Logs sensitive data
logging.info(f"User password: {password}")
logging.info(f"Credit card: {cc_number}")
logging.info(f"API key: {api_key}")

# ✅ GOOD: Redacts or omits sensitive data
logging.info(f"User authenticated: {user_id}")
logging.info("Payment processed successfully")
logging.info("API call authorized")
```

### 6. Implement Log Sampling for High Volume

```python
# Sample 1% of requests in production
import random

def should_log():
    return random.random() < 0.01

if should_log():
    logging.debug("Detailed request info...")
```

### 7. Configure Retention Appropriately

```yaml
# Kubelet configuration
containerLogMaxSize: 10Mi   # Small for low-volume apps
containerLogMaxFiles: 5     # Short retention if logs shipped

# For high-volume apps without log shipping
containerLogMaxSize: 100Mi  # Larger files
containerLogMaxFiles: 10    # More retention
```

## Multi-Line Logs

### Problem

Stack traces split across multiple log lines:

```
2024-01-15 10:30:45 ERROR Exception occurred
Traceback (most recent call last):
  File "app.py", line 42, in process
    result = divide(a, b)
ZeroDivisionError: division by zero
```

### Solution 1: Structured Logging

```json
{
  "timestamp": "2024-01-15T10:30:45Z",
  "level": "ERROR",
  "message": "Exception occurred",
  "stacktrace": "Traceback (most recent call last):\n  File \"app.py\", line 42, in process\n    result = divide(a, b)\nZeroDivisionError: division by zero"
}
```

### Solution 2: Log Agent Configuration

Configure Fluentd/Fluent Bit to merge multi-line logs:

```yaml
# fluent-bit.conf
[FILTER]
    Name multiline
    Match *
    multiline.key_content log
    multiline.parser python
```

## Monitoring Log Volume

### Detect High Log Volume

```bash
# Check log file sizes
kubectl exec <pod> -- du -sh /var/log/pods/

# Monitor logs written per second
kubectl top pods --containers | grep -E 'CPU|MEM'

# Check for log-heavy pods
kubectl get pods -A -o json | jq '.items[] | select(.status.containerStatuses[].restartCount > 5) | .metadata.name'
```

### Alerts

Set alerts for:
- Log volume > threshold
- Frequent pod restarts (often indicates crash logs)
- Logs filling disk space

## Common Issues

### Issue 1: Logs Not Appearing

**Check**:
```bash
# Verify pod is running
kubectl get pod <name>

# Check if container is logging
kubectl logs <pod> --tail=1

# Check container is writing to stdout
kubectl exec <pod> -- ps aux
```

### Issue 2: Logs Truncated

**Cause**: Log rotation occurred, only latest file shown

**Fix**: Implement cluster-level logging for full retention

### Issue 3: Disk Space Full

**Check**:
```bash
# Node disk usage
kubectl top nodes

# Pod log directory size
kubectl get nodes -o json | jq '.items[] | {name: .metadata.name, capacity: .status.capacity.ephemeral-storage}'
```

**Fix**:
- Reduce log volume (sample, change level to INFO)
- Adjust rotation settings (smaller maxSize)
- Implement log shipping

## Cluster-Level Logging Checklist

Production readiness:

- [ ] Applications log to stdout/stderr
- [ ] Structured logging (JSON) implemented
- [ ] Log levels configurable via environment variables
- [ ] Sensitive data NOT logged
- [ ] Trace IDs included for distributed tracing
- [ ] Log aggregation solution deployed (Fluentd, Logstash, etc.)
- [ ] Log retention policy defined
- [ ] Log storage separate from cluster
- [ ] Alerts configured for log volume anomalies
- [ ] Log rotation tuned for workload volume
- [ ] System component logs monitored (kubelet, etc.)

## Official Documentation

- Logging Architecture: https://kubernetes.io/docs/concepts/cluster-administration/logging/
- System Logs: https://kubernetes.io/docs/concepts/cluster-administration/system-logs/
- kubectl logs: https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#logs
