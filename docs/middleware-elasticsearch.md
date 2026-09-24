# Elasticsearch

Elasticsearch stores the device search index. The `uemctl` post-install job
creates the index templates; it needs a working endpoint and credentials.

The example below is the tested setup from
[examples/eks-deploy-guide.md](../examples/eks-deploy-guide.md) §12; the
matching connection values are in [examples/values-full.yaml](../examples/values-full.yaml).

## Requirements

- Elasticsearch 8.x / 9.x (tested with 9.4.7)
- HTTPS endpoint reachable from the cluster
- Credentials with index-management rights

## Option A: ECK (Elastic Cloud on Kubernetes, recommended)

Install the [ECK operator](https://www.elastic.co/guide/en/cloud-on-k8s/current/index.html)
(tested via the Helm chart):

```bash
helm repo add elastic https://helm.elastic.co
helm repo update
helm install elastic-operator elastic/eck-operator \
  --namespace elastic-system --create-namespace
```

Create the cluster (tested example — namespace `elastic`, 3 combined nodes;
the sysctl init container raises `vm.max_map_count`, which Elasticsearch
requires):

```yaml
apiVersion: elasticsearch.k8s.elastic.co/v1
kind: Elasticsearch
metadata:
  name: elasticsearch
  namespace: elastic
spec:
  version: 9.4.7
  nodeSets:
    - name: default
      count: 3
      config:
        node.roles: ["master", "data", "ingest"]
        xpack.security.enabled: true
      podTemplate:
        spec:
          initContainers:
            - name: sysctl
              securityContext:
                privileged: true
                runAsUser: 0
              command: ['sh', '-c', 'sysctl -w vm.max_map_count=262144']
          containers:
            - name: elasticsearch
              resources:
                requests:
                  cpu: "2"
                  memory: 8Gi
                limits:
                  cpu: "4"
                  memory: 16Gi
                env:
                  - name: ES_JAVA_OPTS
                    value: "-Xms4g -Xmx4g"
      volumeClaimTemplates:
        - metadata:
            name: elasticsearch-data
          spec:
            storageClassName: gp3   # your storage class
            accessModes: [ReadWriteOnce]
            resources:
              requests:
                storage: 100Gi
```

Wait until the cluster is green:

```bash
kubectl -n elastic get elasticsearch -w
```

ECK creates:

- Service `<name>-es-http` (port 9200)
- Secret `<name>-es-elastic-user` with the `elastic` user password

Read the password and fill it into the values:

```bash
kubectl -n elastic get secret elasticsearch-es-elastic-user \
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
      - https://elasticsearch-es-http.elastic.svc.cluster.local:9200
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
  https://elasticsearch-es-http.elastic.svc.cluster.local:9200/_cluster/health
```
