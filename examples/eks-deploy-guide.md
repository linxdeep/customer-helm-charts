# EKS 测试集群搭建与中间件部署指南

> Region：us-east-2（美东俄亥俄）\
> 工具：AWS CLI v2 · kubectl · helm
> 组件：Cassandra · Kafka · Redis · EMQX · Elasticsearch\
> 部署方式：全部使用 Operator\
> 用途：纯测试，完成后全部删除\
> 日期：2026-09-23

## 集群规格

| workload-type    | 规格        | vCPU | 内存   | 台数 |
|------------------|-------------|------|--------|------|
| memory-intensive | r6i.2xlarge | 8    | 64 GiB | 3    |
| general          | m6i.2xlarge | 8    | 32 GiB | 3    |

------------------------------------------------------------------------

## 目录

1.  [前置准备](#1-前置准备)
2.  [创建 IAM 角色](#2-创建-iam-角色)
3.  [创建 VPC 和网络](#3-创建-vpc-和网络)
4.  [创建 EKS 集群](#4-创建-eks-集群)
5.  [创建节点组](#5-创建节点组)
6.  [安装 EBS CSI Driver](#6-安装-ebs-csi-driver)
7.  [创建 StorageClass](#7-创建-storageclass)
8.  [部署 Cassandra](#8-部署-cassandra)
9.  [部署 Kafka](#9-部署-kafka)
10. [部署 Redis](#10-部署-redis)
11. [部署 EMQX](#11-部署-emqx)
12. [部署 Elasticsearch](#12-部署-elasticsearch)
13. [验证所有组件](#13-验证所有组件)
14. [清理集群（全部删除）](#14-清理集群全部删除)

------------------------------------------------------------------------

## 1. 前置准备

``` bash
# 安装 kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s \
  https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# 安装 helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# 确认版本
aws --version && kubectl version --client && helm version

# ── 全局变量（每次新开终端执行 source ~/.eks-test-env 恢复）──
export CLUSTER_NAME="test-cluster"
export REGION="us-east-2"
export ACCOUNT_ID=$(aws sts get-caller-identity \
  --query Account --output text)

# 持久化
cat > ~/.eks-test-env << EOF
export CLUSTER_NAME="test-cluster"
export REGION="us-east-2"
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
EOF

echo "Account=$ACCOUNT_ID | Region=$REGION | Cluster=$CLUSTER_NAME"
```

## 2. 创建 IAM 角色

``` bash
# ── EKS Cluster 角色 ──────────────────────────────────────────
cat > /tmp/eks-cluster-trust.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "eks.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}
EOF

aws iam create-role \
  --role-name EKSClusterRole-test \
  --assume-role-policy-document file:///tmp/eks-cluster-trust.json

aws iam attach-role-policy \
  --role-name EKSClusterRole-test \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy

# ── Node Group 角色 ───────────────────────────────────────────
cat > /tmp/eks-node-trust.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "ec2.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}
EOF

aws iam create-role \
  --role-name EKSNodeRole-test \
  --assume-role-policy-document file:///tmp/eks-node-trust.json

aws iam attach-role-policy --role-name EKSNodeRole-test \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
aws iam attach-role-policy --role-name EKSNodeRole-test \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
aws iam attach-role-policy --role-name EKSNodeRole-test \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy

# ── EBS CSI Driver 角色（占位，第 6 步更新信任策略）──────────
cat > /tmp/ebs-csi-trust.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "ec2.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}
EOF

aws iam create-role \
  --role-name EBSCSIDriverRole-test \
  --assume-role-policy-document file:///tmp/ebs-csi-trust.json

aws iam attach-role-policy --role-name EBSCSIDriverRole-test \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy

echo "IAM 角色创建完成"
```

## 3. 创建 VPC 和网络

``` bash
# 创建 VPC
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block 10.1.0.0/16 \
  --region $REGION \
  --query 'Vpc.VpcId' --output text)

aws ec2 modify-vpc-attribute --vpc-id $VPC_ID \
  --enable-dns-hostnames --region $REGION
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID \
  --enable-dns-support --region $REGION
aws ec2 create-tags --resources $VPC_ID --region $REGION \
  --tags Key=Name,Value=eks-test-vpc

# Internet Gateway
IGW_ID=$(aws ec2 create-internet-gateway \
  --region $REGION \
  --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway \
  --vpc-id $VPC_ID --internet-gateway-id $IGW_ID --region $REGION

# 3 个公有子网（跨 AZ）
SUBNET_1=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID --cidr-block 10.1.1.0/24 \
  --availability-zone ${REGION}a --region $REGION \
  --query 'Subnet.SubnetId' --output text)

SUBNET_2=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID --cidr-block 10.1.2.0/24 \
  --availability-zone ${REGION}b --region $REGION \
  --query 'Subnet.SubnetId' --output text)

SUBNET_3=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID --cidr-block 10.1.3.0/24 \
  --availability-zone ${REGION}c --region $REGION \
  --query 'Subnet.SubnetId' --output text)

# 开启公有 IP 自动分配
for SUBNET in $SUBNET_1 $SUBNET_2 $SUBNET_3; do
  aws ec2 modify-subnet-attribute \
    --subnet-id $SUBNET --map-public-ip-on-launch --region $REGION
done

# 路由表
RT_ID=$(aws ec2 create-route-table \
  --vpc-id $VPC_ID --region $REGION \
  --query 'RouteTable.RouteTableId' --output text)

aws ec2 create-route \
  --route-table-id $RT_ID \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id $IGW_ID --region $REGION

for SUBNET in $SUBNET_1 $SUBNET_2 $SUBNET_3; do
  aws ec2 associate-route-table \
    --subnet-id $SUBNET --route-table-id $RT_ID --region $REGION
done

# EKS 所需子网标签
for SUBNET in $SUBNET_1 $SUBNET_2 $SUBNET_3; do
  aws ec2 create-tags --resources $SUBNET --region $REGION --tags \
    Key=kubernetes.io/cluster/${CLUSTER_NAME},Value=shared \
    Key=kubernetes.io/role/elb,Value=1
done

# 持久化网络变量
cat >> ~/.eks-test-env << EOF
export VPC_ID=$VPC_ID
export IGW_ID=$IGW_ID
export RT_ID=$RT_ID
export SUBNET_1=$SUBNET_1
export SUBNET_2=$SUBNET_2
export SUBNET_3=$SUBNET_3
EOF

echo "VPC=$VPC_ID"
echo "Subnets: $SUBNET_1 $SUBNET_2 $SUBNET_3"
```

## 4. 创建 EKS 集群

``` bash
CLUSTER_ROLE_ARN=$(aws iam get-role \
  --role-name EKSClusterRole-test \
  --query 'Role.Arn' --output text)

# 创建集群（约 10-15 分钟）
aws eks create-cluster \
  --name $CLUSTER_NAME \
  --region $REGION \
  --kubernetes-version 1.30 \
  --role-arn $CLUSTER_ROLE_ARN \
  --resources-vpc-config \
    subnetIds=${SUBNET_1},${SUBNET_2},${SUBNET_3},\
endpointPublicAccess=true,endpointPrivateAccess=true

echo "等待集群 ACTIVE（约 10-15 分钟）..."
aws eks wait cluster-active \
  --name $CLUSTER_NAME --region $REGION

# 更新 kubeconfig
aws eks update-kubeconfig \
  --region $REGION --name $CLUSTER_NAME

kubectl get svc
echo "集群创建完成"
```

## 5. 创建节点组

``` bash
NODE_ROLE_ARN=$(aws iam get-role \
  --role-name EKSNodeRole-test \
  --query 'Role.Arn' --output text)

# ── 内存密集型节点组（Cassandra + Elasticsearch）──────────────
# r6i.2xlarge：8 vCPU / 64 GB × 3 节点
aws eks create-nodegroup \
  --cluster-name $CLUSTER_NAME \
  --nodegroup-name memory-nodes \
  --node-role $NODE_ROLE_ARN \
  --subnets $SUBNET_1 $SUBNET_2 $SUBNET_3 \
  --instance-types r6i.2xlarge \
  --scaling-config minSize=3,maxSize=6,desiredSize=3 \
  --disk-size 100 \
  --labels workload-type=memory-intensive \
  --taints '[{"key":"workload-type","value":"memory-intensive","effect":"NO_SCHEDULE"}]' \
  --ami-type AL2_x86_64 \
  --region $REGION

# ── 通用节点组（Kafka + Redis + EMQX）────────────────────────
# m6i.2xlarge：8 vCPU / 32 GB × 3 节点
aws eks create-nodegroup \
  --cluster-name $CLUSTER_NAME \
  --nodegroup-name general-nodes \
  --node-role $NODE_ROLE_ARN \
  --subnets $SUBNET_1 $SUBNET_2 $SUBNET_3 \
  --instance-types m6i.2xlarge \
  --scaling-config minSize=3,maxSize=6,desiredSize=3 \
  --disk-size 100 \
  --labels workload-type=general \
  --ami-type AL2_x86_64 \
  --region $REGION

echo "等待节点组就绪（约 5-10 分钟）..."
aws eks wait nodegroup-active \
  --cluster-name $CLUSTER_NAME \
  --nodegroup-name memory-nodes --region $REGION

aws eks wait nodegroup-active \
  --cluster-name $CLUSTER_NAME \
  --nodegroup-name general-nodes --region $REGION

kubectl get nodes -L workload-type
```

## 6. 安装 EBS CSI Driver

``` bash
source ~/.eks-test-env

# 直接用 AWS CLI 创建 OIDC Provider（无需手动获取 thumbprint）
# AWS EKS 的 OIDC 端点固定使用这个 thumbprint
aws iam create-open-id-connect-provider \
  --url https://oidc.eks.us-east-2.amazonaws.com/id/7EACE41C4B4A18C180C3BA68BBD4E41F \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 9e99a48a9960b14926bb7f3b02e22da2b0ab7280

# 持久化 OIDC 变量
export OIDC_URL="oidc.eks.us-east-2.amazonaws.com/id/7EACE41C4B4A18C180C3BA68BBD4E41F"
echo "export OIDC_URL=$OIDC_URL" >> ~/.eks-test-env

# 更新 EBSCSIDriverRole-test 的信任策略
cat > /tmp/ebs-csi-trust-irsa.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_URL}"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "${OIDC_URL}:aud": "sts.amazonaws.com",
        "${OIDC_URL}:sub": "system:serviceaccount:kube-system:ebs-csi-controller-sa"
      }
    }
  }]
}
EOF

aws iam update-assume-role-policy \
  --role-name EBSCSIDriverRole-test \
  --policy-document file:///tmp/ebs-csi-trust-irsa.json

EBS_ROLE_ARN=$(aws iam get-role \
  --role-name EBSCSIDriverRole-test \
  --query 'Role.Arn' --output text)

# 安装 EBS CSI Driver Addon
aws eks create-addon \
  --cluster-name $CLUSTER_NAME \
  --addon-name aws-ebs-csi-driver \
  --service-account-role-arn $EBS_ROLE_ARN \
  --region $REGION

aws eks wait addon-active \
  --cluster-name $CLUSTER_NAME \
  --addon-name aws-ebs-csi-driver \
  --region $REGION

echo "EBS CSI Driver 安装完成"
```

## 7. 创建 StorageClass

``` bash
cat > /tmp/storageclass.yaml << 'EOF'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  iops: "3000"
  throughput: "125"
  encrypted: "true"
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
allowVolumeExpansion: true
EOF

kubectl apply -f /tmp/storageclass.yaml

# 取消 gp2 默认（如存在）
kubectl patch storageclass gp2 \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}' \
  2>/dev/null || true

kubectl get storageclass
```

## 动态开关机

```

# 缩容 general-nodes
aws eks update-nodegroup-config \
  --cluster-name test-cluster \
  --nodegroup-name general-nodes \
  --scaling-config minSize=0,maxSize=10,desiredSize=0 \
  --region us-east-2

# 缩容 memory-nodes
aws eks update-nodegroup-config \
  --cluster-name test-cluster \
  --nodegroup-name memory-nodes \
  --scaling-config minSize=0,maxSize=10,desiredSize=0 \
  --region us-east-2


# 恢复 general-nodes
aws eks update-nodegroup-config \
  --cluster-name test-cluster \
  --nodegroup-name general-nodes \
  --scaling-config minSize=1,maxSize=10,desiredSize=3 \
  --region us-east-2

# 恢复 memory-nodes
aws eks update-nodegroup-config \
  --cluster-name test-cluster \
  --nodegroup-name memory-nodes \
  --scaling-config minSize=1,maxSize=10,desiredSize=3 \
  --region us-east-2

```

## 8. 部署 Cassandra（K8ssandra Operator）

### 8.1 安装 cert-manager

``` bash
# cert-manager（K8ssandra 依赖）
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true

kubectl wait --for=condition=ready pod \
  -l app=cert-manager -n cert-manager --timeout=120s
```

### 8.2 K8ssandra Operator

``` bash
helm repo add k8ssandra https://helm.k8ssandra.io/stable
helm repo update

helm install k8ssandra-operator k8ssandra/k8ssandra-operator \
  --namespace cassandra \
  --create-namespace

kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=k8ssandra-operator \
  -n cassandra --timeout=120s
```

### 8.3 部署 Cassandra 集群

``` bash
cat > cassandra-cluster.yaml << 'EOF'
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
            storageClassName: gp3
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
        tolerations:
          - key: workload-type
            value: memory-intensive
            effect: NoSchedule
EOF

kubectl apply -f cassandra-cluster.yaml

# 等待集群就绪
kubectl wait --for=condition=Ready \
  cassandradatacenter/dc1 \
  -n k8ssandra-operator --timeout=600s

```

### 8.4 验证集群状态

``` bash
# 查看 pod 状态（预期 3 个 2/2 Running）
kubectl get pods -n cassandra

# 查看 dc1 状态
kubectl get cassandradatacenter dc1 -n cassandra

# 查看 K8ssandraCluster 状态（ERROR 应为 None）
kubectl get k8ssandracluster -n cassandra

# 验证 Cassandra 节点（预期 3 个 UN）
kubectl exec -n cassandra cassandra-dc1-default-sts-0 \
  -c cassandra -- nodetool status
  
# 等待集群全部 UN
# Datacenter: dc1
# ===============
# Status=Up/Down
# |/ State=Normal/Leaving/Joining/Moving
# --  Address     Load        Tokens  Owns (effective)  Host ID                               Rack
# UN  10.1.3.128  109.32 KiB  16      100.0%            92d4bd93-655c-4078-a945-72fc4c76a78b  default
# UN  10.1.2.163  75.12 KiB   16      100.0%            db6c1fca-d979-4d52-9c93-cbd1d9f8db58  default
# UN  10.1.1.107  75.2 KiB    16      100.0%            abb3281c-a7f3-4785-a41c-5eed88a3a5c0  default

```

### 8.3 创建用户 uemdb

``` bash
# 获取 superuser 凭证
CASS_POD=$(kubectl get pod -n cassandra \
  -l app.kubernetes.io/name=cassandra \
  -o jsonpath='{.items[0].metadata.name}')

CASS_USER=$(kubectl get secret cassandra-superuser \
  -n cassandra -o jsonpath='{.data.username}' | base64 --decode)

CASS_PASS=$(kubectl get secret cassandra-superuser \
  -n cassandra -o jsonpath='{.data.password}' | base64 --decode)

echo "Superuser: $CASS_USER | Pod: $CASS_POD"

# 创建用户 uemdb
kubectl exec -it $CASS_POD -n cassandra -- \
  cqlsh -u $CASS_USER -p $CASS_PASS -e \
  "CREATE ROLE IF NOT EXISTS uemdb WITH PASSWORD = 'Welcome1234' AND LOGIN = true AND SUPERUSER = true;"

# 授予所有 keyspace 权限
kubectl exec -it $CASS_POD -n cassandra -- \
  cqlsh -u $CASS_USER -p $CASS_PASS -e \
  "GRANT ALL PERMISSIONS ON ALL KEYSPACES TO uemdb;"

# 验证用户创建成功
kubectl exec -it $CASS_POD -n cassandra -- \
  cqlsh -u $CASS_USER -p $CASS_PASS -e "LIST ROLES;"
```

## 9. 部署 Kafka（Strimzi Operator）

``` bash
helm repo add strimzi https://strimzi.io/charts/
helm repo update

helm install strimzi-kafka-operator strimzi/strimzi-kafka-operator \
  --namespace kafka \
  --create-namespace

kubectl wait --for=condition=ready pod \
  -l name=strimzi-cluster-operator \
  -n kafka --timeout=120s

cat > kafka-cluster.yaml << EOF
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
    class: gp3
  resources:
    requests:
      cpu: "2"
      memory: 8Gi
    limits:
      cpu: "4"
      memory: 16Gi
  template:
    pod:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: workload-type
                    operator: In
                    values: [general]
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
EOF

# 再等 CRD 就绪
kubectl wait --for=condition=established crd/kafkas.kafka.strimzi.io --timeout=120s
kubectl wait --for=condition=established crd/kafkanodepools.kafka.strimzi.io --timeout=120s

# 最后再 apply
kubectl apply -f kafka-cluster.yaml

kubectl wait kafka/kafka-cluster \
  --for=condition=Ready --timeout=600s -n kafka
```

## 10. 部署 Redis（OT-Container-Kit Operator）

``` bash
helm repo add ot-helm https://ot-container-kit.github.io/helm-charts/
helm repo update

helm install redis-operator ot-helm/redis-operator \
  --namespace redis-operator \
  --create-namespace

kubectl wait --for=condition=ready pod \
  -l name=redis-operator \
  -n redis-operator --timeout=120s

kubectl create namespace redis

cat > redis-cluster.yaml <<EOF
apiVersion: redis.redis.opstreelabs.in/v1beta2
kind: RedisCluster
metadata:
  name: redis-cluster
  namespace: redis
spec:
  clusterSize: 3
  clusterVersion: v8
  persistenceEnabled: true
  podSecurityContext:
    fsGroup: 1000
    runAsUser: 1000
    runAsGroup: 1000
  kubernetesConfig:
    image: quay.io/opstree/redis:v8.10.1
    imagePullPolicy: IfNotPresent
    resources:
      requests:
        cpu: "100m"
        memory: "128Mi"
      limits:
        cpu: "500m"
        memory: "1024Mi"
  storage:
    keepAfterDelete: false
    nodeConfVolume: true
    volumeClaimTemplate:
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: gp3
        resources:
          requests:
            storage: 10Gi
    nodeConfVolumeClaimTemplate:
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: gp3
        resources:
          requests:
            storage: 1Gi
  redisLeader:
    replicas: 3
    affinity:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
            - matchExpressions:
                - key: workload-type
                  operator: In
                  values: [memory-intensive]
    tolerations:
      - key: "workload-type"
        operator: "Equal"
        value: "memory-intensive"
        effect: "NoSchedule"
  redisFollower:
    replicas: 3
    affinity:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
            - matchExpressions:
                - key: workload-type
                  operator: In
                  values: [memory-intensive]
    tolerations:
      - key: "workload-type"
        operator: "Equal"
        value: "memory-intensive"
        effect: "NoSchedule"
EOF

kubectl apply -f redis-cluster.yaml
```

## 11. 部署 EMQX（EMQX Operator）

``` bash
helm repo add emqx https://repos.emqx.io/charts
helm repo update

helm install emqx-operator emqx/emqx-operator \
  --namespace emqx-operator-system \
  --create-namespace \
  --set installCRDs=true \
  --version 2.2.29

kubectl wait --for=condition=ready pod \
  -l "control-plane=controller-manager" \
  -n emqx-operator-system --timeout=120s

kubectl create namespace emqx

cat > emqx-cluster.yaml << EOF
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
        storageClassName: gp3
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 20Gi
EOF

kubectl apply -f emqx-cluster.yaml
```

## 12. 部署 Elasticsearch（ECK Operator）

``` bash
helm repo add elastic https://helm.elastic.co
helm repo update

helm install elastic-operator elastic/eck-operator \
  --namespace elastic-system \
  --create-namespace

kubectl wait --for=condition=ready pod \
  -l control-plane=elastic-operator \
  -n elastic-system --timeout=120s

kubectl create namespace elastic

cat > elasticsearch-cluster.yaml << EOF
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
          tolerations:
            - key: workload-type
              value: memory-intensive
              effect: NoSchedule
          nodeSelector:
            workload-type: memory-intensive
      volumeClaimTemplates:
        - metadata:
            name: elasticsearch-data
          spec:
            storageClassName: gp3
            accessModes: [ReadWriteOnce]
            resources:
              requests:
                storage: 100Gi
EOF

kubectl apply -f elasticsearch-cluster.yaml

# 获取 elastic 用户默认密码
echo "Elasticsearch 密码："
kubectl get secret elasticsearch-es-elastic-user \
  -n elastic \
  -o jsonpath='{.data.elastic}' | base64 --decode && echo
```

## 13. 验证所有组件

``` bash
echo "===== Nodes =====" && kubectl get nodes -L workload-type
echo "===== Cassandra =====" && kubectl get pods -n cassandra
echo "===== Kafka =====" && kubectl get pods -n kafka
echo "===== Redis =====" && kubectl get pods -n redis
echo "===== EMQX =====" && kubectl get pods -n emqx
echo "===== Elasticsearch =====" && kubectl get pods -n elastic
echo "===== PVC =====" && kubectl get pvc -A

# 验证 Cassandra uemdb 用户
CASS_POD=$(kubectl get pod -n cassandra \
  -l app.kubernetes.io/name=cassandra \
  -o jsonpath='{.items[0].metadata.name}')
CASS_USER=$(kubectl get secret cassandra-superuser \
  -n cassandra -o jsonpath='{.data.username}' | base64 --decode)
CASS_PASS=$(kubectl get secret cassandra-superuser \
  -n cassandra -o jsonpath='{.data.password}' | base64 --decode)
kubectl exec -it $CASS_POD -n cassandra -- \
  cqlsh -u $CASS_USER -p $CASS_PASS -e "LIST ROLES;"
```

## 14. 清理集群

### 14.1 删除中间件和 Operator

``` bash
# 删除中间件（自动触发 PVC/EBS 卷删除）
kubectl delete -f /tmp/elasticsearch-cluster.yaml --ignore-not-found
kubectl delete -f /tmp/emqx-cluster.yaml          --ignore-not-found
kubectl delete -f /tmp/redis-cluster.yaml         --ignore-not-found
kubectl delete -f /tmp/kafka-cluster.yaml         --ignore-not-found
kubectl delete -f /tmp/cassandra-cluster.yaml     --ignore-not-found

# 等待 PVC 全部删除（确保 EBS 卷释放）
echo "等待 PVC 删除..."
for NS in cassandra kafka redis emqx elastic; do
  kubectl delete pvc --all -n $NS --ignore-not-found
done

# 卸载所有 Operator
helm uninstall elastic-operator       -n elastic-system        --ignore-not-found
helm uninstall emqx-operator          -n emqx-operator-system  --ignore-not-found
helm uninstall redis-operator         -n redis-operator        --ignore-not-found
helm uninstall strimzi-kafka-operator -n kafka                 --ignore-not-found
helm uninstall k8ssandra-operator     -n k8ssandra-operator    --ignore-not-found
helm uninstall cert-manager           -n cert-manager          --ignore-not-found

# 删除 namespace
for NS in cassandra kafka redis emqx elastic \
          elastic-system emqx-operator-system \
          redis-operator k8ssandra-operator cert-manager; do
  kubectl delete namespace $NS --ignore-not-found
done

echo "中间件和 Operator 已清理"
```

### 14.2 删除节点组

``` bash
aws eks delete-nodegroup \
  --cluster-name $CLUSTER_NAME \
  --nodegroup-name memory-nodes --region $REGION

aws eks delete-nodegroup \
  --cluster-name $CLUSTER_NAME \
  --nodegroup-name general-nodes --region $REGION

echo "等待节点组删除（约 5 分钟）..."
aws eks wait nodegroup-deleted \
  --cluster-name $CLUSTER_NAME \
  --nodegroup-name memory-nodes --region $REGION

aws eks wait nodegroup-deleted \
  --cluster-name $CLUSTER_NAME \
  --nodegroup-name general-nodes --region $REGION

echo "节点组已删除"
```

### 14.3 删除 EKS 集群

``` bash
# 删除 EBS CSI Addon
aws eks delete-addon \
  --cluster-name $CLUSTER_NAME \
  --addon-name aws-ebs-csi-driver \
  --region $REGION

# 删除集群
aws eks delete-cluster \
  --name $CLUSTER_NAME --region $REGION

echo "等待集群删除（约 10 分钟）..."
aws eks wait cluster-deleted \
  --name $CLUSTER_NAME --region $REGION

echo "EKS 集群已删除"
```

### 14.4 删除网络资源

``` bash
# 解绑子网路由表并删除子网
for SUBNET in $SUBNET_1 $SUBNET_2 $SUBNET_3; do
  ASSOC_ID=$(aws ec2 describe-route-tables \
    --filters "Name=association.subnet-id,Values=$SUBNET" \
    --query 'RouteTables[0].Associations[0].RouteTableAssociationId' \
    --output text --region $REGION 2>/dev/null)
  [ "$ASSOC_ID" != "None" ] && [ -n "$ASSOC_ID" ] && \
    aws ec2 disassociate-route-table \
      --association-id $ASSOC_ID --region $REGION
  aws ec2 delete-subnet --subnet-id $SUBNET --region $REGION
done

aws ec2 delete-route-table \
  --route-table-id $RT_ID --region $REGION
aws ec2 detach-internet-gateway \
  --internet-gateway-id $IGW_ID --vpc-id $VPC_ID --region $REGION
aws ec2 delete-internet-gateway \
  --internet-gateway-id $IGW_ID --region $REGION
aws ec2 delete-vpc --vpc-id $VPC_ID --region $REGION

echo "VPC 网络资源已删除"
```

### 14.5 删除 IAM 角色和 OIDC Provider

``` bash
# EKSClusterRole-test
aws iam detach-role-policy --role-name EKSClusterRole-test \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
aws iam delete-role --role-name EKSClusterRole-test

# EKSNodeRole-test
aws iam detach-role-policy --role-name EKSNodeRole-test \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
aws iam detach-role-policy --role-name EKSNodeRole-test \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
aws iam detach-role-policy --role-name EKSNodeRole-test \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
aws iam delete-role --role-name EKSNodeRole-test

# EBSCSIDriverRole-test
aws iam detach-role-policy --role-name EBSCSIDriverRole-test \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy
aws iam delete-role --role-name EBSCSIDriverRole-test

# OIDC Provider
OIDC_ARN=$(aws iam list-open-id-connect-providers \
  --query "OpenIDConnectProviderList[].Arn" --output text \
  | tr '\t' '\n' | grep "$OIDC_URL")
[ -n "$OIDC_ARN" ] && \
  aws iam delete-open-id-connect-provider \
    --open-id-connect-provider-arn $OIDC_ARN

echo "IAM 角色和 OIDC Provider 已删除"
```

### 14.6 清理本地临时文件

``` bash
rm -f /tmp/eks-cluster-trust.json /tmp/eks-node-trust.json \
      /tmp/ebs-csi-trust.json /tmp/ebs-csi-trust-irsa.json \
      /tmp/storageclass.yaml /tmp/cassandra-cluster.yaml \
      /tmp/kafka-cluster.yaml /tmp/redis-cluster.yaml \
      /tmp/emqx-cluster.yaml /tmp/elasticsearch-cluster.yaml \
      ~/.eks-test-env

# 查看当前所有 context（确认要删除的名称）
kubectl config get-contexts

# 删除测试集群的 context（格式固定为 arn:aws:eks:region:accountid:cluster/clustername）
CONTEXT_NAME="arn:aws:eks:${REGION}:${ACCOUNT_ID}:cluster/${CLUSTER_NAME}"

kubectl config delete-context $CONTEXT_NAME

# 删除对应的 cluster 配置
kubectl config delete-cluster $CONTEXT_NAME

# 删除对应的 user 配置
kubectl config delete-user $CONTEXT_NAME

# 验证已清除
kubectl config get-contexts

echo "kubectl context 已清理"

echo "本地临时文件已清理，所有测试资源删除完毕"
```
