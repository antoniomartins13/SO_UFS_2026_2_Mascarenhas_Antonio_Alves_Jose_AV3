#!/usr/bin/env bash
# Parte D — mount read-only e menor privilégio.
# Monta SOMENTE o diretório sintético dados_demo/ em /dados:ro e registra:
#   D1 (principal): uid 65534 (nobody), cap-drop ALL, no-new-privileges, /dados:ro
#       -> leitura OK, criação de arquivo negada
#   D2 (controle):  root no contêiner, cap-drop ALL, no-new-privileges, /dados:ro
#       -> mostra que a negação vem da flag ro do mount, não da identidade
#   D3 (controle):  uid 65534, mesmas restrições, cópia sintética montada RW
#       -> mostra negação por permissão DAC (dono/modo), sem ro
# Nada é montado além de dados_demo*/; não usa --privileged nem desativa AppArmor.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"
IMAGEM_LAB="${IMAGEM_LAB:-$(docker image inspect --format '{{index .RepoDigests 0}}' python:3.12-slim)}"
OUT="resultados/parte_d"
mkdir -p "$OUT" dados_demo dados_demo_rw
printf '%s\n' 'Documento sintetico' > dados_demo/texto.txt
printf '%s\n' 'Documento sintetico' > dados_demo_rw/texto.txt
chmod 755 dados_demo dados_demo_rw; chmod 644 dados_demo/texto.txt dados_demo_rw/texto.txt

# Script executado dentro do contêiner (só leitura de /proc e tentativa de escrita em /dados)
INTERNO='
echo "== identidade =="; id
echo "== /proc/self/status (caps e no_new_privs) =="
grep -E "^(CapInh|CapPrm|CapEff|CapBnd|CapAmb|NoNewPrivs|Seccomp):" /proc/self/status
echo "== perfil LSM =="; cat /proc/self/attr/current 2>/dev/null || echo "(indisponivel)"; echo
echo "== mountinfo de /dados =="; grep " /dados " /proc/self/mountinfo
echo "== permissoes =="; ls -ln /dados
echo "== leitura =="; cat /dados/texto.txt; echo "leitura_exit=$?"
echo "== tentativa de escrita =="
python3 -c "
import errno, os
try:
    open(\"/dados/novo.txt\", \"x\").close()
    print(\"escrita_resultado=PERMITIDA\")
except OSError as e:
    print(f\"escrita_resultado=NEGADA errno={e.errno} ({errno.errorcode[e.errno]}) msg={e.strerror}\")
"
touch /dados/novo_touch.txt; echo "touch_exit=$?"
'

COMUNS=(--rm --network none --cap-drop ALL --security-opt no-new-privileges
        --read-only --cpus 0.5 --memory 64m --pids-limit 16)

roda() {  # nome  usuario  volume
  local nome="$1" usuario="$2" vol="$3" arq="$OUT/$1.log"
  {
    echo "# caso=$nome data=$(date -Iseconds) imagem=$IMAGEM_LAB"
    echo "# docker run ${COMUNS[*]} --user $usuario -v $vol"
    echo "# host antes: $(ls -ln "${vol%%:*}" | tr '\n' ' ')"
    echo "# sha256 antes: $(sha256sum "${vol%%:*}/texto.txt" | cut -d' ' -f1)"
    timeout 60 docker run "${COMUNS[@]}" --user "$usuario" -v "$vol" "$IMAGEM_LAB" sh -c "$INTERNO" 2>&1
    echo "# docker_exit=$?"
    echo "# host depois: $(ls -ln "${vol%%:*}" | tr '\n' ' ')"
    echo "# sha256 depois: $(sha256sum "${vol%%:*}/texto.txt" | cut -d' ' -f1)"
  } > "$arq"
  echo "== $arq"; cat "$arq"; echo
}

{
  echo "# contexto de seguranca do daemon"
  docker info --format 'SecurityOptions={{.SecurityOptions}} Cgroup={{.CgroupVersion}} Rootless={{range .SecurityOptions}}{{if eq . "name=rootless"}}sim{{end}}{{end}}'
  echo "uid_host=$(id -u)"
} > "$OUT/contexto.txt"

roda D1_nobody_ro "65534:65534" "$DIR/dados_demo:/dados:ro"
roda D2_root_capdrop_ro "0:0" "$DIR/dados_demo:/dados:ro"
roda D3_nobody_rw_controle "65534:65534" "$DIR/dados_demo_rw:/dados:rw"
