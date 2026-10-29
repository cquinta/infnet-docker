# Subindo um cluster Docker Swarm com 3 nós na AWS

Este roteiro descreve como subir um cluster Docker Swarm com 3 nós (1 líder/manager e 2 workers) usando instâncias EC2 Ubuntu que **já possuem o Docker Engine instalado**.

## Visão geral da topologia

| Papel   | Nome sugerido | Função                                          |
|---------|---------------|-------------------------------------------------|
| Manager | `swarm-manager` | Nó líder, inicializa o cluster e orquestra     |
| Worker  | `swarm-worker-1` | Executa as tarefas (containers)                |
| Worker  | `swarm-worker-2` | Executa as tarefas (containers)                |

---

## 1. Portas necessárias

O Docker Swarm precisa das seguintes portas liberadas **entre os nós** do cluster:

| Porta      | Protocolo | Uso                                                          |
|------------|-----------|--------------------------------------------------------------|
| 2377       | TCP       | Comunicação de gerenciamento do cluster (manager)            |
| 7946       | TCP e UDP | Comunicação entre nós / descoberta de serviços              |
| 4789       | UDP       | Tráfego de rede overlay (VXLAN)                              |

Além disso, o enunciado pede liberar para **toda a internet** (`0.0.0.0/0`) as portas:

| Porta | Protocolo | Uso                          |
|-------|-----------|------------------------------|
| 22    | TCP       | SSH                          |
| 80    | TCP       | HTTP                         |
| 443   | TCP       | HTTPS                        |
| 8080  | TCP       | Aplicação / painel           |

---

## 2. Criar o Security Group

Você pode criar o security group pelo console da AWS ou via AWS CLI. Abaixo, o passo a passo com a CLI.

> Substitua `vpc-xxxxxxxx` pelo ID da sua VPC e `us-east-1` pela sua região.

### 2.1. Criar o security group

```bash
SG_ID=$(aws ec2 create-security-group \
  --group-name swarm-sg \
  --description "Security group para cluster Docker Swarm" \
  --vpc-id $VPC_ID \
  --query 'GroupId' \
  --output text)

echo "Security Group criado: $SG_ID"
```

### 2.2. Liberar portas para toda a internet (0.0.0.0/0)

```bash
# SSH
aws ec2 authorize-security-group-ingress --group-id $SG_ID \
  --protocol tcp --port 22 --cidr 0.0.0.0/0

# HTTP
aws ec2 authorize-security-group-ingress --group-id $SG_ID \
  --protocol tcp --port 80 --cidr 0.0.0.0/0

# HTTPS
aws ec2 authorize-security-group-ingress --group-id $SG_ID \
  --protocol tcp --port 443 --cidr 0.0.0.0/0

# Aplicação (8080)
aws ec2 authorize-security-group-ingress --group-id $SG_ID \
  --protocol tcp --port 8080 --cidr 0.0.0.0/0
```

### 2.3. Liberar as portas do Swarm somente entre os nós (mesmo security group)

Usar o próprio security group como origem (`--source-group`) garante que só as instâncias que pertencem a ele conversem entre si nessas portas, sem expô-las à internet.

```bash
# 2377/TCP - gerenciamento do cluster
aws ec2 authorize-security-group-ingress --group-id $SG_ID \
  --protocol tcp --port 2377 --source-group $SG_ID

# 7946/TCP - comunicação entre nós
aws ec2 authorize-security-group-ingress --group-id $SG_ID \
  --protocol tcp --port 7946 --source-group $SG_ID

# 7946/UDP - comunicação entre nós
aws ec2 authorize-security-group-ingress --group-id $SG_ID \
  --protocol udp --port 7946 --source-group $SG_ID

# 4789/UDP - rede overlay (VXLAN)
aws ec2 authorize-security-group-ingress --group-id $SG_ID \
  --protocol udp --port 4789 --source-group $SG_ID
```

> Se preferir fazer pelo console: em **EC2 > Security Groups > Create security group**, adicione as regras de entrada (Inbound rules) conforme as tabelas da seção 1. Para as regras do Swarm, escolha como *Source* o próprio security group.

---

## 3. Provisionar as 3 instâncias EC2

Suba 3 instâncias Ubuntu (com Docker já instalado), todas associadas ao security group `swarm-sg` criado acima e com a mesma key pair para acesso SSH.

Sugestão de configuração:
- AMI: Ubuntu Server (LTS)
- Tipo: `t3.small` ou superior
- Security group: `swarm-sg`
- Key pair: a sua chave `.pem`

Anote os IPs de cada instância:

| Nó              | IP público (SSH) | IP privado (comunicação do cluster) |
|-----------------|------------------|-------------------------------------|
| `swarm-manager` | `<IP_PUB_MANAGER>` | `10-0-0-194`               |
| `swarm-worker-1`| `<IP_PUB_WORKER1>` | `<IP_PRIV_WORKER1>`               |
| `swarm-worker-2`| `<IP_PUB_WORKER2>` | `<IP_PRIV_WORKER2>`               |

> Use sempre o **IP privado** do manager na inicialização do Swarm, pois os nós conversam pela rede interna da VPC.

---

## 4. Verificar o Docker em cada nó

Acesse cada instância via SSH e confirme que o Docker está funcionando:

```bash
ssh -i sua-chave.pem ubuntu@<IP_PUBLICO>

docker --version
docker info
```

Se o comando exigir `sudo`, adicione seu usuário ao grupo docker (opcional):

```bash
sudo usermod -aG docker ubuntu
# faça logout/login para aplicar
```

---

## 5. Inicializar o Swarm no nó manager

Conecte no nó **manager** e inicialize o cluster usando o **IP privado** dele:

```bash
ssh -i sua-chave.pem ubuntu@<IP_PUB_MANAGER>

docker swarm init --advertise-addr <IP_PRIV_MANAGER>
```

A saída trará o comando de join com o token de worker, algo como:

```
docker swarm join --token SWMTKN-1-xxxxxxxxxxxxxxxxxxxx-yyyyyyyyyyyy <IP_PRIV_MANAGER>:2377
```

Copie esse comando. Caso precise recuperá-lo depois, rode no manager:

```bash
docker swarm join-token worker
```

---

## 6. Adicionar os workers ao cluster

Conecte em **cada worker** e execute o comando de join copiado do manager:

```bash
# No swarm-worker-1
ssh -i sua-chave.pem ubuntu@<IP_PUB_WORKER1>
docker swarm join --token SWMTKN-1-xxxxxxxxxxxxxxxxxxxx-yyyyyyyyyyyy <IP_PRIV_MANAGER>:2377
```

```bash
# No swarm-worker-2
ssh -i sua-chave.pem ubuntu@<IP_PUB_WORKER2>
docker swarm join --token SWMTKN-1-xxxxxxxxxxxxxxxxxxxx-yyyyyyyyyyyy <IP_PRIV_MANAGER>:2377
```

Cada worker deve responder com: `This node joined a swarm as a worker.`

---

## 7. Verificar o cluster

De volta ao **manager**, liste os nós:

```bash
docker node ls
```

Saída esperada (3 nós, o manager como `Leader`):

```
ID          HOSTNAME         STATUS    AVAILABILITY   MANAGER STATUS
abc123 *    swarm-manager    Ready     Active         Leader
def456      swarm-worker-1   Ready     Active
ghi789      swarm-worker-2   Ready     Active
```

---

## 8. Testar com um serviço

Ainda no manager, suba um serviço de teste e verifique a distribuição:

```bash
# Cria um serviço nginx com 3 réplicas publicando na porta 80
docker service create --name web --replicas 3 -p 80:80 nginx

# Acompanha as réplicas e em quais nós rodam
docker service ps web

# Lista os serviços
docker service ls
```

Acesse `http://<IP_PUB_MANAGER>` (ou de qualquer nó) no navegador para ver a página do nginx. Graças ao *routing mesh* do Swarm, a porta publicada responde a partir de qualquer nó do cluster.

Para remover o serviço de teste:

```bash
docker service rm web
```

---

## 9. Testar o load balancer do Swarm

O Swarm distribui as requisições entre as réplicas de um serviço através do *routing mesh* + *ingress load balancer*. Para **enxergar** esse balanceamento, o ideal é usar um serviço cuja resposta identifique qual réplica atendeu. A imagem `webapp` deste repositório (`examples/webapp`) faz exatamente isso: ela exibe o **hostname do container** na página, e no Swarm o hostname do container corresponde ao ID da tarefa/réplica.

### 9.1. Publicar a imagem para o cluster

Os nós do Swarm precisam ter acesso à imagem. Escolha uma das opções:

**Opção A — via registry (recomendado):** faça push da imagem para um registry acessível (Docker Hub, ECR etc.).

```bash
# Na sua máquina (ou no manager), a partir de examples/webapp
docker build -t <seu-usuario>/webapp:1.0 .
docker push <seu-usuario>/webapp:1.0
```

**Opção B — sem registry:** faça o build da imagem em **cada nó** (manager e workers), copiando o diretório `examples/webapp` para todos eles e rodando `docker build -t webapp:1.0 .` em cada um.

### 9.2. Criar o serviço com múltiplas réplicas

No **manager**, crie o serviço com mais réplicas que nós (para garantir várias réplicas por nó) publicando na porta 8080:

```bash
# Use a tag do registry (Opção A) ou webapp:1.0 (Opção B)
docker service create \
  --name webapp \
  --replicas 6 \
  -p 8080:80 \
  <seu-usuario>/webapp:1.0

# Confira em quais nós as réplicas foram distribuídas
docker service ps webapp
```

### 9.3. Gerar requisições e observar o balanceamento

Faça várias requisições seguidas ao endpoint publicado. Como o *ingress load balancer* usa round-robin, o hostname retornado deve **alternar** entre as réplicas:

```bash
# A partir de qualquer nó ou da sua máquina.
# Extrai apenas a linha com o hostname da página.
for i in $(seq 1 12); do
  curl -s http://<IP_PUB_MANAGER>:8080 | grep -o '<div class="hostname">[^<]*' | sed 's/.*>//'
done
```

Saída esperada — os hostnames se repetem alternando entre as réplicas, evidenciando o balanceamento:

```
a1b2c3d4e5f6
b2c3d4e5f6a1
c3d4e5f6a1b2
a1b2c3d4e5f6
b2c3d4e5f6a1
...
```

> Você pode apontar o `curl` para **qualquer** IP do cluster (manager ou worker) na porta 8080 e ainda assim as requisições serão distribuídas entre todas as réplicas. Isso comprova o *routing mesh*: qualquer nó recebe na porta publicada e encaminha para uma réplica disponível.

Se estiver testando pelo navegador, dê vários *refresh* (use Ctrl+F5 para evitar cache) e observe o hostname mudando.

### 9.4. (Opcional) Escalar e observar a mudança

```bash
# Aumenta para 9 réplicas e repita o teste de requisições
docker service scale webapp=9
docker service ps webapp
```

### 9.5. Remover o serviço de teste

```bash
docker service rm webapp
```

---

## 10. Comandos úteis de manutenção

```bash
# Ver detalhes de um nó
docker node inspect <ID_OU_HOSTNAME> --pretty

# Remover um worker do cluster (rode no próprio worker)
docker swarm leave

# Remover um nó já desligado (rode no manager)
docker node rm <ID_OU_HOSTNAME>

# Fazer um worker deixar o swarm forçadamente
docker swarm leave --force

# Recuperar token de manager (para adicionar outro manager)
docker swarm join-token manager
```

---

## Resumo do fluxo

1. Criar o security group com as portas do Swarm (entre nós) + 22/80/443/8080 (internet).
2. Subir 3 instâncias Ubuntu com Docker, associadas ao security group.
3. `docker swarm init` no manager (usando IP privado).
4. `docker swarm join` nos 2 workers.
5. `docker node ls` para confirmar os 3 nós.
6. `docker service create` para validar o cluster.
7. Subir o serviço `webapp` com várias réplicas e usar `curl` em loop para ver o load balancer alternando os hostnames.
