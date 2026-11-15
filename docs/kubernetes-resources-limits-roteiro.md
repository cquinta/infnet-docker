# Resources e Limits no Kubernetes

Roteiro prático sobre como configurar e validar requests e limits de CPU e memória em pods, incluindo a instalação do Metrics Server para observação em tempo real.

---

## Conceitos

| Conceito | O que define |
|----------|--------------|
| `requests` | Quantidade mínima de recurso garantida ao container — usada pelo scheduler para decidir em qual nó alocar o pod |
| `limits` | Quantidade máxima que o container pode consumir — o kernel intervém se o limite for ultrapassado |

### O que acontece quando o limite é ultrapassado

| Recurso | Comportamento ao ultrapassar o limit |
|---------|--------------------------------------|
| CPU | O container é throttled — continua rodando, mas com CPU limitada |
| Memória | O container é morto com `OOMKilled` (Out Of Memory) e reiniciado |

### Unidades

| Recurso | Unidades aceitas |
|---------|-----------------|
| CPU | `1` = 1 core, `500m` = 0.5 core, `100m` = 0.1 core |
| Memória | `128Mi`, `256Mi`, `1Gi` (base 2) ou `128M`, `1G` (base 10) |

---

## 1. Instalar o Metrics Server

O Metrics Server coleta métricas de CPU e memória dos nós e pods via API do kubelet, habilitando `kubectl top`.

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

### Ajuste necessário em ambientes sem TLS válido (EC2, kubeadm)

Por padrão o Metrics Server valida o certificado TLS do kubelet. Em clusters kubeadm sem certificados assinados por CA pública, é necessário desabilitar essa validação:

```bash
kubectl patch deployment metrics-server \
  -n kube-system \
  --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
```

Aguarde o pod ficar `Running`:

```bash
kubectl get pods -n kube-system -l k8s-app=metrics-server -w
```

Valide que a API está respondendo:

```bash
kubectl top nodes
```

Saída esperada:

```
NAME           CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%
k8s-master     120m         6%     900Mi           45%
k8s-worker-1   80m          4%     600Mi           30%
k8s-worker-2   75m          3%     580Mi           29%
```

---

## 2. Configurar requests e limits em um Pod

```yaml
# pod-resources.yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-resources
spec:
  containers:
  - name: app
    image: nginx:1.25
    resources:
      requests:
        cpu: "100m"
        memory: "128Mi"
      limits:
        cpu: "200m"
        memory: "256Mi"
```

```bash
kubectl apply -f pod-resources.yaml
kubectl top pod pod-resources
```

---

## 3. Simular pressão de CPU

Cria um pod que consome CPU continuamente para observar o throttling:

```yaml
# pod-cpu-stress.yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-cpu-stress
spec:
  containers:
  - name: stress
    image: polinux/stress
    resources:
      requests:
        cpu: "100m"
        memory: "64Mi"
      limits:
        cpu: "200m"
        memory: "128Mi"
    command: ["stress"]
    args: ["--cpu", "2", "--timeout", "120s"]
```

```bash
kubectl apply -f pod-cpu-stress.yaml

# Observar o consumo — o pod tentará usar 2 cores mas será limitado a 200m
kubectl top pod pod-cpu-stress
```

O pod continuará rodando, mas com CPU throttled. Verifique o throttling:

```bash
kubectl describe pod pod-cpu-stress | grep -A5 Limits
```

---

## 4. Simular OOMKilled (limite de memória)

Cria um pod que tenta alocar mais memória do que o limite permite:

```yaml
# pod-oom.yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-oom
spec:
  containers:
  - name: stress
    image: polinux/stress
    resources:
      requests:
        memory: "64Mi"
      limits:
        memory: "128Mi"
    command: ["stress"]
    args: ["--vm", "1", "--vm-bytes", "200M", "--timeout", "30s"]
```

```bash
kubectl apply -f pod-oom.yaml

# Acompanhar o OOMKill
kubectl get pod pod-oom -w
```

Saída esperada:

```
NAME      READY   STATUS      RESTARTS   AGE
pod-oom   0/1     OOMKilled   0          5s
pod-oom   0/1     OOMKilled   1          15s
```

Confirme a causa:

```bash
kubectl describe pod pod-oom | grep -A5 "Last State\|OOM"
```

```
Last State: Terminated
  Reason: OOMKilled
  Exit Code: 137
```

---

## 5. QoS Classes

O Kubernetes classifica os pods em três classes de qualidade de serviço com base nos resources definidos. Pods com classe inferior são os primeiros a ser removidos em situação de pressão de memória no nó.

| Classe | Condição | Prioridade de remoção |
|--------|----------|-----------------------|
| `Guaranteed` | `requests == limits` para CPU e memória | Última a ser removida |
| `Burstable` | `requests < limits` ou apenas um definido | Intermediária |
| `BestEffort` | Nenhum request ou limit definido | Primeira a ser removida |

### Exemplo Guaranteed

```yaml
# pod-guaranteed.yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-guaranteed
spec:
  containers:
  - name: app
    image: nginx:1.25
    resources:
      requests:
        cpu: "200m"
        memory: "256Mi"
      limits:
        cpu: "200m"
        memory: "256Mi"
```

Verifique a classe atribuída:

```bash
kubectl apply -f pod-guaranteed.yaml
kubectl get pod pod-guaranteed -o jsonpath='{.status.qosClass}'
# Guaranteed
```

---

## 6. LimitRange — definir padrões por namespace

O `LimitRange` aplica valores padrão de requests e limits automaticamente a pods que não os definem, e impõe limites mínimos e máximos no namespace.

```yaml
# limitrange.yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: limites-padrao
  namespace: default
spec:
  limits:
  - type: Container
    default:
      cpu: "200m"
      memory: "256Mi"
    defaultRequest:
      cpu: "100m"
      memory: "128Mi"
    max:
      cpu: "1"
      memory: "1Gi"
    min:
      cpu: "50m"
      memory: "64Mi"
```

```bash
kubectl apply -f limitrange.yaml
kubectl describe limitrange limites-padrao
```

Crie um pod sem resources e confirme que os padrões foram aplicados:

```bash
kubectl run pod-sem-resources --image=nginx:1.25
kubectl get pod pod-sem-resources -o jsonpath='{.spec.containers[0].resources}'
```

---

## 7. ResourceQuota — limitar consumo total do namespace

O `ResourceQuota` impõe um teto de consumo agregado para todos os pods de um namespace.

```yaml
# resourcequota.yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: quota-namespace
  namespace: default
spec:
  hard:
    requests.cpu: "2"
    requests.memory: "2Gi"
    limits.cpu: "4"
    limits.memory: "4Gi"
    pods: "10"
```

```bash
kubectl apply -f resourcequota.yaml

# Ver o consumo atual vs quota
kubectl describe resourcequota quota-namespace
```

```
Name:            quota-namespace
Namespace:       default
Resource         Used    Hard
--------         ----    ----
limits.cpu       400m    4
limits.memory    512Mi   4Gi
pods             2       10
requests.cpu     200m    2
requests.memory  256Mi   2Gi
```

---

## 8. HPA — Horizontal Pod Autoscaler

O HPA escala automaticamente o número de réplicas de um Deployment com base no consumo de CPU ou memória observado pelo Metrics Server.

### Como funciona

```
Metrics Server → HPA controller → ajusta replicas do Deployment
```

O HPA consulta o Metrics Server a cada 15 segundos (padrão) e calcula o número ideal de réplicas:

```
replicas desejadas = ceil(replicas atuais × (uso atual / meta))
```

### Deployment base para o teste

```yaml
# deployment-hpa.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-hpa
spec:
  replicas: 1
  selector:
    matchLabels:
      app: app-hpa
  template:
    metadata:
      labels:
        app: app-hpa
    spec:
      containers:
      - name: app
        image: nginx:1.25
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "200m"
            memory: "256Mi"
```

> O `requests.cpu` é obrigatório — o HPA calcula o percentual de uso em relação ao request, não ao limit.

```bash
kubectl apply -f deployment-hpa.yaml
```

### Criar o HPA

**Opção A — via manifesto (recomendado):**

```yaml
# hpa.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: hpa-app
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: app-hpa
  minReplicas: 1
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 50
```

```bash
kubectl apply -f hpa.yaml
```

**Opção B — via kubectl:**

```bash
kubectl autoscale deployment app-hpa \
  --cpu-percent=50 \
  --min=1 \
  --max=5
```

### Verificar o estado do HPA

```bash
kubectl get hpa hpa-app
```

```
NAME      REFERENCE            TARGETS   MINPODS   MAXPODS   REPLICAS   AGE
hpa-app   Deployment/app-hpa   2%/50%    1         5         1          30s
```

> Se `TARGETS` mostrar `<unknown>/50%`, aguarde alguns segundos — o Metrics Server ainda está coletando as primeiras métricas.

### Simular carga para acionar o scale up

Em outro terminal, gere carga contínua no deployment:

```bash
# Cria um pod temporário que faz requisições em loop
kubectl run load-generator \
  --image=busybox:1.36 \
  --restart=Never \
  -- sh -c "while true; do wget -q -O- http://app-hpa; done"
```

Acompanhe o HPA escalando:

```bash
kubectl get hpa hpa-app -w
```

```
NAME      REFERENCE            TARGETS    MINPODS   MAXPODS   REPLICAS
hpa-app   Deployment/app-hpa   2%/50%     1         5         1
hpa-app   Deployment/app-hpa   85%/50%    1         5         1
hpa-app   Deployment/app-hpa   85%/50%    1         5         2
hpa-app   Deployment/app-hpa   72%/50%    1         5         3
hpa-app   Deployment/app-hpa   48%/50%    1         5         3
```

### Remover a carga e observar o scale down

```bash
kubectl delete pod load-generator
```

O HPA aguarda 5 minutos (padrão) antes de reduzir réplicas para evitar flapping:

```bash
kubectl get hpa hpa-app -w
# Após ~5 minutos REPLICAS voltará para 1
```

### Inspecionar decisões do HPA

```bash
kubectl describe hpa hpa-app
```

A seção `Events` mostra cada decisão de scale:

```
Events:
  Type    Reason             Message
  ----    ------             -------
  Normal  SuccessfulRescale  New size: 3; reason: cpu resource utilization (percentage of request) above target
  Normal  SuccessfulRescale  New size: 1; reason: All metrics below target
```

### HPA com múltiplas métricas (CPU + memória)

```yaml
# hpa-multi.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: hpa-multi
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: app-hpa
  minReplicas: 1
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 50
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 70
```

> Com múltiplas métricas, o HPA calcula o número de réplicas para cada métrica separadamente e usa o **maior** valor.

---

## 9. Comandos úteis de observação

```bash
# Consumo atual de todos os pods
kubectl top pods -A

# Consumo por nó
kubectl top nodes

# Ver resources definidos em todos os pods de um namespace
kubectl get pods -o custom-columns=\
"NAME:.metadata.name,\
CPU_REQ:.spec.containers[0].resources.requests.cpu,\
MEM_REQ:.spec.containers[0].resources.requests.memory,\
CPU_LIM:.spec.containers[0].resources.limits.cpu,\
MEM_LIM:.spec.containers[0].resources.limits.memory"

# Ver eventos de OOMKill ou throttling
kubectl get events --field-selector reason=OOMKilling
```

---

## Limpeza

```bash
kubectl delete pod pod-resources pod-cpu-stress pod-oom pod-guaranteed pod-sem-resources
kubectl delete deployment app-hpa
kubectl delete hpa hpa-app hpa-multi
kubectl delete limitrange limites-padrao
kubectl delete resourcequota quota-namespace
```

---

## Resumo

| Objeto | Escopo | Para que serve |
|--------|--------|----------------|
| `resources.requests` | Container | Garante recursos mínimos e guia o scheduler |
| `resources.limits` | Container | Impõe teto de consumo |
| `LimitRange` | Namespace | Define padrões e limites por container |
| `ResourceQuota` | Namespace | Define teto de consumo agregado |
| `Metrics Server` | Cluster | Habilita `kubectl top` para observação em tempo real |
| `HPA` | Namespace | Escala réplicas automaticamente com base em métricas de CPU/memória |
