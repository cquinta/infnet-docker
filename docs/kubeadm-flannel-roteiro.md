# Bootstrap de Cluster Kubernetes com kubeadm na AWS (EC2 Ubuntu) — CNI: Flannel

Roteiro para provisionar um cluster Kubernetes com **1 nó master** e **2 workers** em instâncias EC2 Ubuntu via `kubeadm`, usando **Flannel** como plugin de rede.

> Prefira este roteiro ao invés do roteiro com Cilium quando quiser uma configuração de rede mais simples e sem risco de conflito de rotas na VPC da AWS.

---

## Topologia

| Papel    | Nome sugerido    | Observação                          |
|----------|------------------|-------------------------------------|
| Master   | `k8s-master`     | Control plane, executa kubeadm init |
| Worker 1 | `k8s-worker-1`   | Executa workloads                   |
| Worker 2 | `k8s-worker-2`   | Executa workloads                   |

---

## 1. Pré-requisitos na AWS

### 1.1. Instâncias EC2

Suba **3 instâncias** com as seguintes configurações:

| Parâmetro      | Valor recomendado                   |
|----------------|-------------------------------------|
| AMI            | Ubuntu Server 22.04 LTS             |
| Tipo           | `t3.medium` (mínimo 2 vCPU / 2 GB) |
| Armazenamento  | 20 GB gp3                           |
| Key pair       | Sua chave `.pem`                    |
| Security Group | `k8s-sg` (ver seção 1.2)            |

> O kubeadm exige no mínimo 2 CPUs e 2 GB de RAM no nó master.

### 1.2. Security Group (`k8s-sg`)

Crie um security group com as seguintes regras de entrada (inbound):

**Acesso externo (0.0.0.0/0):**

| Porta | Protocolo | Uso |
|-------|-----------|-----|
| 22    | TCP       | SSH |

**Entre os nós do cluster (source: próprio security group):**

| Porta(s)    | Protocolo | Componente                       |
|-------------|-----------|----------------------------------|
| 6443        | TCP       | API Server (master)              |
| 2379-2380   | TCP       | etcd (master)                    |
| 10250       | TCP       | Kubelet (todos os nós)           |
| 10257       | TCP       | kube-controller-manager (master) |
| 10259       | TCP       | kube-scheduler (master)          |
| 30000-32767 | TCP       | NodePort Services (workers)      |
| 8472        | UDP       | Flannel VXLAN overlay            |

Via AWS CLI:

```bash
SG_ID=$(aws ec2 create-security-group \
  --group-name k8s-sg \
  --description "Security group para cluster Kubernetes" \
  --vpc-id $VPC_ID \
  --query 'GroupId' --output text)

# SSH externo
aws ec2 authorize-security-group-ingress --group-id $SG_ID \
  --protocol tcp --port 22 --cidr 0.0.0.0/0

# Portas internas do cluster
for port in 6443 10250 10257 10259; do
  aws ec2 authorize-security-group-ingress --group-id $SG_ID \
    --protocol tcp --port $port --source-group $SG_ID
done

aws ec2 authorize-security-group-ingress --group-id $SG_ID \
  --protocol tcp --port 2379-2380 --source-group $SG_ID

aws ec2 authorize-security-group-ingress --group-id $SG_ID \
  --protocol tcp --port 30000-32767 --source-group $SG_ID

# Flannel VXLAN
aws ec2 authorize-security-group-ingress --group-id $SG_ID \
  --protocol udp --port 8472 --source-group $SG_ID
```

---

## 2. Preparação de todos os nós (master e workers)

> Execute os passos desta seção em **todas as 3 instâncias**.

```bash
ssh -i sua-chave.pem ubuntu@<IP_PUBLICO>
```

### 2.1. Desabilitar swap

```bash
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab
```

### 2.2. Carregar módulos do kernel

```bash
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter
```

### 2.3. Configurar parâmetros de rede do kernel

```bash
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system
```

### 2.4. Instalar o containerd

```bash
sudo apt-get update
sudo apt-get install -y containerd

sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml

sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

sudo systemctl restart containerd
sudo systemctl enable containerd
```

### 2.5. Instalar kubeadm, kubelet e kubectl

```bash
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

sudo systemctl enable kubelet
```

---

## 3. Inicializar o cluster (somente no master)

```bash
sudo kubeadm init \
  --pod-network-cidr=10.244.0.0/16 \
  --apiserver-advertise-address=<IP_PRIVADO_MASTER>
```

> `10.244.0.0/16` é o CIDR padrão do Flannel. Ele **não conflita** com a subnet típica de VPCs na AWS (`10.0.0.0/24`) pois o Flannel não injeta rotas na tabela do host — usa encapsulamento VXLAN transparente.

Ao final, copie e guarde o comando de join exibido na saída:

```
kubeadm join <IP_PRIVADO_MASTER>:6443 --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH>
```

### 3.1. Configurar o kubectl

```bash
mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

### 3.2. Instalar o Flannel

```bash
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
```

Aguarde os pods ficarem `Running`:

```bash
kubectl get pods -n kube-flannel --watch
```

Saída esperada:

```
NAME                    READY   STATUS    RESTARTS   AGE
kube-flannel-ds-xxxxx   1/1     Running   0          30s
```

---

## 4. Adicionar os workers ao cluster

Execute em **cada worker**:

```bash
sudo kubeadm join <IP_PRIVADO_MASTER>:6443 --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH>
```

Cada worker deve responder com: `This node has joined the cluster`.

> Se o token expirar (validade de 24h), gere um novo no master:
> ```bash
> kubeadm token create --print-join-command
> ```

Acompanhe o Flannel subindo automaticamente nos novos nós:

```bash
kubectl get pods -n kube-flannel -o wide --watch
```

---

## 5. Verificar o cluster (no master)

```bash
kubectl get nodes -o wide
```

Saída esperada:

```
NAME           STATUS   ROLES           AGE   VERSION
k8s-master     Ready    control-plane   5m    v1.30.x
k8s-worker-1   Ready    <none>          2m    v1.30.x
k8s-worker-2   Ready    <none>          2m    v1.30.x
```

---

## 6. Validar o cluster com um deployment de teste

```bash
kubectl create deployment nginx --image=nginx --replicas=3
kubectl expose deployment nginx --type=NodePort --port=80
kubectl get pods -o wide
kubectl get svc nginx
```

Acesse `http://<IP_PUBLICO_QUALQUER_NO>:<NODEPORT>` no navegador para confirmar.

```bash
kubectl delete deployment nginx
kubectl delete svc nginx
```

---

## 7. Comandos úteis de manutenção

```bash
# Listar nós com detalhes
kubectl get nodes -o wide

# Descrever um nó
kubectl describe node <NOME_DO_NO>

# Ver todos os pods do sistema
kubectl get pods -n kube-system
kubectl get pods -n kube-flannel

# Drenar um nó antes de manutenção
kubectl drain <NOME_DO_NO> --ignore-daemonsets --delete-emptydir-data

# Reabilitar o nó após manutenção
kubectl uncordon <NOME_DO_NO>

# Remover um nó do cluster (rode no master)
kubectl delete node <NOME_DO_NO>

# Resetar um nó (rode no próprio nó)
sudo kubeadm reset
```

---

## Resumo do fluxo

1. Criar o security group `k8s-sg` com as portas do Kubernetes + `8472/UDP` para o Flannel.
2. Subir 3 instâncias EC2 Ubuntu `t3.medium` associadas ao `k8s-sg`.
3. Em **todos os nós**: desabilitar swap, configurar kernel, instalar containerd + kubeadm/kubelet/kubectl.
4. No **master**: `kubeadm init --pod-network-cidr=10.244.0.0/16`, configurar kubectl, instalar Flannel.
5. Nos **workers**: `kubeadm join` com o token gerado pelo master.
6. Validar com `kubectl get nodes` e um deployment de teste.
