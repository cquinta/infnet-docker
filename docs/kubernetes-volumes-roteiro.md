# Volumes Persistentes no Kubernetes com Minikube

Roteiro prático para criar e testar PersistentVolume (PV), PersistentVolumeClaim (PVC) e StorageClass em um cluster Minikube com 2 nós.

---

## Conceitos

| Objeto | O que é |
|--------|---------|
| `PersistentVolume (PV)` | Recurso de armazenamento provisionado no cluster — pode ser criado manualmente ou dinamicamente |
| `PersistentVolumeClaim (PVC)` | Requisição de armazenamento feita por um pod — o Kubernetes vincula ao PV compatível |
| `StorageClass` | Define como provisionar PVs dinamicamente — o Minikube já vem com uma StorageClass padrão |

### Ciclo de vida

```
StorageClass → PVC → PV (provisionado) → Pod monta o volume
```

### Access Modes

| Modo | Significado |
|------|-------------|
| `ReadWriteOnce (RWO)` | Leitura e escrita por um único nó |
| `ReadOnlyMany (ROX)` | Leitura por múltiplos nós simultaneamente |
| `ReadWriteMany (RWX)` | Leitura e escrita por múltiplos nós simultaneamente |

> O Minikube usa o provisioner `hostPath` que suporta apenas `ReadWriteOnce`.

### Reclaim Policy

| Policy | O que acontece com o PV quando o PVC é deletado |
|--------|--------------------------------------------------|
| `Retain` | PV permanece com os dados — requer limpeza manual |
| `Delete` | PV e os dados são deletados automaticamente |
| `Recycle` | Dados são apagados e o PV fica disponível novamente (deprecated) |

---

## Verificar o ambiente

```bash
# Confirmar os nós do cluster
minikube status
kubectl get nodes -o wide
```

```
NAME           STATUS   ROLES           AGE   VERSION
minikube       Ready    control-plane   10m   v1.x.x
minikube-m02   Ready    <none>          8m    v1.x.x
```

Verificar a StorageClass padrão do Minikube:

```bash
kubectl get storageclass
```

```
NAME                 PROVISIONER                RECLAIMPOLICY   VOLUMEBINDINGMODE
standard (default)   k8s.io/minikube-hostpath   Delete          Immediate
```

---

## 1. Provisionamento Dinâmico (StorageClass)

O provisionamento dinâmico cria o PV automaticamente quando um PVC é criado — sem necessidade de criar o PV manualmente.

### 1.1. Criar o PVC

```yaml
# pvc-dinamico.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-dinamico
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: standard
```

```bash
kubectl apply -f pvc-dinamico.yaml
kubectl get pvc pvc-dinamico
```

```
NAME          STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS
pvc-dinamico  Bound    pvc-a1b2c3d4-...                           1Gi        RWO            standard
```

> `STATUS: Bound` confirma que o PV foi criado e vinculado automaticamente.

### 1.2. Criar um Pod que usa o PVC

```yaml
# pod-pvc-dinamico.yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-pvc-dinamico
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "while true; do date >> /dados/log.txt; sleep 5; done"]
    volumeMounts:
    - name: dados
      mountPath: /dados
  volumes:
  - name: dados
    persistentVolumeClaim:
      claimName: pvc-dinamico
```

```bash
kubectl apply -f pod-pvc-dinamico.yaml
kubectl get pod pod-pvc-dinamico -w
```

### 1.3. Validar a persistência dos dados

```bash
# Aguardar alguns segundos e verificar o arquivo gerado
kubectl exec pod-pvc-dinamico -- cat /dados/log.txt
```

```
Mon Jan 01 00:00:05 UTC 2025
Mon Jan 01 00:00:10 UTC 2025
Mon Jan 01 00:00:15 UTC 2025
```

Deletar o pod e recriar para confirmar que os dados persistem:

```bash
kubectl delete pod pod-pvc-dinamico
kubectl apply -f pod-pvc-dinamico.yaml

# O arquivo deve conter as entradas anteriores + novas
kubectl exec pod-pvc-dinamico -- cat /dados/log.txt
```

---

## 2. Provisionamento Estático (PV manual)

No provisionamento estático o administrador cria o PV manualmente e o PVC é vinculado a ele.

### 2.1. Criar o PV

```yaml
# pv-estatico.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-estatico
spec:
  capacity:
    storage: 500Mi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual
  hostPath:
    path: /mnt/dados-estaticos
```

```bash
kubectl apply -f pv-estatico.yaml
kubectl get pv pv-estatico
```

```
NAME         CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      STORAGECLASS
pv-estatico  500Mi      RWO            Retain           Available   manual
```

### 2.2. Criar o PVC vinculado ao PV

```yaml
# pvc-estatico.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-estatico
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 500Mi
  storageClassName: manual
```

```bash
kubectl apply -f pvc-estatico.yaml
kubectl get pvc pvc-estatico
```

```
NAME          STATUS   VOLUME       CAPACITY   ACCESS MODES   STORAGECLASS
pvc-estatico  Bound    pv-estatico  500Mi      RWO            manual
```

### 2.3. Criar um Pod que usa o PVC estático

```yaml
# pod-pvc-estatico.yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-pvc-estatico
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "echo 'dados persistidos' > /dados/teste.txt; sleep 3600"]
    volumeMounts:
    - name: dados
      mountPath: /dados
  volumes:
  - name: dados
    persistentVolumeClaim:
      claimName: pvc-estatico
```

```bash
kubectl apply -f pod-pvc-estatico.yaml
kubectl exec pod-pvc-estatico -- cat /dados/teste.txt
```

### 2.4. Verificar os dados no nó do Minikube

```bash
# Acessar o nó onde o pod foi agendado
kubectl get pod pod-pvc-estatico -o wide

# Entrar no nó via minikube ssh (ajuste o nome do nó se necessário)
minikube ssh

# Verificar o arquivo no hostPath
cat /mnt/dados-estaticos/teste.txt
# dados persistidos

exit
```

---

## 3. Testar Reclaim Policy Retain

Demonstra que o PV e os dados sobrevivem à deleção do PVC quando a policy é `Retain`.

```bash
# Deletar o PVC
kubectl delete pvc pvc-estatico

# O PV deve permanecer com status Released (não Available)
kubectl get pv pv-estatico
```

```
NAME         CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS     STORAGECLASS
pv-estatico  500Mi      RWO            Retain           Released   manual
```

> `Released` significa que o PVC foi deletado mas o PV ainda tem a referência ao PVC anterior. Para reutilizá-lo é necessário remover o `claimRef`:

```bash
kubectl patch pv pv-estatico \
  --type=json \
  -p='[{"op":"remove","path":"/spec/claimRef"}]'

kubectl get pv pv-estatico
# STATUS volta para Available
```

---

## 4. Usar PVC em um Deployment

Em produção os volumes são usados em Deployments, não em pods standalone. Todos os pods do Deployment compartilham o mesmo PVC (com `RWO` apenas um pod por vez escreve).

```yaml
# deployment-pvc.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-com-volume
spec:
  replicas: 1
  selector:
    matchLabels:
      app: app-com-volume
  template:
    metadata:
      labels:
        app: app-com-volume
    spec:
      containers:
      - name: app
        image: nginx:1.25
        volumeMounts:
        - name: dados
          mountPath: /usr/share/nginx/html
      volumes:
      - name: dados
        persistentVolumeClaim:
          claimName: pvc-dinamico
```

```bash
kubectl apply -f deployment-pvc.yaml
kubectl get pods -l app=app-com-volume -o wide
```

---

## 5. Testar failover entre nós

Valida que os dados persistem quando o pod é recriado em um nó diferente.

```bash
# Ver em qual nó o pod está rodando
kubectl get pod -l app=app-com-volume -o wide

# Escrever dados no volume
kubectl exec deploy/app-com-volume -- \
  sh -c "echo 'teste failover' > /usr/share/nginx/html/index.html"

# Forçar o pod para o outro nó deletando o atual
kubectl delete pod -l app=app-com-volume

# Aguardar o novo pod subir
kubectl get pod -l app=app-com-volume -w

# Verificar se os dados persistiram
kubectl exec deploy/app-com-volume -- cat /usr/share/nginx/html/index.html
# teste failover
```

> Com `hostPath` no Minikube, o dado fica no nó físico. Se o pod for recriado em um nó diferente, o dado não estará lá. Para testar failover real entre nós use o addon `csi-hostpath-driver` ou um provisionador de rede como NFS.

---

## 6. StorageClass com WaitForFirstConsumer

Por padrão a StorageClass do Minikube usa `Immediate` — o PV é criado assim que o PVC é criado, independente de haver um pod. Com `WaitForFirstConsumer` o PV só é provisionado quando um pod requisitar o PVC, permitindo que o scheduler escolha o nó antes de criar o volume.

```yaml
# storageclass-wait.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: standard-wait
provisioner: k8s.io/minikube-hostpath
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
```

```bash
kubectl apply -f storageclass-wait.yaml

# Criar um PVC com a nova StorageClass
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-wait
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 500Mi
  storageClassName: standard-wait
EOF

# O PVC ficará Pending até um pod requisitá-lo
kubectl get pvc pvc-wait
# STATUS: Pending

# Criar um pod que usa o PVC
kubectl run pod-wait --image=busybox:1.36 \
  --overrides='{"spec":{"volumes":[{"name":"v","persistentVolumeClaim":{"claimName":"pvc-wait"}}],"containers":[{"name":"pod-wait","image":"busybox:1.36","command":["sleep","3600"],"volumeMounts":[{"name":"v","mountPath":"/dados"}]}]}}' \
  --restart=Never

# Agora o PVC deve estar Bound
kubectl get pvc pvc-wait
# STATUS: Bound
```

---

## 7. Comandos úteis de inspeção

```bash
# Listar todos os PVs do cluster
kubectl get pv

# Listar todos os PVCs
kubectl get pvc -A

# Ver detalhes do vínculo PV/PVC
kubectl describe pv <NOME_DO_PV>
kubectl describe pvc <NOME_DO_PVC>

# Ver qual PVC um pod está usando
kubectl get pod <NOME_DO_POD> -o jsonpath='{.spec.volumes}'

# Ver eventos relacionados a volumes
kubectl get events --field-selector reason=ProvisioningSucceeded
kubectl get events --field-selector reason=ProvisioningFailed
```

---

## Limpeza

```bash
kubectl delete pod pod-pvc-dinamico pod-pvc-estatico pod-wait
kubectl delete deployment app-com-volume
kubectl delete pvc pvc-dinamico pvc-estatico pvc-wait
kubectl delete pv pv-estatico
kubectl delete storageclass standard-wait
```

---

## Resumo

| Objeto | Criado por | Quando usar |
|--------|-----------|-------------|
| `PV` manual | Administrador | Armazenamento pré-provisionado com controle total |
| `PVC` + `StorageClass` | Desenvolvedor | Provisionamento dinâmico — mais comum em produção |
| `Retain` | Administrador | Dados críticos que não podem ser deletados automaticamente |
| `Delete` | Padrão dinâmico | Ambientes efêmeros onde os dados seguem o ciclo do PVC |
| `WaitForFirstConsumer` | Administrador | Clusters multi-nó onde o scheduler deve escolher o nó antes do volume |
