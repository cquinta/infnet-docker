# Bootstrap de Cluster Kubernetes com kubeadm na AWS (EC2 Ubuntu)

Roteiro para provisionar um cluster Kubernetes com **1 nó master** e **2 workers** em instâncias EC2 Ubuntu via `kubeadm`.

---

## Topologia

| Papel    | Nome sugerido   | Observação                        |
|----------|-----------------|-----------------------------------|
| Master   | `k8s-master`    | Control plane, executa kubeadm init |
| Worker 1 | `k8s-worker-1`  | Executa workloads                 |
| Worker 2 | `k8s-worker-2`  | Executa workloads                 |

---

## 1. Pré-requisitos na AWS

### 1.1. Instâncias EC2

Suba **3 instâncias** com as seguintes configurações:

| Parâmetro       | Valor recomendado                  |
|-----------------|------------------------------------|
| AMI             | Ubuntu Server 22.04 LTS            |
| Tipo            | `t3.medium` (mínimo 2 vCPU / 2 GB) |
| Armazenamento   | 20 GB gp3                          |
| Key pair        | Sua chave `.pem`                   |
| Security Group  | `k8s-sg` (ver seção 1.2)           |

> O kubeadm exige no mínimo 2 CPUs e 2 GB de RAM no nó master.

### 1.2. Security Group (`k8s-sg`)

Crie um security group com as seguintes regras de entrada (inbound):

**Acesso externo (0.0.0.0/0):**

| Porta | Protocolo | Uso          |
|-------|-----------|--------------|
| 22    | TCP       | SSH          |

**Entre os nós do cluster (source: próprio security group):**

| Porta(s)    | Protocolo | Componente                          |
|-------------|-----------|-------------------------------------|
| 6443        | TCP       | API Server (master)                 |
| 2379-2380   | TCP       | etcd (master)                       |
| 10250       | TCP       | Kubelet (todos os nós)              |
| 10257       | TCP       | kube-controller-manager (master)    |
| 10259       | TCP       | kube-scheduler (master)             |
| 30000-32767 | TCP       | NodePort Services (workers)         |
| 8472        | UDP       | Cilium VXLAN overlay                |
| 4240        | TCP       | Cilium health checks                |
| 4244        | TCP       | Hubble server (observabilidade)     |

Via AWS CLI:

```bash
# Cria o security group
SG_ID=$(aws ec2 create-security-group \
  --group-name k8s-sg \
  --description "Security group para cluster Kubernetes" \
  --vpc-id $VPC_ID \
  --query 'GroupId' --output text)

# SSH externo
aws ec2 authorize-security-group-ingress --group-id $SG_ID \
  --protocol tcp --port 22 --cidr 0.0.0.0/0

# Portas internas do cluster (entre os nós)
for port in 6443 10250 10257 10259; do
  aws ec2 authorize-security-group-ingress --group-id $SG_ID \
    --protocol tcp --port $port --source-group $SG_ID
done

aws ec2 authorize-security-group-ingress --group-id $SG_ID \
  --protocol tcp --port 2379-2380 --source-group $SG_ID

aws ec2 authorize-security-group-ingress --group-id $SG_ID \
  --protocol tcp --port 30000-32767 --source-group $SG_ID

aws ec2 authorize-security-group-ingress --group-id $SG_ID \
  --protocol udp --port 8472 --source-group $SG_ID

# 4240/TCP - Cilium health checks
aws ec2 authorize-security-group-ingress --group-id $SG_ID \
  --protocol tcp --port 4240 --source-group $SG_ID

# 4244/TCP - Hubble
aws ec2 authorize-security-group-ingress --group-id $SG_ID \
  --protocol tcp --port 4244 --source-group $SG_ID
```

---

## 2. Preparação de todos os nós (master e workers)

> Execute os passos desta seção em **todas as 3 instâncias**.

Acesse cada instância via SSH:

```bash
ssh -i sua-chave.pem ubuntu@<IP_PUBLICO>
```

### 2.1. Desabilitar swap

O kubelet não funciona com swap ativo:

```bash
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab
```

### 2.2. Carregar módulos do kernel necessários

| Módulo | Para que serve |
|--------|----------------|
| `overlay` | Sistema de arquivos em camadas usado pelo containerd para montar o filesystem dos containers de forma eficiente, sem duplicar dados entre imagens. |
| `br_netfilter` | Permite que o netfilter (iptables/nftables) inspecione e filtre pacotes que trafegam por bridges de rede virtual — necessário para que as regras de rede do Kubernetes funcionem no tráfego entre pods. |

```bash
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter
```

### 2.3. Configurar parâmetros de rede do kernel

| Parâmetro | Para que serve |
|-----------|----------------|
| `net.bridge.bridge-nf-call-iptables` | Garante que o tráfego IPv4 que passa por bridges virtuais seja processado pelo iptables, permitindo que o kube-proxy aplique as regras de roteamento de serviços. |
| `net.bridge.bridge-nf-call-ip6tables` | Mesmo comportamento do parâmetro acima, para tráfego IPv6. |
| `net.ipv4.ip_forward` | Habilita o encaminhamento de pacotes IP entre interfaces de rede, essencial para que o nó roteie tráfego entre pods, serviços e a rede externa. |

```bash
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system
```

### 2.4. Instalar o containerd (container runtime)

O `containerd` é o runtime de containers usado pelo Kubernetes para criar, executar e gerenciar os containers nos nós. Ele implementa a interface CRI (Container Runtime Interface) exigida pelo kubelet.

| Configuração | Para que serve |
|--------------|----------------|
| `containerd config default` | Gera o arquivo de configuração padrão com todos os parâmetros disponíveis. |
| `SystemdCgroup = true` | Faz o containerd delegar o gerenciamento de cgroups ao systemd, alinhando com o que o kubelet espera. Sem isso, o kubelet e o containerd usam drivers de cgroup diferentes e o nó fica instável. |

```bash
sudo apt-get update
sudo apt-get install -y containerd

sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml

# Habilita o SystemdCgroup (obrigatório para kubeadm)
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

sudo systemctl restart containerd
sudo systemctl enable containerd
```

### 2.5. Instalar kubeadm, kubelet e kubectl

| Pacote | Para que serve |
|--------|----------------|
| `apt-transport-https` | Permite que o apt baixe pacotes via HTTPS, necessário para acessar o repositório oficial do Kubernetes. |
| `ca-certificates` | Instala certificados de autoridades certificadoras confiáveis, usados para validar conexões TLS com o repositório. |
| `curl` | Ferramenta de transferência de dados usada para baixar a chave GPG do repositório do Kubernetes. |
| `gpg` | Verifica a assinatura criptográfica dos pacotes, garantindo que vieram de uma fonte confiável. |
| `kubelet` | Agente que roda em todos os nós, responsável por garantir que os containers descritos nos Pods estejam em execução e saudáveis. |
| `kubeadm` | Ferramenta que automatiza o bootstrap do cluster: inicializa o control plane no master e gera os tokens de join para os workers. |
| `kubectl` | CLI para interagir com o cluster Kubernetes — criar, inspecionar e gerenciar recursos como pods, deployments e serviços. |
| `apt-mark hold` | Congela as versões instaladas dos três pacotes acima, evitando que uma atualização automática do sistema quebre a compatibilidade entre os componentes do cluster. |

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

Conecte no nó **master** e execute:

```bash
sudo kubeadm init \
  --pod-network-cidr=10.244.0.0/16 \
  --skip-phases=addon/kube-proxy \
  --apiserver-advertise-address=<IP_PRIVADO_MASTER>
```

> O `--skip-phases=addon/kube-proxy` é obrigatório porque o Cilium será instalado com `kubeProxyReplacement=true`, assumindo todas as funções do kube-proxy via eBPF. Instalar os dois em paralelo causa conflito de regras de roteamento. O CIDR `10.244.0.0/16` é o padrão do Flannel/Cilium com IPAM `kubernetes` — o Cilium respeitará esse range e não alocará pods em `10.0.0.0/8`, evitando colisão com a subnet da VPC.

Ao final, a saída exibirá o comando de join. **Copie e guarde** — ele será usado nos workers:

```
kubeadm join <IP_PRIVADO_MASTER>:6443 --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH>
```

### 3.1. Configurar o kubectl para o usuário ubuntu

```bash
mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

### 3.2. Instalar o plugin de rede (CNI) — Cilium

#### Instalar a CLI do Cilium

```bash
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
curl -L --fail --remote-name-all \
  https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-amd64.tar.gz
sudo tar xzvf cilium-linux-amd64.tar.gz -C /usr/local/bin
rm cilium-linux-amd64.tar.gz
```

#### Instalar o Cilium no cluster

```bash
cilium install \
  --set ipam.mode=kubernetes \
  --set routingMode=tunnel \
  --set tunnelProtocol=vxlan \
  --set autoDirectNodeRoutes=false \
  --set kubeProxyReplacement=true
```

> O `ipam.mode=kubernetes` faz o Cilium usar o podCIDR atribuído pelo kubeadm a cada nó (`10.244.x.x/24`) em vez de alocar do próprio pool interno (`10.0.0.0/8` por padrão). Sem esse parâmetro, o Cilium ignora o podCIDR do Kubernetes, aloca prefixos em `10.0.0.x`, colide com a subnet da VPC e injeta rotas via `cilium_host` que derrubam a conectividade entre os nós. O `kubeProxyReplacement=true` é obrigatório porque o cluster foi inicializado sem kube-proxy (`--skip-phases=addon/kube-proxy`).

#### Verificar o status da instalação

```bash
cilium status --wait
```

Aguarde até que todos os componentes apareçam como `OK`:

```
    /¯¯\
 /¯¯\__/¯¯\    Cilium:             OK
 \__/¯¯\__/    Operator:           OK
 /¯¯\__/¯¯\    Envoy DaemonSet:    disabled
 \__/¯¯\__/    Hubble Relay:       disabled
    \__/        ClusterMesh:        disabled
```

Confirme que os pods do Cilium estão `Running`:

```bash
kubectl get pods -n kube-system -l k8s-app=cilium
```

#### (Opcional) Executar o teste de conectividade do Cilium

```bash
cilium connectivity test
```

> O teste cria um namespace temporário `cilium-test`, executa uma bateria de verificações de rede e remove tudo ao final. Pode levar alguns minutos.

---

## 4. Adicionar os workers ao cluster

Conecte em **cada worker** e execute o comando de join copiado na etapa 3:

```bash
sudo kubeadm join <IP_PRIVADO_MASTER>:6443 --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH>
```

Cada worker deve responder com: `This node has joined the cluster`.

> Se o token expirar (validade de 24h), gere um novo no master:
> ```bash
> kubeadm token create --print-join-command
> ```

---

## 5. Verificar o cluster (no master)

```bash
kubectl get nodes -o wide
```

Saída esperada (todos os nós com status `Ready`):

```
NAME           STATUS   ROLES           AGE   VERSION
k8s-master     Ready    control-plane   5m    v1.30.x
k8s-worker-1   Ready    <none>          2m    v1.30.x
k8s-worker-2   Ready    <none>          2m    v1.30.x
```

---

## 6. Validar o cluster com um deployment de teste

```bash
# Cria um deployment nginx com 3 réplicas
kubectl create deployment nginx --image=nginx --replicas=3

# Expõe via NodePort
kubectl expose deployment nginx --type=NodePort --port=80

# Verifica a distribuição dos pods nos nós
kubectl get pods -o wide

# Obtém a porta NodePort atribuída
kubectl get svc nginx
```

Acesse `http://<IP_PUBLICO_QUALQUER_NO>:<NODEPORT>` no navegador para confirmar.

Remova o deployment de teste:

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

1. Criar o security group `k8s-sg` com as portas do Kubernetes.
2. Subir 3 instâncias EC2 Ubuntu `t3.medium` associadas ao `k8s-sg`.
3. Em **todos os nós**: desabilitar swap, configurar kernel, instalar containerd + kubeadm/kubelet/kubectl.
4. No **master**: `kubeadm init`, configurar kubectl, instalar CNI (Cilium via CLI).
5. Nos **workers**: `kubeadm join` com o token gerado pelo master.
6. Validar com `kubectl get nodes` e um deployment de teste.
