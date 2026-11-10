#!/usr/bin/env bash
# Parte B — evidências de namespaces PID, mount e network em dois contêineres
# independentes da mesma imagem (fixada por digest).
# Cria apenas so3_ns_a e so3_ns_b e os remove ao final (trap EXIT).
# Somente leitura de /proc; root (sudo) é usado apenas para LER /proc de outros processos.
#
# Uso recomendado (no seu terminal, para o sudo poder pedir a senha):
#   sudo -v && bash scripts/coleta_namespaces.sh
# Sem sudo, o script roda igual e marca as leituras do host como "(requer root)".
set -u
export LC_ALL=C
cd "$(dirname "$0")/.."
mkdir -p evidencias
IMAGEM_LAB="${IMAGEM_LAB:-$(cat evidencias/imagem_digest.txt)}"
A=so3_ns_a
B=so3_ns_b
OUT=evidencias/namespaces.txt
if [ -e "$OUT" ]; then
  echo "ERRO: $OUT ja existe. Renomeie (preserve) a coleta anterior antes de rodar de novo." >&2
  exit 1
fi
cleanup() { docker rm -f "$A" "$B" >/dev/null 2>&1 || true; }
trap cleanup EXIT
cleanup

if sudo -n true 2>/dev/null; then ROOT="sudo -n"; else ROOT=""; fi
rd() { # readlink como root se disponivel
  if [ -n "$ROOT" ]; then $ROOT readlink "$1" 2>/dev/null || echo "(erro)"; else readlink "$1" 2>/dev/null || echo "(requer root)"; fi
}

{
  echo "# Data: $(date -Is)"
  echo "# Imagem: $IMAGEM_LAB"
  echo "# Flags: --network none --cap-drop ALL --security-opt no-new-privileges ; comando: sleep 600"
  echo "# Leituras do host como root: $([ -n "$ROOT" ] && echo SIM || echo NAO)"
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
    echo "--- montagens vistas pelo PID 1 do conteiner (/proc/1/mountinfo) ---"
    docker exec "$n" cat /proc/1/mountinfo
  done

  # Host do daemon = host do terminal (Linux nativo, verificado em ambiente.txt).
  echo
  echo "=== VISAO DO HOST (mesmo kernel; daemon local, sem VM) ==="
  echo "--- namespaces iniciais do host: PID 1 do host (systemd) ---"
  printf "host_PID1_comm=%s\n" "$(cat /proc/1/comm)"
  for ns in pid mnt net; do printf "host_%s=%s\n" "$ns" "$(rd /proc/1/ns/$ns)"; done
  echo "--- namespaces do shell que executou o script (deve coincidir com o host) ---"
  for ns in pid mnt net; do printf "shell_%s=%s\n" "$ns" "$(readlink /proc/self/ns/$ns)"; done

  for n in "$A" "$B"; do
    P=$(docker inspect --format '{{.State.Pid}}' "$n")
    echo
    echo "--- $n: PID_host=$P ---"
    ps -o pid,ppid,user,comm,args -p "$P"
    PP=$(ps -o ppid= -p "$P" | tr -d ' ')
    echo "processo pai (PPID=$PP):"
    ps -o pid,ppid,user,comm,args -p "$PP"
    echo "NSpid (PID no host -> PID no namespace do conteiner): $(grep NSpid /proc/$P/status)"
    for ns in pid mnt net; do
      fora=$(rd /proc/$P/ns/$ns)
      dentro=$(docker exec "$n" readlink /proc/1/ns/$ns)
      if [ -z "$ROOT" ]; then ok=NAO_VERIFICADO_SEM_ROOT
      elif [ "$fora" = "$dentro" ]; then ok=IGUAL; else ok=DIFERENTE; fi
      echo "ns=$ns  host:/proc/$P/ns/$ns=$fora  dentro:/proc/1/ns/$ns=$dentro  -> $ok"
    done
  done

  echo
  echo "=== lsns (namespaces pid/mnt/net cujo processo e um dos sleep dos conteineres) ==="
  PA=$(docker inspect --format '{{.State.Pid}}' "$A"); PB=$(docker inspect --format '{{.State.Pid}}' "$B")
  for t in pid mnt net; do
    if [ -n "$ROOT" ]; then $ROOT lsns -t $t -o NS,TYPE,NPROCS,PID,COMMAND 2>&1 | awk -v a="$PA" -v b="$PB" 'NR==1 || $4==a || $4==b'
    else echo "(lsns requer root)"; fi
  done
} > "$OUT" 2>&1

echo "Gerado: $OUT"
