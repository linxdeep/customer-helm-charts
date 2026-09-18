# Elasticsearch

Elasticsearch stores the device search index. The `uemctl` post-install job
creates the index templates; it needs a working endpoint and credentials.

## Requirements

- Elasticsearch 8.x / 9.x (9.x recommended)
- HTTPS endpoint reachable from the cluster
- Credentials with index-management rights

## Recommended: ECK (Elastic Cloud on Kubernetes)

Install the [ECK operator](https://www.elastic.co/guide/en/cloud-on-k8s/current/index.html):

```bash
# Use the latest 3.x ECK release (required for Elasticsearch 9.x)
kubectl apply -f https://download.elastic.co/downloads/eck/3.1.0/crds.yaml
kubectl apply -f https://download.elastic.co/downloads/eck/3.1.0/operator.yaml
```

Create a cluster (minimal example):

```yaml
apiVersion: elasticsearch.k8s.elastic.co/v1
kind: Elasticsearch
metadata:
  name: elasticsearch
  namespace: search
spec:
  version: 9.1.0
  nodeSets:
    - name: masters
      count: 3
      config:
        node.roles: ["master", "data", "ingest"]
        node.store.allow_mmap: false
      volumeClaimTemplates:
        - metadata:
            name: elasticsearch-data
          spec:
            accessModes: [ReadWriteOnce]
            storageClassName: <your-storage-class>
            resources:
              requests:
                storage: 100Gi
```

Wait until the cluster is green:

```bash
kubectl -n search get elasticsearch -w
```

ECK creates:

- Service `<name>-es-http` (port 9200)
- Secret `<name>-es-elastic-user` with the `elastic` user password

Read the password:

```bash
kubectl -n search get secret elasticsearch-es-elastic-user \
  -o jsonpath='{.data.elastic}' | base64 -d
```

Chart values (self-signed certificates are used by default, so keep
`insecureSkipVerify` or provide a proper CA):

```yaml
search:
  type: es
  deviceIndexPrefix: devices
  es:
    addresses:
      - https://elasticsearch-es-http.search.svc.cluster.local:9200
    username: elastic
    password: <password-from-the-secret>
    insecureSkipVerify: true
    maxRetries: 3
    timeout: 10s
```

## Option B: external Elasticsearch

Any reachable Elasticsearch 8.x / 9.x endpoint works:

```yaml
search:
  es:
    addresses:
      - https://es.internal.example.com:9200
    username: uem-search
    password: <secret>
    insecureSkipVerify: false
```

## Verification

```bash
kubectl run es-check --rm -it --image=curlimages/curl:8.11.1 --restart=Never -- \
  curl -sk -u 'elastic:<password>' \
  https://elasticsearch-es-http.search:9200/_cluster/health
```
