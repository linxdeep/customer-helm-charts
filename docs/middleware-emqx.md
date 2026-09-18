# EMQX (MQTT broker, clustered)

All device communication goes through MQTT. EMQX must be deployed as a
**cluster** (2+ core nodes recommended, 3 for production).

**Supported versions: EMQX 5.7.x / 5.8.x — use the latest 5.8 patch release.**

The platform connects with:

- `emqx.address` — MQTT listener, `host:port` (default port 1883)
- `emqx.apiAddress` — management API, `host:port` (default port 18083)
- `emqx.adminPassword` — dashboard admin password
- `mqtt.username` / `mqtt.password` — MQTT credentials the platform uses

## Recommended: EMQX Operator

Install the [EMQX Operator](https://docs.emqx.com/en/emqx-operator/latest/)
(it requires cert-manager):

```bash
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager jetstack/cert-manager \
  -n cert-manager --create-namespace \
  --set crds.enabled=true

helm repo add emqx https://repos.emqx.io/charts
helm repo update
helm install emqx-operator emqx/emqx-operator \
  -n emqx-system --create-namespace
```

Create a cluster named `emqx` so the generated services match the default
chart values (minimal example):

```yaml
apiVersion: apps.emqx.io/v2beta1
kind: EmqxEnterprise
metadata:
  name: emqx
  namespace: <platform-namespace>
spec:
  replication: 3
  template:
    spec:
      emqxContainer:
        image: emqx/emqx:5.8.3
        resources:
          requests:
            cpu: 500m
            memory: 1Gi
          limits:
            cpu: "2"
            memory: 4Gi
      # Set the dashboard admin password so it matches emqx.adminPassword.
      # EMQX 5 hashes dashboard passwords; generate one with
      #   docker run --rm emqx/emqx:5.8.3 emqx eval 'emqx_dashboard_hash:hash(<<"YourPassword">>)'
      # and paste the resulting bcrypt hash below.
      # bootstrapConfig:
      #   dashboard:
      #     default_password: "<bcrypt-hash>"
  coreTemplate:
    spec:
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              podAffinityTerm:
                topologyKey: kubernetes.io/hostname
                labelSelector:
                  matchLabels:
                    apps.emqx.io/instance: emqx
```

Check the generated services and confirm the ports before installing the
platform chart:

```bash
kubectl -n <platform-namespace> get svc
```

Defaults in the platform chart assume the operator-created service is named
`emqx` with MQTT on 1883 and the API on 18083:

```yaml
emqx:
  address: emqx:1883
  apiAddress: emqx:18083
  adminPassword: "<the dashboard password you configured>"
  bootstrap:
    enabled: true
mqtt:
  username: <mqtt-user>
  password: <mqtt-password>
```

If the services are named differently (cross-namespace, custom CR name), adjust
`emqx.address` / `emqx.apiAddress` accordingly.

## What the bootstrap job does

On install/upgrade the chart runs a post-install job (`emqx`) that:

1. Logs in to the EMQX API as `admin` with `emqx.adminPassword`
2. Creates an API key for the platform and patches it into the `middleware`
   ConfigMap
3. Creates the business rules `client_connected`, `client_disconnected` and
   `message_acked`

If you prefer to manage this yourself, set `emqx.bootstrap.enabled=false`,
pre-create the API key and rules, and fill `mqtt.apiKey` / `mqtt.apiSecret`.

## Exposing MQTT to devices

MQTT (TCP 1883, TLS 8883) and MQTT over WebSocket (8083/8084) cannot be
served through a plain HTTP ingress. Expose them with a LoadBalancer service,
e.g.:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: emqx-lb
  namespace: <platform-namespace>
spec:
  type: LoadBalancer
  selector:
    apps.emqx.io/instance: emqx    # adjust to your EMQX pod labels
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
