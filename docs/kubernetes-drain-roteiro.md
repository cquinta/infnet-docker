# Drenagem Segura de Nó Kubernetes

Roteiro para remover workloads de um nó de forma controlada antes de manutenção, atualização ou descomissionamento.

---

## O que é drain?

`kubectl drain` evita que novos pods sejam agendados no nó (`cordon`) e remove os pods existentes, que são recriados em outros nós pelo scheduler.

---

## 1. Verificar o estado do cluster antes de drenar

```bash
# Ver todos os nós e seus status
kubectl get nodes -o wide

# Ver pods em execução no nó alvo
kubectl get pods -A -o wide --field-selector spec.nodeName=<NOME_DO_NO>
```

> Confirme que os outros nós têm capacidade suficiente para absorver os workloads do nó que será drenado.

---

## 2. Cordon — bloquear novos agendamentos

Antes de drenar, marque o nó como não agendável para que o scheduler não coloque novos pods nele durante o processo:

```bash
kubectl cordon <NOME_DO_NO>
```

Confirme que o nó está com status `SchedulingDisabled`:

```bash
kubectl get node <NOME_DO_NO>
```

```
NAME           STATUS                     ROLES    AGE   VERSION
k8s-worker-1   Ready,SchedulingDisabled   <none>   10d   v1.37.x
```

---

## 3. Drenar o nó

```bash
kubectl drain <NOME_DO_NO> \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --grace-period=60 \
  --timeout=300s
```

| Flag | Para que serve |
|------|----------------|
| `--ignore-daemonsets` | DaemonSets (como Cilium e kube-proxy) rodam em todos os nós por design — não podem ser removidos. Essa flag instrui o drain a ignorá-los. |
| `--delete-emptydir-data` | Pods que usam volumes `emptyDir` perdem os dados ao serem removidos. Essa flag confirma que você aceita essa perda. |
| `--grace-period=60` | Tempo em segundos que o pod tem para encerrar graciosamente antes de ser forçado. Padrão do pod se omitido. |
| `--timeout=300s` | Tempo máximo de espera pelo drain completo antes de retornar erro. |

---

## 4. Situações que bloqueiam o drain

### 4.1. Pod com PodDisruptionBudget restritivo

Se um Deployment tiver um `PodDisruptionBudget` (PDB) que não permite nenhuma indisponibilidade, o drain ficará travado.

```bash
# Verificar PDBs no cluster
kubectl get pdb -A

# Descrever o PDB problemático
kubectl describe pdb <NOME_DO_PDB> -n <NAMESPACE>
```

Opções:
- Aumentar temporariamente o `minAvailable` ou `maxUnavailable` no PDB
- Usar `--disable-eviction` (força delete em vez de eviction — use com cautela):

```bash
kubectl drain <NOME_DO_NO> \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --disable-eviction
```

### 4.2. Pod standalone (sem controller)

Pods criados diretamente (sem Deployment, StatefulSet, etc.) não são recriados após o drain. O comando bloqueará por segurança.

```bash
# Identificar pods sem controller no nó
kubectl get pods -A -o wide --field-selector spec.nodeName=<NOME_DO_NO> | grep -v "Running\|Completed"
```

Adicione `--force` apenas se tiver certeza que esses pods podem ser perdidos:

```bash
kubectl drain <NOME_DO_NO> \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --force
```

---

## 5. Realizar a manutenção

Com o nó drenado, execute o que for necessário:

```bash
# Exemplo: atualizar pacotes do sistema
sudo apt-get update && sudo apt-get upgrade -y

# Exemplo: atualizar kubeadm/kubelet/kubectl
sudo apt-mark unhold kubelet kubeadm kubectl
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl daemon-reload
sudo systemctl restart kubelet
```

---

## 6. Reabilitar o nó após manutenção

```bash
kubectl uncordon <NOME_DO_NO>
```

Confirme que o nó voltou ao status `Ready`:

```bash
kubectl get node <NOME_DO_NO>
```

O scheduler voltará a agendar pods no nó normalmente.

---

## 7. Verificar redistribuição dos pods

```bash
kubectl get pods -A -o wide | grep <NOME_DO_NO>
```

---

## Resumo do fluxo

```
cordon → drain → manutenção → uncordon
```

| Etapa | Comando |
|-------|---------|
| Bloquear agendamento | `kubectl cordon <NO>` |
| Remover pods | `kubectl drain <NO> --ignore-daemonsets --delete-emptydir-data` |
| Reabilitar | `kubectl uncordon <NO>` |
