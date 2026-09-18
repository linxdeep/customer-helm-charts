# Ingress routing

The platform is served under a single domain (plus its wildcard subdomains).
This document lists every route so you can configure any ingress controller.
The chart can also generate a standard `networking.k8s.io/v1` Ingress for you
(`ingress.enabled=true`) — but MQTT and STUN/TURN must always be exposed
separately (see below).

All service names below are in the namespace where the chart is installed.

## HTTP routes

Priority: the more specific path wins. Order in the table is longest-path
first, matching what an nginx-style controller does automatically.

| Path (prefix) | Service : Port | Purpose |
|---|---|---|
| `/api/attachment` | `file : 80` | attachment downloads. **Method caveat:** see note below |
| `/sse/rcw` | `remote-proxy : 80` | remote control SSE stream |
| `/wss/rcw` | `remote-proxy : 80` | remote control WebSocket |
| `/zs/temp/remoteControl` | `remote-proxy : 80` | remote control helper |
| `/zs/temp/rcd` | `remote-proxy : 80` | remote control helper |
| `/api` | `bff : 80` | main API |
| `/partner` | `bff : 80` | partner API |
| `/zs` | `devices : 80` | device API used by agents |
| `/apple` | `apple : 80` | Apple MDM (APNs callbacks) |
| `/MDMServiceConfig` | `apple : 80` | Apple MDM discovery |
| `/ManagementServer` | `windows : 80` | Windows MDM (MS-MDE) |
| `/EnrollmentServer` | `windows : 80` | Windows MDM enrollment |
| `/files` | `file : 80` | file uploads/downloads |
| `/file` | `file : 80` | file uploads/downloads |
| `/dispatch` | `file : 80` | content dispatch |
| `/` (fallback) | `www : 80` | web console |

`emqx.<domain>` may optionally route to the EMQX dashboard (`emqx : 18083`)
for administrators — restrict access appropriately.

### `/api/attachment` method caveat

The reference routing sends only `GET /api/attachment` to the `file` service
(other methods, i.e. uploads, go to `bff`). Standard Ingress resources cannot
match by HTTP method, so the chart's generated route (disabled by default,
`ingress.attachmentRoute.enabled`) sends **all** `/api/attachment` requests to
`file`. Verify your upload flow before enabling it, or express the method
condition with your controller's advanced configuration (e.g. nginx
snippets).

## gRPC route (remote control)

| Path | Service : Port | Protocol |
|---|---|---|
| `/linxdeep.remote.proxy.v1.RemoteProxy` | `remote-proxy : 9099` | gRPC (h2c) |

The chart can generate a separate Ingress for this (`ingress.grpc.enabled`)
which needs a gRPC-capable controller.

## Non-HTTP traffic (no HTTP ingress)

These endpoints must be reachable by devices directly, typically via
LoadBalancer services:

| Protocol / Port | Target | Purpose |
|---|---|---|
| TCP 1883 (`mqtt.tcpPort`) | EMQX | MQTT |
| TLS 8883 (`mqtt.sslPort`) | EMQX | MQTT over TLS |
| TCP/TLS 8083, 8084 | EMQX | MQTT over WebSocket(S) |
| UDP/TCP 3478 | STUN server | remote control NAT traversal |
| TCP 3479 (+ UDP relay range) | TURN server | remote control relay |

Set `mqtt.external` to the public MQTT hostname. STUN/TURN servers are
configured via `remoteProxy.stun` / `remoteProxy.turn`.

## Example: nginx ingress controller

Using the chart-generated Ingress:

```yaml
ingress:
  enabled: true
  className: nginx
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "0"       # large uploads
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600" # long-lived SSE/WS
  tls:
    - secretName: uem-tls
      hosts: [uem.example.com]
  grpc:
    enabled: true
    annotations:
      nginx.ingress.kubernetes.io/backend-protocol: "GRPC"
domain: uem.example.com
```

WebSockets need no extra annotation on nginx (upgrading is automatic).

## Example: Traefik

Standard Ingress works on Traefik as well (`ingress.className: traefik`).
WebSockets and SSE work out of the box.

For gRPC either use the generated grpc Ingress with the h2c protocol, or a
Traefik `IngressRoute`:

```yaml
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: uem-grpc
spec:
  entryPoints: [websecure]
  routes:
    - match: Host(`uem.example.com`) && PathPrefix(`/linxdeep.remote.proxy.v1.RemoteProxy`)
      kind: Rule
      services:
        - name: remote-proxy
          port: 9099
          scheme: h2c
```

For MQTT, a Traefik TCP entryPoint + `IngressRouteTCP` pointing at the EMQX
service works as an alternative to a LoadBalancer service.
