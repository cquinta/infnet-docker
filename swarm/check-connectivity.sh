#!/bin/bash
# Testa a conectividade de rede nas portas necessárias para o Docker Swarm.
# Execute em cada nó do cluster.

MANAGER="10.0.0.160"
WORKER1="10.0.0.234"
WORKER2="10.0.0.246"

NODES=("$MANAGER" "$WORKER1" "$WORKER2")
NODE_NAMES=("manager" "worker-1" "worker-2")

# Portas TCP a testar (nc -z)
TCP_PORTS=(2377 7946)
# Portas UDP a testar (nc -zu)
UDP_PORTS=(7946 4789)

PASS=0
FAIL=0

check_tcp() {
  local host=$1 port=$2 label=$3
  if nc -z -w2 "$host" "$port" 2>/dev/null; then
    echo "  [OK]  TCP $port -> $label ($host)"
    ((PASS++))
  else
    echo "  [FAIL] TCP $port -> $label ($host)"
    ((FAIL++))
  fi
}

check_udp() {
  local host=$1 port=$2 label=$3
  if nc -zu -w2 "$host" "$port" 2>/dev/null; then
    echo "  [OK]  UDP $port -> $label ($host)"
    ((PASS++))
  else
    echo "  [FAIL] UDP $port -> $label ($host)"
    ((FAIL++))
  fi
}

echo "============================================"
echo " Teste de conectividade - Docker Swarm"
echo "============================================"
echo " Manager : $MANAGER"
echo " Worker-1: $WORKER1"
echo " Worker-2: $WORKER2"
echo "--------------------------------------------"
echo ""
echo "Portas do Swarm:"
echo "  2377/TCP  - gerenciamento do cluster (somente manager)"
echo "  7946/TCP  - comunicação entre nós"
echo "  7946/UDP  - comunicação entre nós"
echo "  4789/UDP  - rede overlay (VXLAN)"
echo ""

for i in "${!NODES[@]}"; do
  TARGET="${NODES[$i]}"
  LABEL="${NODE_NAMES[$i]}"

  echo "--- Testando nó: $LABEL ($TARGET) ---"

  # 2377/TCP apenas para o manager
  if [[ "$TARGET" == "$MANAGER" ]]; then
    check_tcp "$TARGET" 2377 "$LABEL"
  fi

  for port in "${TCP_PORTS[@]}"; do
    [[ "$port" == "2377" ]] && continue  # já tratado acima
    check_tcp "$TARGET" "$port" "$LABEL"
  done

  for port in "${UDP_PORTS[@]}"; do
    check_udp "$TARGET" "$port" "$LABEL"
  done

  echo ""
done

echo "============================================"
echo " Resultado: $PASS OK  |  $FAIL FALHA(S)"
echo "============================================"

[[ $FAIL -eq 0 ]] && exit 0 || exit 1
