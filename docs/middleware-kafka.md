# Kafka

Kafka carries the async event stream between services. Topics and partitions
are created automatically by the `uemctl` post-install job; you only need to
provide the bootstrap servers.

## Requirements

- Kafka 3.x or 4.x
- `kafka.brokerList`: one or more bootstrap `host:port` entries
- PLAINTEXT or TLS listener reachable from inside the cluster

## Option A: Strimzi (recommended)

[Strimzi](https://strimzi.io/) is the reference open-source Kafka operator.

Install the operator:

```bash
kubectl create namespace kafka
kubectl apply -f 'https://strimzi.io/install/latest?namespace=kafka' -n kafka
```

Create a cluster (minimal 3-node example):

```yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: Kafka
metadata:
  name: uem
  namespace: kafka
spec:
  kafka:
    version: 3.9.0
    replicas: 3
    listeners:
      - name: plain
        port: 9092
        type: internal
        tls: false
    config:
      offsets.topic.replication.factor: 3
      transaction.state.log.replication.factor: 3
      transaction.state.log.min.isr: 2
      default.replication.factor: 3
      min.insync.replicas: 2
    storage:
      type: jbod
      volumes:
        - id: 0
          type: persistent-claim
          size: 100Gi
          class: <your-storage-class>
          deleteClaim: false
  zookeeper:
    replicas: 3
    storage:
      type: persistent-claim
      size: 50Gi
      class: <your-storage-class>
      deleteClaim: false
  entityOperator:
    topicOperator: {}
    userOperator: {}
```

> For single-node test clusters set every replication factor to 1 and
> `min.insync.replicas` to 1.
>
> **Kafka 4.x:** Kafka 4 removed ZooKeeper entirely. To run Kafka 4.x on
> Strimzi, set `spec.kafka.version: 4.0.0` (or newer), drop the `zookeeper`
> section and deploy in KRaft mode — see the
> [Strimzi KRaft docs](https://strimzi.io/docs/operators/latest/deploying#assembly-kraft-mode-str)
> for the exact CR shape supported by your operator version.

Wait until ready:

```bash
kubectl -n kafka wait kafka/uem --for=condition=Ready --timeout=600s
```

The bootstrap service is `<clusterName>-kafka-bootstrap`:

```yaml
kafka:
  enabled: true
  brokerList:
    - uem-kafka-bootstrap.kafka.svc.cluster.local:9092
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
  --set image.tag=3.9.0 \
  --set provisioning.enabled=true
```

Newer chart versions default to Kafka 4.x images (KRaft, no ZooKeeper) and
work equally well.

Bootstrap: `kafka-controller-headless:9092` (same namespace).

## Verification

```bash
kubectl run kafka-check --rm -it --image=bitnami/kafka:3.9 --restart=Never -- \
  kafka-topics.sh --bootstrap-server uem-kafka-bootstrap.kafka:9092 --list
```
