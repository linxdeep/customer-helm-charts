# Redis

Redis is used for caching, sessions and rate limiting. It only needs to be
reachable at `redis.addr` (`host:port`). Cluster mode is supported via
`redis.cluster: true`.

The example below is the tested setup from
[examples/eks-deploy-guide.md](../examples/eks-deploy-guide.md) §10; the
matching connection values are in [examples/values-full.yaml](../examples/values-full.yaml).

## Requirements

- Redis 7.x / 8.x (tested with 8.10.1 in cluster mode)
- No authentication by default; if your Redis requires a password, verify the
  deployment supports passing it (coordinate with your Redis administrator)

## Option A: Redis Operator (ot-container-kit)

The open-source [Redis Operator](https://github.com/OT-Kubernetes/redis-operator)
from OT-Kubernetes manages standalone, replication and cluster topologies.

Install the operator:

```bash
helm repo add ot-helm https://ot-container-kit.github.io/helm-charts/
helm repo update
helm install redis-operator ot-helm/redis-operator \
  --namespace redis-operator --create-namespace
```

Create a 3-shard cluster (tested example — namespace `redis`, CR
`redis-cluster`):

```yaml
apiVersion: redis.redis.opstreelabs.in/v1beta2
kind: RedisCluster
metadata:
  name: redis-cluster
  namespace: redis
spec:
  clusterSize: 3
  clusterVersion: v8
  persistenceEnabled: true
  podSecurityContext:
    fsGroup: 1000
    runAsUser: 1000
    runAsGroup: 1000
  kubernetesConfig:
    image: quay.io/opstree/redis:v8.10.1
    imagePullPolicy: IfNotPresent
    resources:
      requests:
        cpu: "100m"
        memory: "128Mi"
      limits:
        cpu: "500m"
        memory: "1024Mi"
  storage:
    keepAfterDelete: false
    nodeConfVolume: true
    volumeClaimTemplate:
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: gp3    # your storage class
        resources:
          requests:
            storage: 10Gi
    nodeConfVolumeClaimTemplate:
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: gp3    # your storage class
        resources:
          requests:
            storage: 1Gi
  redisLeader:
    replicas: 3
  redisFollower:
    replicas: 3
```

The operator creates leader/follower headless services. Point `redis.addr` at
both endpoints and enable cluster mode (cross-namespace, as tested):

```yaml
redis:
  cluster: true
  addr: redis-cluster-leader-headless.redis.svc.cluster.local:6379,redis-cluster-follower-headless.redis.svc.cluster.local:6379
```

For a single endpoint use the standalone `Redis` CR (service named after the
CR) or `RedisReplication` for master-replica, with `redis.cluster: false`.

## Option B: Bitnami Helm chart

If you prefer plain Helm charts over an operator:

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install redis bitnami/redis \
  -n <platform-namespace> \
  --set auth.enabled=false \
  --set architecture=standalone \
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
kubectl run redis-check --rm -it --image=redis:8 --restart=Never -- \
  redis-cli -h redis-cluster-leader-headless.redis.svc.cluster.local ping
# PONG
```
