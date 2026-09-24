# Cassandra

The platform stores all tenant and device data in Cassandra. Deploy it before
installing the chart; the `uemctl` post-install job creates the keyspaces and
runs schema migrations against it.

The example below is the tested setup from
[examples/eks-deploy-guide.md](../examples/eks-deploy-guide.md) §8; the
matching connection values are in [examples/values-full.yaml](../examples/values-full.yaml).

## Requirements

- Cassandra 4.x (tested with 4.1.12)
- Reachable from the cluster namespace at `db.address` (`host:port`, default
  CQL port 9042)
- Dedicated keyspace per installation (`db.keyspace`)

## Option A: K8ssandra Operator (recommended)

Install cert-manager and the operator (tested versions from the reference
guide):

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set installCRDs=true

helm repo add k8ssandra https://helm.k8ssandra.io/stable
helm repo update
helm install k8ssandra-operator k8ssandra/k8ssandra-operator \
  --namespace cassandra --create-namespace
```

Create the cluster (tested example — namespace `cassandra`, datacenter `dc1`):

```yaml
apiVersion: k8ssandra.io/v1alpha1
kind: K8ssandraCluster
metadata:
  name: cassandra
  namespace: cassandra
spec:
  cassandra:
    serverVersion: "4.1.12"
    datacenters:
      - metadata:
          name: dc1
        size: 3
        storageConfig:
          cassandraDataVolumeClaimSpec:
            storageClassName: gp3        # your storage class
            accessModes:
              - ReadWriteOnce
            resources:
              requests:
                storage: 100Gi
        config:
          jvmOptions:
            heapSize: 8G
          cassandraYaml:
            materialized_views_enabled: true
        resources:
          requests:
            cpu: "2"
            memory: 16Gi
          limits:
            cpu: "4"
            memory: 32Gi
```

Wait until the datacenter is ready and all nodes are up:

```bash
kubectl get cassandradatacenter dc1 -n cassandra -w
# STATUS: Ready

kubectl exec -n cassandra cassandra-dc1-default-sts-0 -c cassandra -- nodetool status
# 3 nodes, all UN
```

### Create the application user

The operator writes the superuser credentials to the `cassandra-superuser`
secret. Use them to create the `uemdb` role:

```bash
CASS_POD=$(kubectl get pod -n cassandra \
  -l app.kubernetes.io/name=cassandra \
  -o jsonpath='{.items[0].metadata.name}')
CASS_USER=$(kubectl get secret cassandra-superuser \
  -n cassandra -o jsonpath='{.data.username}' | base64 --decode)
CASS_PASS=$(kubectl get secret cassandra-superuser \
  -n cassandra -o jsonpath='{.data.password}' | base64 --decode)

kubectl exec -it $CASS_POD -n cassandra -- \
  cqlsh -u $CASS_USER -p $CASS_PASS -e \
  "CREATE ROLE IF NOT EXISTS uemdb WITH PASSWORD = '<cassandra-password>' AND LOGIN = true AND SUPERUSER = true;"

kubectl exec -it $CASS_POD -n cassandra -- \
  cqlsh -u $CASS_USER -p $CASS_PASS -e \
  "GRANT ALL PERMISSIONS ON ALL KEYSPACES TO uemdb;"
```

The operator creates a service named `<cluster>-<datacenter>-service`, i.e.
`cassandra-dc1-service` on port 9042.

Chart values (cross-namespace, as tested):

```yaml
db:
  address: cassandra-dc1-service.cassandra.svc.cluster.local:9042
  pool: 2
  timeout: 60
  keyspace: uem
  username: uemdb
  password: <cassandra-password>
  replication: 3
  keyspaceClass:
    keyspaceClass: NetworkTopologyStrategy
    dataCenters:
      - dc1: "3"
```

> `keyspaceClass` and `dataCenters` must match the deployed datacenter: the
> keyspace is created with NetworkTopologyStrategy replicated across `dc1`.

## Option B: external Cassandra

Any Cassandra 4.x cluster reachable from Kubernetes works. Point `db.address`
at the contact point(s) and set credentials:

```yaml
db:
  address: cassandra.internal.example.com:9042
  keyspace: uem
  username: uemdb
  password: <cassandra-password>
  replication: 3
```

## Verification

```bash
kubectl run cassandra-check --rm -it --image=cassandra:4.1 --restart=Never -- \
  cqlsh -u uemdb -p <cassandra-password> \
  cassandra-dc1-service.cassandra.svc.cluster.local 9042
```
