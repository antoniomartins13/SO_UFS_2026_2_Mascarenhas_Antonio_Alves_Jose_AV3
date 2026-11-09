#!/usr/bin/env bash
# Parte B — evidências de namespaces PID, mount e network em dois contêineres
# independentes da mesma imagem (fixada por digest).
# Cria apenas so3_ns_a e so3_ns_b e os remove ao final (trap EXIT).
set -u
export LC_ALL=C
cd "$(dirname "$0")/.."
mkdir -p evidencias
IMAGEM_LAB="${IMAGEM_LAB:-$(cat evidencias/imagem_digest.txt)}"
A=so3_ns_a
B=so3_ns_b
OUT=evidencias/namespaces.txt
cleanup() { docker rm -f "$A" "$B" >/dev/null 2>&1 || true; }
trap cleanup EXIT
cleanup

{
  echo "# Data: $(date -Is)"
  echo "# Imagem: $IMAGEM_LAB"
  echo "# Flags: --network none --cap-drop ALL --security-opt no-new-privileges ; comando: sleep 600"
  docker run -d --name "$A" --network none --cap-drop ALL --security-opt no-new-privileges "$IMAGEM_LAB" sleep 600
  docker run -d --name "$B" --network none --cap-drop ALL --security-opt no-new-privileges "$IMAGEM_LAB" sleep 600

  for n in "$A" "$B"; do
    echo
    echo "=== CONTAINER $n (visao de DENTRO do conteiner) ==="
    docker inspect --format 'ID={{.Id}}' "$n"
    docker inspect --format 'PID_host={{.State.Pid}}' "$n"
    docker exec "$n" sh -c 'printf "PID1_comm="; cat /proc/1/comm'
    docker exec "$n" sh -c 'printf "PID1_cmdline="; tr "\0" " " < /proc/1/cmdline; echo'
    docker exec "$n" readlink /proc/1/ns/pid
    docker exec "$n" readlink /proc/1/ns/mnt
    docker exec "$n" readlink /proc/1/ns/net
    echo "--- processos visiveis dentro do conteiner (ps nao existe na imagem slim; lendo /proc) ---"
    docker exec "$n" sh -c 'for p in /proc/[0-9]*; do printf "%s %s\n" "${p#/proc/}" "$(cat $p/comm 2>/dev/null)"; done'
    echo "--- interfaces de rede vistas no conteiner (/proc/net/dev) ---"
    docker exec "$n" cat /proc/net/dev
  done

  # Host do daemon = host do terminal (Linux nativo, verificado em ambiente.txt).
  # Por isso podemos confirmar no /proc do host o PID informado pelo inspect.
  echo
  echo "=== VISAO DO HOST (mesmo kernel; daemon local, sem VM) ==="
  echo "--- namespaces do PID 1 do host (systemd) ---"
  for ns in pid mnt net; do printf "host_%s=" "$ns"; sudo -n readlink /proc/1/ns/$ns 2>/dev/null || readlink /proc/self/ns/$ns; done
  echo "(se sudo nao estiver disponivel, mostra os namespaces do proprio shell, que sao os do host)"
  for n in "$A" "$B"; do
    P=$(docker inspect --format '{{.State.Pid}}' "$n")
    echo "--- $n: PID_host=$P ---"
    ps -o pid,ppid,user,comm,args -p "$P"
    echo "NSpid (PID no host -> PID no namespace do conteiner): $(grep NSpid /proc/$P/status)"
    for ns in pid mnt net; do printf "host:/proc/%s/ns/%s -> " "$P" "$ns"; sudo -n readlink /proc/$P/ns/$ns 2>/dev/null || echo "(requer root)"; done
  done
  echo
  echo "=== lsns (namespaces do sistema que contem os processos sleep) ==="
  sudo -n lsns -t pid -t mnt -t net 2>/dev/null | grep -E 'NS|sleep' || lsns -t pid -t mnt -t net 2>&1 | grep -E 'NS|sleep' || echo "(lsns sem permissao)"
} > "$OUT" 2>&1

echo "Gerado: $OUT"
