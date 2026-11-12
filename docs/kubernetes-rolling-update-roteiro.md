# Rolling Update no Kubernetes

Roteiro prático sobre como atualizar aplicações em produção sem downtime usando a estratégia de rolling update.

---

## O que é Rolling Update?

Rolling update é a estratégia padrão de atualização de Deployments no Kubernetes. Em vez de derrubar todos os pods de uma vez, ela substitui os pods gradualmente — garantindo que sempre haja pods disponíveis para receber tráfego durante a atualização.

---

## Estratégias de atualização disponíveis

| Estratégia | Comportamento |
|------------|---------------|
| `RollingUpdate` | Substitui pods gradualmente — padrão, sem downtime |
| `Recreate` | Derruba todos os pods antes de criar os novos — causa downtime |

---

## Parâmetros do RollingUpdate

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 1   # Máximo de pods indisponíveis durante a atualização (absoluto ou %)
    maxSurge: 1         # Máximo de pods extras criados acima do replicas desejado (absoluto ou %)
```

| Parâmetro | O que controla |
|-----------|----------------|
| `maxUnavailable` | Quantos pods podem ficar indisponíveis simultaneamente. `0` garante que a capacidade nunca caia abaixo do desejado. |
| `maxSurge` | Quantos pods extras podem ser criados acima do número de réplicas. `0` garante que nunca haja pods além do desejado. |

> Com `maxUnavailable: 0` e `maxSurge: 1`, o Kubernetes sempre cria o pod novo antes de remover o antigo — estratégia mais segura para produção.

---

## 1. Criar o Deployment inicial

```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: app
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0
      maxSurge: 1
  template:
    metadata:
      labels:
        app: app
    spec:
      containers:
      - name: app
        image: nginx:1.24
        ports:
        - containerPort: 80
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 5
```

```bash
kubectl apply -f deployment.yaml
kubectl get pods -w
```

> O `readinessProbe` é essencial no rolling update — o Kubernetes só remove o pod antigo após o novo estar `Ready`. Sem ele, o tráfego pode ser enviado para um pod que ainda não está pronto.

---

## 2. Executar o rolling update

### Opção A — atualizar a imagem via kubectl

```bash
kubectl set image deployment/app app=nginx:1.25
```

### Opção B — editar o manifesto e reaplicar

```bash
# Edite a linha image: nginx:1.24 para image: nginx:1.25
kubectl apply -f deployment.yaml
```

### Opção C — editar diretamente no cluster

```bash
kubectl edit deployment app
# Altere a imagem no editor que abrir
```

---

## 3. Acompanhar o progresso

```bash
# Acompanhar o rollout em tempo real
kubectl rollout status deployment/app

# Ver os pods sendo substituídos
kubectl get pods -w
```

Saída esperada do `rollout status`:

```
Waiting for deployment "app" rollout to finish: 1 out of 3 new replicas have been updated...
Waiting for deployment "app" rollout to finish: 2 out of 3 new replicas have been updated...
Waiting for deployment "app" rollout to finish: 1 old replicas are pending termination...
deployment "app" successfully rolled out
```

---

## 4. Verificar o histórico de revisões

```bash
kubectl rollout history deployment/app
```

```
REVISION  CHANGE-CAUSE
1         <none>
2         <none>
```

Para registrar uma causa no histórico, use a flag `--record` (deprecated) ou anote manualmente:

```bash
kubectl annotate deployment app \
  kubernetes.io/change-cause="atualização para nginx 1.25"
```

Ver detalhes de uma revisão específica:

```bash
kubectl rollout history deployment/app --revision=2
```

---

## 5. Rollback

Se a nova versão apresentar problemas, reverta para a revisão anterior:

```bash
# Voltar para a revisão anterior
kubectl rollout undo deployment/app

# Voltar para uma revisão específica
kubectl rollout undo deployment/app --to-revision=1
```

Acompanhe o rollback:

```bash
kubectl rollout status deployment/app
kubectl get pods -w
```

---

## 6. Pausar e retomar um rollout

Útil para atualizar múltiplos parâmetros sem disparar um rollout a cada mudança:

```bash
# Pausar
kubectl rollout pause deployment/app

# Fazer as alterações desejadas
kubectl set image deployment/app app=nginx:1.25
kubectl set resources deployment/app -c app --limits=cpu=200m,memory=256Mi

# Retomar — o rollout inicia com todas as mudanças de uma vez
kubectl rollout resume deployment/app
```

---

## 7. Simular uma atualização com falha

Aplique uma imagem inexistente para observar o comportamento:

```bash
kubectl set image deployment/app app=nginx:versao-inexistente
kubectl rollout status deployment/app
```

O rollout ficará travado pois os novos pods não conseguem fazer pull da imagem:

```
Waiting for deployment "app" rollout to finish: 1 out of 3 new replicas have been updated...
```

```bash
# Confirmar o erro
kubectl get pods
# STATUS: ErrImagePull ou ImagePullBackOff

# Reverter imediatamente
kubectl rollout undo deployment/app
```

---

## 8. Comandos de inspeção

```bash
# Ver a imagem atual de cada container do deployment
kubectl get deployment app -o jsonpath='{.spec.template.spec.containers[*].image}'

# Ver detalhes do deployment incluindo estratégia
kubectl describe deployment app | grep -A5 "Strategy\|RollingUpdate"

# Ver ReplicaSets gerados por cada revisão
kubectl get replicasets -l app=app
```

---

## Resumo do fluxo

```
apply/set image → rollout status → history → undo (se necessário)
```

| Operação | Comando |
|----------|---------|
| Atualizar imagem | `kubectl set image deployment/<nome> <container>=<imagem>:<tag>` |
| Acompanhar | `kubectl rollout status deployment/<nome>` |
| Ver histórico | `kubectl rollout history deployment/<nome>` |
| Reverter | `kubectl rollout undo deployment/<nome>` |
| Pausar | `kubectl rollout pause deployment/<nome>` |
| Retomar | `kubectl rollout resume deployment/<nome>` |
