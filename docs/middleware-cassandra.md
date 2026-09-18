# Cassandra

The platform stores all tenant and device data in Cassandra. Deploy it before
installing the chart; the `uemctl` post-install job creates the keyspaces and
runs schema migrations against it.

## Requirements

- Cassandra 4.x
- Reachable from the cluster namespace at `db.address` (`host:port`, default
  CQL port 9042)
- Dedicated keyspace per installation (`db.keyspace`)

## Option A: k8ssandra-operator (recommended)

Install the operator (see the [k8ssandra docs](https://k8ssandra.io/docs/install/)
for the current version):

```bash
helm repo add k8ssandra https://helm.k8ssandra.io/stable
helm repo update
helm install k8ssandra-operator k8ssandra/k8ssandra-operator \
  -n k8ssandra-operator --create-namespace
```

Create a `CassandraDatacenter` (minimal example):

```yaml
apiVersion: cassandra.datastax.com/v1beta1
kind: CassandraDatacenter
metadata:
  name: dc1
spec:
  clusterName: uem-cluster
  serverType: cassandra
  serverVersion: "4.0.17"
  size: 3                     # >= 3 nodes for production
  storageConfig:
    cassandraDataVolumeClaimSpec:
      storageClassName: <your-storage-class>
      accessModes:
        - ReadWriteOnce
      resources:
        requests:
          storage: 200Gi
  config:
    cassandra-yaml:
      auto_snapshot: false
      commitlog_sync_period_in_ms: 10000
    jvm-options:
      initial_heap_size: 4G
      max_heap_size: 4G
```

Wait until the datacenter is ready:

```bash
kubectl get cassandradatacenter dc1 -w
# STATUS: Ready
```

The operator creates a headless service named
`<clusterName>-<datacenterName>-service`, i.e. `uem-cluster-dc1-service` on
port 9042.

Chart values (same namespace):

```yaml
db:
  address: uem-cluster-dc1-service:9042
  keyspace: uem
  username: ""
  password: ""
  replication: 3
  keyspaceClass:
    keyspaceClass: NetworkTopologyStrategy
    dataCenter:
      dc1: 3
```

> The example above does not enable authentication. For production enable
> Cassandra auth, create a user, and set `db.username` / `db.password`
> accordingly.

Cross-namespace access uses `<service>.<namespace>.svc.cluster.local`.

## Option B: external Cassandra

Any Cassandra 4.x cluster reachable from Kubernetes works. Point `db.address`
at the contact point(s) and set credentials:

```yaml
db:
  address: cassandra.internal.example.com:9042
  keyspace: uem
  username: uemdb
  password: <secret>
  replication: 3
```

## Verification

```bash
# from any pod with cqlsh, or via a debug pod in the platform namespace
cqlsh -u <user> -p <password> uem-cluster-dc1-service 9042
```
