# UEM Helm Charts

Helm charts for deploying the UEM platform (application services only).

All middleware — Cassandra, Redis, Kafka, EMQX and Elasticsearch — is deployed
and managed **outside** this chart. Operator-based deployment examples and the
required connection settings are documented under [`docs/`](docs/).

## Repository layout

```
charts/uem/    The UEM platform chart
docs/          Middleware deployment guides and ingress routing rules
examples/      Ready-to-adapt values files
```

## Prerequisites

- Kubernetes 1.26+
- Helm 3.10+
- Middleware up and running (see the deployment order below)
- A StorageClass (if you enable the shared PVC), see `pvc.storageClass`
- An ingress controller of your choice (see [docs/ingress-routing.md](docs/ingress-routing.md))
- Container images reachable from the cluster (see `global.imageRegistry`)

## Deployment order

Middleware must be ready **before** the chart is installed, because the
post-install `uemctl` job connects to all of it:

1. Cassandra — [docs/middleware-cassandra.md](docs/middleware-cassandra.md)
2. Redis — [docs/middleware-redis.md](docs/middleware-redis.md)
3. Kafka — [docs/middleware-kafka.md](docs/middleware-kafka.md)
4. EMQX (clustered) — [docs/middleware-emqx.md](docs/middleware-emqx.md)
5. Elasticsearch — [docs/middleware-elasticsearch.md](docs/middleware-elasticsearch.md)
6. This chart

## Quick start

```bash
# 1. Copy the example values and fill in your environment
cp examples/values-full.yaml my-values.yaml

# 2. Review mandatory settings (see the checklist below)
vi my-values.yaml

# 3. Install
helm install uem charts/uem -n uem --create-namespace -f my-values.yaml

# 4. Watch the initialization jobs complete, then check the pods
kubectl -n uem get jobs -w
kubectl -n uem get pods
```

### Mandatory settings checklist

| Setting | Notes |
|---|---|
| `global.imageRegistry` | Registry that hosts the UEM images |
| `global.imagePullSecrets` | Pull secret for that registry |
| `domain` | Public hostname of the console |
| `license` | License string |
| `db.*` | Cassandra address/keyspace/credentials |
| `emqx.address`, `emqx.apiAddress`, `emqx.adminPassword` | EMQX cluster endpoints and dashboard password |
| `mqtt.username/password/external` | MQTT credentials and public host |
| `redis.addr` | `host:port` of Redis |
| `kafka.brokerList` | Kafka bootstrap servers |
| `search.es.*` | Elasticsearch endpoint and credentials |
| `s3.*` | S3-compatible object storage |
| `email.*` | SMTP server for notifications |

## Routing

The chart can generate a standard `networking.k8s.io/v1` Ingress
(`ingress.enabled`), but routing is fully documented so you can also configure
your own controller: [docs/ingress-routing.md](docs/ingress-routing.md).

Note that MQTT (TCP 1883 / TLS 8883) and the remote-control STUN/TURN ports
cannot go through an HTTP ingress and must be exposed separately.

## Upgrade notes

After the first installation, the `emqx` post-install job creates an EMQX API
key and writes it into the `middleware` ConfigMap. Because Helm resets the
ConfigMap on every upgrade, **copy the generated `apiKey`/`apiSecret` into your
values file** (`mqtt.apiKey` / `mqtt.apiSecret`) once the first install
succeeds:

```bash
kubectl -n uem get configmap middleware -o jsonpath='{.data.emqx\.yaml}'
```

Alternatively, pre-provision the API key yourself in EMQX and set
`emqx.bootstrap.enabled=false` together with `mqtt.apiKey`/`mqtt.apiSecret`.

## Monitoring (optional)

Set `monitoring.enabled=true` (requires the Prometheus operator) and adjust
`monitoring.labels` so your Prometheus discovers the generated
ServiceMonitors.
