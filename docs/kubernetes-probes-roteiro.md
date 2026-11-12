# Probes no Kubernetes

Roteiro prático sobre como configurar e validar os três tipos de probes disponíveis no Kubernetes para monitorar a saúde dos containers.

---

## O que são probes?

Probes são verificações periódicas que o kubelet executa em um container para determinar seu estado. Existem três tipos:

| Probe | Pergunta que responde | Ação em caso de falha |
|-------|-----------------------|-----------------------|
| `livenessProbe` | O container está vivo? | Reinicia o container |
| `readinessProbe` | O container está pronto para receber tráfego? | Remove o pod dos endpoints do Service |
| `startupProbe` | O container terminou de inicializar? | Reinicia o container (desativa liveness/readiness durante a inicialização) |

---

@app.get("/hostname")
def get_hostname():
    """Retorna o hostname do container que está respondendo."""
    return {"hostname": socket.gethostname()}


@app.get("/version")
def get_version():
    """Retorna a versão da API."""
    return {"version": API_VERSION}


@app.get("/health")
def healthcheck():
    """Healthcheck simples da API."""
    return {"status": "healthy"}

## Mecanismos de verificação

Cada probe pode usar um dos três mecanismos abaixo:

| Mecanismo | Como funciona |
|-----------|---------------|
| `httpGet` | Faz uma requisição HTTP GET — sucesso se o status for entre 200 e 399 |
| `exec` | Executa um comando dentro do container — sucesso se o exit code for 0 |
| `tcpSocket` | Abre uma conexão TCP na porta — sucesso se a conexão for estabelecida |

---

## Parâmetros comuns

```yaml
initialDelaySeconds: 10   # Aguarda X segundos após o container iniciar antes da primeira verificação
periodSeconds: 5          # Intervalo entre verificações
timeoutSeconds: 3         # Tempo máximo de espera por resposta
failureThreshold: 3       # Número de falhas consecutivas para considerar o probe falho
successThreshold: 1       # Número de sucessos consecutivos para considerar o probe bem-sucedido
```

---

## 1. livenessProbe

Detecta containers travados que não conseguem se recuperar sozinhos. O kubelet reinicia o container quando o probe falha.

### Exemplo com httpGet

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: liveness-http
spec:
  containers:
  - name: app
    image: nginx:1.25
    ports:
    - containerPort: 80
    livenessProbe:
      httpGet:
        path: /healthz
        port: 80
      initialDelaySeconds: 10
      periodSeconds: 5
      failureThreshold: 3
```

### Exemplo com exec

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: liveness-exec
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "touch /tmp/healthy; sleep 30; rm /tmp/healthy; sleep 600"]
    livenessProbe:
      exec:
        command:
        - cat
        - /tmp/healthy
      initialDelaySeconds: 5
      periodSeconds: 5
      failureThreshold: 3
```

> O container cria `/tmp/healthy` na inicialização, remove após 30s e dorme. O liveness detecta a ausência do arquivo e reinicia o container.

Aplique e observe o comportamento:

```bash
kubectl apply -f liveness-exec.yaml
kubectl get pod liveness-exec -w
```

Após ~35 segundos o campo `RESTARTS` incrementará:

```
NAME            READY   STATUS    RESTARTS   AGE
liveness-exec   1/1     Running   0          30s
liveness-exec   1/1     Running   1          65s
```

---

## 2. readinessProbe

Controla quando o pod começa a receber tráfego. Enquanto o probe falhar, o pod é removido dos endpoints do Service — sem reiniciar o container.

### Exemplo com httpGet

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: readiness-http
  labels:
    app: readiness-demo
spec:
  containers:
  - name: app
    image: nginx:1.25
    ports:
    - containerPort: 80
    readinessProbe:
      httpGet:
        path: /
        port: 80
      initialDelaySeconds: 5
      periodSeconds: 5
      failureThreshold: 3
---
apiVersion: v1
kind: Service
metadata:
  name: readiness-svc
spec:
  selector:
    app: readiness-demo
  ports:
  - port: 80
    targetPort: 80
```

Verifique se o pod está nos endpoints do Service:

```bash
kubectl apply -f readiness-http.yaml
kubectl get endpoints readiness-svc
```

Simule uma falha removendo o index do nginx:

```bash
kubectl exec readiness-http -- rm /usr/share/nginx/html/index.html
```

O nginx passa a retornar 404, o readiness falha e o pod sai dos endpoints:

```bash
kubectl get endpoints readiness-svc
# ADDRESS ficará vazio
kubectl describe pod readiness-http | grep -A5 Conditions
```

---

## 3. startupProbe

Indicado para aplicações com inicialização lenta (ex: JVM, migrações de banco). Enquanto o startupProbe não tiver sucesso, o liveness e o readiness ficam desativados — evitando reinicializações prematuras.

### Exemplo com tcpSocket

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: startup-tcp
spec:
  containers:
  - name: app
    image: nginx:1.25
    ports:
    - containerPort: 80
    startupProbe:
      tcpSocket:
        port: 80
      initialDelaySeconds: 5
      periodSeconds: 5
      failureThreshold: 12      # Aguarda até 60s (12 * 5s) para a inicialização
    livenessProbe:
      httpGet:
        path: /
        port: 80
      periodSeconds: 10
      failureThreshold: 3
```

> Com `failureThreshold: 12` e `periodSeconds: 5`, o Kubernetes aguarda até **60 segundos** para a aplicação inicializar antes de considerar o pod com falha.

---

## 4. Combinando os três probes

Configuração recomendada para aplicações em produção:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-completo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: app-completo
  template:
    metadata:
      labels:
        app: app-completo
    spec:
      containers:
      - name: app
        image: nginx:1.25
        ports:
        - containerPort: 80
        startupProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 5
          failureThreshold: 12
        livenessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 0
          periodSeconds: 10
          timeoutSeconds: 3
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 0
          periodSeconds: 5
          timeoutSeconds: 2
          failureThreshold: 3
          successThreshold: 1
```

---

## 5. Inspecionar eventos dos probes

```bash
# Ver eventos de falha de probe
kubectl describe pod <NOME_DO_POD> | grep -A 20 Events

# Acompanhar reinicializações em tempo real
kubectl get pod <NOME_DO_POD> -w

# Ver logs do container reiniciado anteriormente
kubectl logs <NOME_DO_POD> --previous
```

Exemplo de evento de falha de liveness:

```
Warning  Unhealthy  5s    kubelet  Liveness probe failed: HTTP probe failed with statuscode: 500
Warning  Killing    5s    kubelet  Container app failed liveness probe, will be restarted
```

---

## Resumo de quando usar cada probe

| Situação | Probe recomendado |
|----------|-------------------|
| Container pode travar sem morrer | `livenessProbe` |
| Aplicação demora para inicializar | `startupProbe` |
| Aplicação precisa de warm-up antes de receber tráfego | `readinessProbe` |
| Aplicação em produção | Os três combinados |
