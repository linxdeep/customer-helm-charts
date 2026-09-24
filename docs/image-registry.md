# Pulling images from a private registry

All images are referenced through two global settings:

```yaml
global:
  imageRegistry: "registry.example.com"   # prefix prepended to every image
  imagePullSecrets:
    - name: regcred                       # secret with the registry credentials
```

Service images default to `uem/<service>` paths (see `charts/uem/values.yaml`),
so with the example above the deployment pulls
`registry.example.com/uem/bff:<tag>`.

If your nodes can pull anonymously (public registry, or node-level
credentials), omit `imagePullSecrets`.

## Creating the pull secret

```bash
kubectl -n <platform-namespace> create secret docker-registry regcred \
  --docker-server=registry.example.com \
  --docker-username=<user> \
  --docker-password=<password-or-token>
```

## Private registry on AWS ECR

ECR authentication tokens are **valid for 12 hours only**. A secret created
once with `aws ecr get-login-password` stops working after that. Choose one
of the approaches below.

### A. EKS with node IAM access (no secret needed)

If the platform runs on EKS and the node role can read the ECR repositories,
kubelet pulls without any imagePullSecret. For cross-account repositories
(images hosted in another AWS account) add a repository policy on the ECR
side granting the cluster's node role:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "AWS": "arn:aws:iam::<cluster-account-id>:role/<node-role>" },
    "Action": [
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer"
    ]
  }]
}
```

Then set only `global.imageRegistry` and leave `imagePullSecrets` empty.

### B. Any cluster: periodically refreshed secret

Create the initial secret, then refresh it with a CronJob at an interval well
below 12 hours (e.g. every 6). The example refreshes with static AWS keys via
env vars; on EKS prefer IRSA (a dedicated service account bound to a role)
instead of long-lived keys:

```bash
kubectl -n <platform-namespace> create secret docker-registry ecr-registry-secret \
  --docker-server=<account-id>.dkr.ecr.<region>.amazonaws.com \
  --docker-username=AWS \
  --docker-password=$(aws ecr get-login-password --region <region>)
```

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: ecr-refresh-creds        # AWS keys used ONLY by the refresh job
  namespace: <platform-namespace>
type: Opaque
stringData:
  AWS_ACCESS_KEY_ID: <key-id>
  AWS_SECRET_ACCESS_KEY: <secret>
  AWS_DEFAULT_REGION: <region>
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ecr-refresh
  namespace: <platform-namespace>
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ecr-refresh
  namespace: <platform-namespace>
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    resourceNames: ["ecr-registry-secret"]
    verbs: ["get", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ecr-refresh
  namespace: <platform-namespace>
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: ecr-refresh
subjects:
  - kind: ServiceAccount
    name: ecr-refresh
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: ecr-secret-refresh
  namespace: <platform-namespace>
spec:
  schedule: "0 */6 * * *"
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      backoffLimit: 2
      template:
        spec:
          serviceAccountName: ecr-refresh
          restartPolicy: Never
          containers:
            - name: refresh
              image: public.ecr.aws/aws-cli/aws-cli:latest
              envFrom:
                - secretRef:
                    name: ecr-refresh-creds
              command: ["/bin/sh", "-c"]
              args:
                - |
                  set -e
                  REGISTRY="<account-id>.dkr.ecr.<region>.amazonaws.com"
                  PASSWORD=$(aws ecr get-login-password --region <region>)
                  AUTH=$(printf 'AWS:%s' "$PASSWORD" | base64)
                  DOCKERCONFIG=$(printf '{"auths":{"%s":{"username":"AWS","password":"%s","auth":"%s"}}}' "$REGISTRY" "$PASSWORD" "$AUTH" | base64 | tr -d '\n')
                  kubectl -n <platform-namespace> patch secret ecr-registry-secret \
                    -p "{\"data\":{\".dockerconfigjson\":\"$DOCKERCONFIG\"}}"
```

Ready-made tools such as
[nabsul/k8s-ecr-login-renew](https://github.com/nabsul/k8s-ecr-login-renew)
do the same job if you prefer not to maintain the manifest yourself.

Chart values:

```yaml
global:
  imageRegistry: "<account-id>.dkr.ecr.<region>.amazonaws.com"
  imagePullSecrets:
    - name: ecr-registry-secret
```

### C. Avoid ECR auth entirely

Mirror the images to a registry the cluster can already reach (ECR Public
Gallery `public.ecr.aws` allows anonymous pulls of public repositories, or a
registry inside the customer network), then set `global.imageRegistry`
accordingly.

## Minimal IAM policy for pull-only ECR access

For the AWS credentials used by the cluster (dedicated IAM user or role):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["ecr:GetAuthorizationToken"],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer"
      ],
      "Resource": "arn:aws:ecr:<region>:<account-id>:repository/<repo-prefix>/*"
    }
  ]
}
```

> Note: init containers also use public utility images
> (`global.kubectlImage`, `global.curlImage`, `global.waitForImage`). In an
> air-gapped environment mirror those too and override the values.
