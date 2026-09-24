# Kafka

Kafka carries the async event stream between services. Topics and partitions
are created automatically by the `uemctl` post-install job; you only need to
provide the bootstrap servers.

The example below is the tested setup from
[examples/eks-deploy-guide.md](../examples/eks-deploy-guide.md) §9; the
matching connection values are in [examples/values-full.yaml](../examples/values-full.yaml).

## Requirements

- Kafka 3.x or 4.x (tested with 4.3.1 in KRaft mode)
- `kafka.brokerList`: one or more bootstrap `host:port` entries
- PLAINTEXT or TLS listener reachable from inside the cluster

## Option A: Strimzi (recommended)

[Strimzi](https://strimzi.io/) is the reference open-source Kafka operator.

Install the operator:

```bash
helm repo add strimzi https://strimzi.io/charts/
helm repo update
helm install strimzi-kafka-operator strimzi/strimzi-kafka-operator \
  --namespace kafka --create-namespace
```

Create the cluster — Kafka 4.x runs KRaft-only, so deploy a combined
controller+broker node pool (tested example, namespace `kafka`, cluster name
`kafka-cluster`):

```yaml
apiVersion: kafka.strimzi.io/v1
kind: KafkaNodePool
metadata:
  name: dual-role
  namespace: kafka
  labels:
    strimzi.io/cluster: kafka-cluster
spec:
  replicas: 3
  roles:
    - controller
    - broker
  storage:
    type: persistent-claim
    size: 100Gi
    class: gp3                  # your storage class
  resources:
    requests:
      cpu: "2"
      memory: 8Gi
    limits:
      cpu: "4"
      memory: 16Gi
---
apiVersion: kafka.strimzi.io/v1
kind: Kafka
metadata:
  name: kafka-cluster
  namespace: kafka
  annotations:
    strimzi.io/node-pools: enabled
    strimzi.io/kraft: enabled
spec:
  kafka:
    version: 4.3.1
    metadataVersion: "4.3.1"
    listeners:
      - name: plain
        port: 9092
        type: internal
        tls: false
      - name: tls
        port: 9093
        type: internal
        tls: true
    config:
      offsets.topic.replication.factor: 3
      transaction.state.log.replication.factor: 3
      transaction.state.log.min.isr: 2
      default.replication.factor: 3
      min.insync.replicas: 2
      num.partitions: 3
  entityOperator:
    topicOperator: {}
    userOperator: {}
```

> For single-node test clusters set every replication factor to 1 and
> `min.insync.replicas` to 1.

Wait until ready:

```bash
kubectl wait kafka/kafka-cluster --for=condition=Ready --timeout=600s -n kafka
```

The bootstrap service is `<clusterName>-kafka-bootstrap`, i.e.
`kafka-cluster-kafka-bootstrap:9092`. Chart values (cross-namespace, as
tested):

```yaml
kafka:
  enabled: true
  brokerList:
    - kafka-cluster-kafka-bootstrap.kafka.svc.cluster.local:9092
  groupId: "uem"
```

## Option B: Bitnami Helm chart

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install kafka bitnami/kafka \
  -n <platform-namespace> \
  --set kraft.enabled=true \
  --set zookeeper.enabled=false \
  --set controller.controllerOnly=false \
  --set controller.replicaCount=3 \
  --set provisioning.enabled=true
```

Newer chart versions default to Kafka 4.x images (KRaft, no ZooKeeper) and
work equally well.

Bootstrap: `kafka-controller-headless:9092` (same namespace):

```yaml
kafka:
  enabled: true
  brokerList:
    - kafka-controller-headless:9092
  groupId: "uem"
```

## Verification

```bash
kubectl run kafka-check --rm -it --image=bitnami/kafka:4.3 --restart=Never -- \
  kafka-topics.sh --bootstrap-server kafka-cluster-kafka-bootstrap.kafka:9092 --list
```
