#!/usr/bin/env bash
# Parte A — registra o ambiente do host do daemon Docker, a versão de cgroup,
# os controladores disponíveis e fixa a imagem por digest.
# Somente leitura: não altera /sys, não muda configuração do Docker.
set -u
export LC_ALL=C
cd "$(dirname "$0")/.."
mkdir -p evidencias

{
  echo '=== DATA ==='
  date -Is
  echo '=== KERNEL (uname -srvmo; hostname omitido) ==='
  uname -srvmo
  echo '=== DISTRIBUICAO ==='
  cat /etc/os-release
  echo '=== VIRTUALIZACAO (systemd-detect-virt; "none" = Linux nativo) ==='
  systemd-detect-virt 2>&1 || true
  echo '=== CPU ==='
  echo "nproc=$(nproc)"
  lscpu | grep -E '^(Model name|Architecture|CPU\(s\)|Thread\(s\) per core|Core\(s\) per socket|Socket\(s\)|Virtualization|Hypervisor vendor)' || true
  echo '=== MEMORIA ==='
  free -h
  echo '=== DOCKER ==='
  docker version
  docker compose version 2>&1 || echo 'docker compose indisponivel'
  docker info --format 'Cgroup={{.CgroupVersion}} Driver={{.CgroupDriver}}'
  docker info --format 'OperatingSystem={{.OperatingSystem}} KernelVersion={{.KernelVersion}} NCPU={{.NCPU}} MemTotal={{.MemTotal}}'
  docker info --format 'SecurityOptions={{.SecurityOptions}}'
  docker context ls
  echo '=== CGROUP NO HOST ==='
  echo "tipo_fs=$(stat -fc %T /sys/fs/cgroup)   (cgroup2fs = cgroup v2 unificado)"
  echo "controladores_raiz=$(cat /sys/fs/cgroup/cgroup.controllers)"
  echo "subtree_control_raiz=$(cat /sys/fs/cgroup/cgroup.subtree_control)"
  echo "cgroup_do_terminal=$(cat /proc/self/cgroup)"
} > evidencias/ambiente.txt 2>&1

# Imagem confiável fixada por digest
docker pull python:3.12-slim > evidencias/imagem_pull.txt 2>&1
IMAGEM_LAB="$(docker image inspect --format '{{index .RepoDigests 0}}' python:3.12-slim)"
printf '%s\n' "$IMAGEM_LAB" > evidencias/imagem_digest.txt

# Visão dos controladores de dentro de um contêiner com os limites da Parte C
docker run --rm --network none --cpus 0.5 --memory 256m --memory-swap 256m --pids-limit 64 \
  --cap-drop ALL --security-opt no-new-privileges --user 65534:65534 "$IMAGEM_LAB" sh -c '
  echo "# Imagem: '"$IMAGEM_LAB"'"
  echo "# Flags: --cpus 0.5 --memory 256m --memory-swap 256m --pids-limit 64"
  echo "=== /proc/self/cgroup ==="; cat /proc/self/cgroup
  echo "=== cgroup.controllers ==="; cat /sys/fs/cgroup/cgroup.controllers
  echo "=== cpu.max ==="; cat /sys/fs/cgroup/cpu.max
  echo "=== memory.max ==="; cat /sys/fs/cgroup/memory.max
  echo "=== memory.swap.max ==="; cat /sys/fs/cgroup/memory.swap.max
  echo "=== pids.max ==="; cat /sys/fs/cgroup/pids.max
  echo "=== kernel visto no conteiner ==="; uname -srm
' > evidencias/controladores.txt 2>&1

echo "Gerados: evidencias/ambiente.txt, imagem_digest.txt, controladores.txt"
echo "IMAGEM_LAB=$IMAGEM_LAB"
