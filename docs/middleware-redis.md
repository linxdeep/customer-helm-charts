# Redis

Redis is used for caching, sessions and rate limiting. It only needs to be
reachable at `redis.addr` (`host:port`). Cluster mode is supported via
`redis.cluster: true`.

## Requirements

- Redis 7.x / 8.x (single instance or master-replica with a single endpoint)
- No authentication by default; if your Redis requires a password, verify the
  deployment supports passing it (coordinate with your Redis administrator)

## Option A: Redis Operator (ot-container-kit)

The open-source [Redis Operator](https://github.com/OT-Kubernetes/redis-operator)
from OT-Kubernetes manages standalone, replication and cluster topologies.

Install the operator:

```bash
helm repo add ot-ecosystem https://ot-container-kit.github.io/redis-operator/
helm repo update
helm install redis-operator ot-ecosystem/redis-operator \
  -n redis-operator --create-namespace
```

Create a standalone Redis (minimal example):

```yaml
apiVersion: redis.redis.opstreelabs.in/v1beta2
kind: Redis
metadata:
  name: redis
spec:
  kubernetesConfig:
    image: quay.io/opstree/redis:v8.0.15   # check the operator support matrix for the exact 8.x tag
    imagePullPolicy: IfNotPresent
  redisExporter:
    enabled: true
    image: quay.io/opstree/redis-exporter:v1.44.0
  storage:
    volumeClaimTemplate:
      spec:
        storageClassName: <your-storage-class>
        accessModes: [ReadWriteOnce]
        resources:
          requests:
            storage: 10Gi
```

The operator creates a service named after the CR (`redis`).

Chart values (same namespace):

```yaml
redis:
  addr: redis:6379
  cluster: false
```

For high availability use the `RedisReplication` CR (service
`redis-replication`, point `redis.addr` at the master endpoint) or
`RedisCluster` with `redis.cluster: true`.

## Option B: Bitnami Helm chart

If you prefer plain Helm charts over an operator:

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install redis bitnami/redis \
  -n <platform-namespace> \
  --set auth.enabled=false \
  --set architecture=standalone \
  --set image.tag=8.2.1 \
  --set master.persistence.size=10Gi
```

This creates `redis-master:6379`:

```yaml
redis:
  addr: redis-master:6379
  cluster: false
```

## Verification

```bash
kubectl run redis-check --rm -it --image=redis:7 --restart=Never -- \
  redis-cli -h redis ping
# PONG
```
