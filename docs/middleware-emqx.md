# EMQX (MQTT broker, clustered)

All device communication goes through MQTT. EMQX must be deployed as a
**cluster** (2+ core nodes recommended, 3 for production).

**Supported versions: EMQX 5.7.x / 5.8.x (tested with 5.7.2).**

This chart connects to the externally deployed cluster:

- `emqx.address` — MQTT listener, `host:port` (default port 1883)
- `emqx.apiAddress` — management API, `host:port` (default port 18083)
- `emqx.adminPassword` — dashboard admin password (used by the bootstrap job)
- `mqtt.username` / `mqtt.password` — MQTT credentials the platform uses

## Option A: EMQX Operator (recommended)

The example below is the tested setup from
[examples/eks-deploy-guide.md](../examples/eks-deploy-guide.md) §11; the
matching connection values are in [examples/values-full.yaml](../examples/values-full.yaml).

Install the operator (it requires cert-manager, see
[middleware-cassandra.md](middleware-cassandra.md)):

```bash
helm repo add emqx https://repos.emqx.io/charts
helm repo update

helm install emqx-operator emqx/emqx-operator \
  --namespace emqx-operator-system \
  --create-namespace \
  --set installCRDs=true \
  --version 2.2.29
```

Create the cluster (tested example — namespace `emqx`, open-source `EMQX` CR,
dashboard bound to 0.0.0.0:18083 so the API is reachable through the generated
`emqx-dashboard` service):

```yaml
apiVersion: apps.emqx.io/v2beta1
kind: EMQX
metadata:
  name: emqx
  namespace: emqx
spec:
  image: emqx:5.7.2
  config:
    data: |
      dashboard.listeners.http.bind = "0.0.0.0:18083"
  coreTemplate:
    spec:
      replicas: 3
      env:
        - name: EMQX_DASHBOARD__LISTENERS__HTTP__BIND
          value: "0.0.0.0:18083"
      resources:
        requests:
          cpu: "1"
          memory: 4Gi
        limits:
          cpu: "2"
          memory: 8Gi
      volumeClaimTemplates:
        storageClassName: gp3   # your storage class
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 20Gi
```

Wait until the cluster is ready:

```bash
kubectl get emqx emqx -n emqx -w
```

The operator creates the `emqx-listeners` service (MQTT 1883 and friends) and
the `emqx-dashboard` service (API 18083). Chart values (cross-namespace, as
tested; `adminPassword: public` is the EMQX default — change it and the
matching MQTT credentials for anything beyond testing):

```yaml
emqx:
  address: emqx-listeners.emqx.svc.cluster.local:1883
  apiAddress: emqx-dashboard.emqx.svc.cluster.local:18083
  adminPassword: "public"
  bootstrap:
    enabled: true
mqtt:
  username: admin
  password: public
```

If your services are named differently, adjust `emqx.address` /
`emqx.apiAddress` accordingly.

## Option B: any external EMQX

Any reachable EMQX 5.7.x / 5.8.x cluster works:

```yaml
emqx:
  address: emqx.internal.example.com:1883
  apiAddress: emqx.internal.example.com:18083
  adminPassword: "<dashboard admin password>"
  bootstrap:
    enabled: true
mqtt:
  username: <mqtt-user>
  password: <mqtt-password>
```

## What the bootstrap job does

On install/upgrade the chart runs a post-install job (`emqx`) that:

1. Logs in to the EMQX API as `admin` with `emqx.adminPassword`
2. Creates an API key for the platform and patches it into the `middleware`
   ConfigMap
3. Creates the business rules `client_connected`, `client_disconnected` and
   `message_acked`

Set `emqx.bootstrap.enabled=false` only if you provision these yourself — then
fill `mqtt.apiKey` / `mqtt.apiSecret` and create the three rules manually. The
script below does exactly what the job would do; run it from any host that can
reach `emqx.apiAddress` and has `curl`:

```bash
#!/bin/sh
set -e
EMQX_API="http://<emqx-api-address>"   # same value as emqx.apiAddress
ADMIN_PASSWORD="<dashboard-admin-password>"

TOKEN=$(curl -sS -X POST "${EMQX_API}/api/v5/login" \
  -H 'accept: application/json' -H 'Content-Type: application/json' \
  -d "{\"username\": \"admin\", \"password\": \"${ADMIN_PASSWORD}\"}" \
  | grep -o '"token":"[^"]*"' | awk -F'"' '{print $4}')

curl -sS -X POST "${EMQX_API}/api/v5/api_key" \
  -H 'Content-Type: application/json' -H "Authorization: Bearer $TOKEN" \
  -d '{"name": "http", "enable": true, "expired": false, "desc": "api"}'
# -> note the returned api_key / api_secret for mqtt.apiKey / mqtt.apiSecret

curl -sS -X POST "${EMQX_API}/api/v5/rules" \
  -H 'Content-Type: application/json' -H "Authorization: Bearer $TOKEN" \
  -d '{
    "id": "client_disconnected", "enable": true,
    "sql": "SELECT\n  clientid\nFROM\n  \"$events/client_disconnected\"",
    "actions": [{
      "args": {"retain": false, "payload": "${clientid}", "topic": "client_disconnected", "qos": 1},
      "function": "republish"}]}'

curl -sS -X POST "${EMQX_API}/api/v5/rules" \
  -H 'Content-Type: application/json' -H "Authorization: Bearer $TOKEN" \
  -d '{
    "id": "client_connected", "enable": true,
    "sql": "SELECT\n  clientid\nFROM\n  \"$events/client_connected\"",
    "actions": [{
      "args": {"retain": false, "payload": "${clientid}", "topic": "client_connected", "qos": 1},
      "function": "republish"}]}'

curl -sS -X POST "${EMQX_API}/api/v5/rules" \
  -H 'Content-Type: application/json' -H "Authorization: Bearer $TOKEN" \
  -d '{
    "id": "message_acked", "enable": true,
    "sql": "SELECT\n  clientid,\n  last(split(payload, '\'':'\'', '\''trailing'\'')) as idx\nFROM\n  \"$events/message_acked\"\nWHERE\n  topic = clientid AND\n  (\n    first(split(payload, '\'':'\'', '\''leading'\'')) = '\''rename'\'' OR\n    first(split(payload, '\'':'\'', '\''leading'\'')) = '\''tip-message'\'' OR\n    first(split(payload, '\'':'\'', '\''leading'\'')) = '\''message'\'' OR\n    first(split(payload, '\'':'\'', '\''leading'\'')) = '\''uninstall'\'' OR\n    first(split(payload, '\'':'\'', '\''leading'\'')) = '\''script'\'' OR\n    first(split(payload, '\'':'\'', '\''leading'\'')) = '\''block'\'' OR\n    first(split(payload, '\'':'\'', '\''leading'\'')) = '\''customLockDate'\'' OR\n    first(split(payload, '\'':'\'', '\''leading'\'')) = '\''resetpassword'\'' OR\n    first(split(payload, '\'':'\'', '\''leading'\'')) = '\''time-zone'\'' OR\n    first(split(payload, '\'':'\'', '\''leading'\'')) = '\''align'\''\n  )",
    "actions": [{
      "args": {"retain": false, "payload": "${clientid}:${idx}", "topic": "message_acked", "qos": 1},
      "function": "republish"}]}'
```

Or create the key and rules through the EMQX dashboard / your configuration
management — only the end state matters.

## Exposing MQTT to devices

MQTT (TCP 1883, TLS 8883) and MQTT over WebSocket (8083/8084) cannot be
served through a plain HTTP ingress. Expose them with a LoadBalancer service
in front of your EMQX cluster, e.g.:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: emqx-lb
  namespace: <platform-namespace>
spec:
  type: LoadBalancer
  selector:
    <your EMQX pod labels>
  ports:
    - name: mqtt
      port: 1883
      targetPort: 1883
    - name: mqtt-tls
      port: 8883
      targetPort: 8883
```

Then set `mqtt.external` to the public hostname of that load balancer and
`mqtt.tcpPort` / `mqtt.sslPort` to the public ports. Install a TLS certificate
on EMQX itself for the SSL port.
