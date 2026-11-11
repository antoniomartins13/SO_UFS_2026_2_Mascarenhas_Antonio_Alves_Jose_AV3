#!/usr/bin/env bash
# Parte C — experimento de cgroups: C1 (0,5 CPU) x C2 (1,0 CPU), 3 repetições
# alternadas. Mesmos limites de RAM (256 MiB, RAM+swap 256 MiB) e pids (64).
#
# Uso:
#   export ITERACOES=20000000      # congelado após o piloto
#   bash run_experimentos.sh       # 6 execuções principais
#   MODO=piloto REPETICOES=1 ITERACOES=2000000 bash run_experimentos.sh
#
# Cada execução gera resultados/<modo>/<COND>_r<rep>.json (registro bruto),
# .inspect.txt (limites pedidos ao Docker) e .err (stderr). Falhas NÃO são
# apagadas: ficam registradas com status em resultados/<modo>/execucoes.log.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

ITERACOES="${ITERACOES:-20000000}"
REPETICOES="${REPETICOES:-3}"
MODO="${MODO:-principal}"
IMAGEM_LAB="${IMAGEM_LAB:-$(docker image inspect --format '{{index .RepoDigests 0}}' python:3.12-slim)}"
SAIDA="resultados/$MODO"
mkdir -p "$SAIDA"
LOG="$SAIDA/execucoes.log"

declare -A CPUS=([C1]=0.5 [C2]=1.0)

{
  echo "# inicio=$(date -Iseconds) modo=$MODO iteracoes=$ITERACOES repeticoes=$REPETICOES"
  echo "# imagem=$IMAGEM_LAB"
  echo "# host: $(uname -sr) nproc=$(nproc)"
} >> "$LOG"

for rep in $(seq 1 "$REPETICOES"); do
  # alternância: rep ímpar começa por C1, rep par começa por C2
  if (( rep % 2 == 1 )); then ordem=(C1 C2); else ordem=(C2 C1); fi
  for cond in "${ordem[@]}"; do
    nome="so_a3_${MODO}_${cond}_r${rep}"
    base="$SAIDA/${cond}_r${rep}"
    docker rm -f "$nome" >/dev/null 2>&1 || true

    docker create --name "$nome" \
      --cpus "${CPUS[$cond]}" \
      --memory 256m --memory-swap 256m \
      --pids-limit 64 \
      --cgroupns private \
      --network none \
      --user 65534:65534 \
      --cap-drop ALL \
      --security-opt no-new-privileges \
      --read-only --tmpfs /tmp:size=16m \
      -e PYTHONDONTWRITEBYTECODE=1 \
      -v "$DIR/carga_cpu.py:/lab/carga_cpu.py:ro" \
      -v "$DIR/medir.py:/lab/medir.py:ro" \
      "$IMAGEM_LAB" \
      python -B /lab/medir.py "$ITERACOES" >/dev/null

    docker inspect --format \
      'NanoCpus={{.HostConfig.NanoCpus}} CpuQuota={{.HostConfig.CpuQuota}} CpuPeriod={{.HostConfig.CpuPeriod}} Memory={{.HostConfig.Memory}} MemorySwap={{.HostConfig.MemorySwap}} PidsLimit={{.HostConfig.PidsLimit}} User={{.Config.User}} CapDrop={{.HostConfig.CapDrop}} SecurityOpt={{.HostConfig.SecurityOpt}} Network={{.HostConfig.NetworkMode}} CgroupnsMode={{.HostConfig.CgroupnsMode}}' \
      "$nome" > "$base.inspect.txt"

    inicio=$(date -Iseconds)
    timeout 90 docker start -a "$nome" > "$base.json" 2> "$base.err"
    rc=$?
    oom=$(docker inspect --format '{{.State.OOMKilled}}' "$nome" 2>/dev/null)
    docker rm -f "$nome" >/dev/null 2>&1

    echo "cond=$cond rep=$rep iteracoes=$ITERACOES inicio=$inicio exit=$rc oom=$oom arquivo=$base.json" | tee -a "$LOG"
  done
done
echo "# fim=$(date -Iseconds)" >> "$LOG"
