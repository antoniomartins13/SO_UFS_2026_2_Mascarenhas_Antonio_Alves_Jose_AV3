# Atividade 3 — Partes C (cgroups) e D (mount read-only e menor privilégio)

> Implementação própria, equivalente ao kit de apoio (`carga_cpu.py`, `run_experimentos.sh`,
> `resumo.py`, `evidencia_ns_mount.sh`), que não estava disponível localmente. Adaptações estão
> descritas abaixo e devem constar na declaração de uso de IA (scripts escritos com auxílio do
> Claude Code e verificados por execução real).

## Ambiente em que os dados foram coletados

| Item | Valor |
|---|---|
| Host do daemon | Ubuntu 24.04.5 LTS dentro do **WSL2** (VM leve Hyper-V sobre Windows), Docker Engine nativo na distro (não Docker Desktop) |
| Kernel | `6.18.54.1-microsoft-standard-WSL2` x86_64 |
| CPUs lógicas / RAM | 12 / 13 GiB visíveis na VM WSL2 |
| Docker | 29.1.3; `Cgroup=2 Driver=systemd`; daemon **rootful** |
| Controladores na raiz | `cpuset cpu io memory hugetlb pids rdma` |
| LSM | seccomp (perfil builtin); **AppArmor/SELinux ausentes** no kernel WSL2 (`/proc/self/attr/current` = `kernel`) |
| Imagem | `python@sha256:5e2bdb1b0d542d5039cffb8181c65930093949194a65c365dfb1b0fe13a4fa5b` (python:3.12-slim) |

## Arquivos

| Arquivo | Função |
|---|---|
| `carga_cpu.py` | Carga determinística: `Σ i² mod (2⁶¹−1)` para `i < N`, um thread. Checksum conferido pela forma fechada `N(N−1)(2N−1)/6`. Aborta sozinho após 60 s. |
| `medir.py` | Roda **dentro** do contêiner: lê `/sys/fs/cgroup` (antes/depois), executa a carga, amostra `memory.current` a cada 0,2 s. Só lê `/sys`. |
| `run_experimentos.sh` | Cria um contêiner por execução com os limites, salva `docker inspect` (limites pedidos), executa com `timeout 90`, preserva JSON/stderr/log mesmo em caso de falha. |
| `resumo.py` | Gera `resultados/execucoes.csv`, `resumo.csv`, `resumo.md` e `grafico_c1_c2.png`. |
| `parte_d_readonly.sh` | Casos D1–D3 da Parte D. |

## Reprodução

```bash
cd atividade3
docker pull python:3.12-slim
export IMAGEM_LAB="$(docker image inspect --format '{{index .RepoDigests 0}}' python:3.12-slim)"

# Parte C — piloto (feito: N=2M e N=100M, ver resultados/piloto_*)
MODO=piloto REPETICOES=1 ITERACOES=2000000 bash run_experimentos.sh
# Parte C — 6 execuções principais com N congelado
ITERACOES=100000000 bash run_experimentos.sh
python3 resumo.py

# Parte D
bash parte_d_readonly.sh
```

Limpeza: os contêineres são criados com nome `so_a3_*` e removidos ao fim de cada execução;
se algo for interrompido: `docker ps -aq --filter name=so_a3_ | xargs -r docker rm -f`.
Os diretórios `dados_demo*/` são sintéticos e podem ser apagados com `rm -r dados_demo dados_demo_rw`.

---

## Parte C — Experimento de cgroups

### Metodologia

Flags comuns às duas condições: `--memory 256m --memory-swap 256m --pids-limit 64 --cgroupns private
--network none --user 65534:65534 --cap-drop ALL --security-opt no-new-privileges --read-only`.

| Condição | Flag | `cpu.max` lido no cgroup | `memory.max` | `memory.swap.max` | `pids.max` |
|---|---|---|---|---|---|
| C1 | `--cpus 0.5` | `50000 100000` | 268435456 (256 MiB) | 0 | 64 |
| C2 | `--cpus 1.0` | `100000 100000` | 268435456 (256 MiB) | 0 | 64 |

- **Confirmação do limite efetivo:** os valores acima foram lidos pelo próprio processo em
  `/sys/fs/cgroup/*` (cgroup namespace privado → a raiz vista é o cgroup do contêiner), em cada execução
  (`cgroup_antes.arquivos` nos JSON). `docker inspect` (`*.inspect.txt`) mostra só o que foi *pedido*
  (`NanoCpus=500000000`, `Memory=268435456`, `MemorySwap=268435456`, `PidsLimit=64`).
  `memory.swap.max = 0` confirma RAM+swap = 256 MiB.
- **Piloto:** N=2M durou ~0,13 s de CPU (curto demais, dominado por ruído). N=100M deu ~16 s em C1 e
  ~8,6 s em C2, abaixo do limite de 60 s. **N = 100.000.000 congelado** para as seis execuções.
- **Ordem alternada:** C1r1, C2r1, C2r2, C1r2, C1r3, C2r3 (ver `resultados/principal/execucoes.log`).
- Nenhuma execução falhou; nenhuma foi descartada.

### Resultados (registros brutos em `resultados/principal/`, CSV em `resultados/execucoes.csv`)

| Exec. | Wall (s) | CPU proc. (s) | Mi iter/s | Δusage (s) | Δnr_periods | Δnr_throttled | Δthrottled (s) | RSS pico (MiB) | memory.peak (MiB) |
|---|---|---|---|---|---|---|---|---|---|
| C1 r1 | 15,79 | 7,87 | 6,33 | 7,95 | 159 | 159 | 7,96 | 15,2 | 17,9 |
| C1 r2 | 16,07 | 8,01 | 6,22 | 8,09 | 162 | 162 | 6,86 | 15,2 | 18,3 |
| C1 r3 | 16,09 | 8,02 | 6,22 | 8,11 | 162 | 162 | 6,89 | 15,1 | 18,2 |
| C2 r1 | 8,39 | 7,74 | 11,91 | 7,82 | 84 | 0 | 0 | 15,1 | 18,2 |
| C2 r2 | 8,43 | 7,78 | 11,86 | 7,86 | 85 | 0 | 0 | 15,2 | 18,5 |
| C2 r3 | 10,16 | 9,37 | 9,85 | 9,44 | 103 | 0 | 0 | 15,1 | 17,9 |

Consolidado (`resultados/resumo.md`):

| Condição | n | Mediana (Mi iter/s) | Mín–Máx | CV | Wall mediano |
|---|---|---|---|---|---|
| C1 (0,5 CPU) | 3 | **6,22** | 6,22–6,33 | 1,1 % | 16,07 s |
| C2 (1,0 CPU) | 3 | **11,86** | 9,85–11,91 | 10,5 % | 8,43 s |

**Razão das medianas C2/C1 = 1,91.** Gráfico: `resultados/grafico_c1_c2.png` (barras = mediana,
pontos = cada repetição, n=3).

Memória e tarefas: `pids.peak = 6` (limite 64, `pids.events max=0`); `memory.events oom_kill = 0` em todas.

> **Três medidas de memória diferentes, não “RAM média”:**
> *RSS pico do processo* (`ru_maxrss`, ~15,2 MiB) = páginas residentes só do processo da carga;
> *memory.current* (amostrado, máx ~18 MiB) = uso instantâneo de todo o cgroup (todos os processos
> + page cache + kernel memory cobrada); *memory.peak* (~18–18,5 MiB) = máximo de `memory.current`
> desde a criação do cgroup. Todos estão muito abaixo de `memory.max` = 256 MiB.

### Análise

**Como a quota foi confirmada? Houve throttling?** A quota foi confirmada por `cpu.max` dentro do cgroup,
não pela flag. Em C1 houve throttling em **100 % dos períodos** (Δnr_throttled = Δnr_periods ≈ 160),
com ~6,9–8,0 s de `throttled_usec`. Os contadores fecham com o tempo: Δusage ≈ 8,0 s de CPU em
≈ 16 s de parede → razão ≈ 0,50, exatamente 50 000 µs a cada 100 000 µs. O processo não “roda devagar”:
ele roda em velocidade normal por ~50 ms e depois fica suspenso até o próximo período. Em C2 não houve
throttling (Δnr_throttled = 0): a carga é **single-thread**, logo nunca consegue consumir mais de 1 CPU
por período, e a quota de 1,0 não chega a limitar. A quota é **tempo de CPU agregado por período**, não
afinidade nem reserva de núcleo: o processo pode migrar entre as 12 CPUs, e `cpuset` não foi alterado.

**O que aconteceu com mediana e variação?** A mediana de trabalho/s quase dobrou (×1,91, não ×2,00). O
tempo de CPU para fazer o trabalho fixo foi praticamente igual nas duas condições (~7,8–8,0 s), o que
mostra que a quota mudou *quando* o processo pode rodar, não *quanto* trabalho custa. C1 foi muito
estável (CV 1,1 %), porque o gargalo é determinístico (a quota). C2 teve uma repetição lenta (r3,
9,85 Mi iter/s) **sem nenhum throttling**, mas com o tempo de CPU do próprio processo também maior
(9,37 s contra ~7,8 s). Ou seja, o mesmo trabalho custou mais ciclos/tempo de CPU, o que aponta para
ruído do host (frequência/turbo, vizinho SMT, atividade do Windows sobre a VM WSL2), não para o cgroup.
A conclusão vem da combinação de contadores e não é afirmada como causa provada por uma única amostra.

**Principal ameaça à validade:** o host compartilhado e não controlado. O WSL2 é uma VM cujo
escalonamento e frequência de CPU dependem do Windows; não fixamos frequência nem isolamos núcleos.
Ainda: n=3 por condição, um único tipo de carga (CPU-bound, single-thread, Python) e o overhead de
`medir.py`/startup do interpretador incluído no Δusage do cgroup (mas não no wall da carga). A razão
<2 também decorre de C2 não ser limitado pela quota: o “teto” de C2 é a velocidade de um núcleo.

**Por que limitar RAM/tarefas importa em inferência?** Em servidor de inferência compartilhado, um
cliente/modelo com contexto grande ou vazamento pode consumir toda a RAM do host. Com `memory.max`, o
OOM fica contido no cgroup. `pids.max` contém explosão de processos/threads (fork bomb, workers
descontrolados). A quota de CPU garante que um job de pré/pós-processamento não esfomeie os vizinhos.
**Risco que permanece:** cgroups não isolam cache L3, banda de memória nem frequência compartilhada
(vizinho barulhento, visível na própria variação de C2), e **RAM ≠ VRAM**: memória de GPU não é limitada
por `memory.max`. O kernel continua compartilhado: uma falha de kernel/runtime atinge todos.

---

## Parte D — Mount read-only e menor privilégio

Diretório **sintético** `dados_demo/texto.txt` (“Documento sintetico”) montado como `/dados:ro`. Nada
além de `dados_demo*/` foi montado (nem `/`, home, socket do Docker). Sem `--privileged`, sem desativar LSM.
Restrições aplicadas em todos os casos: `--cap-drop ALL`, `--security-opt no-new-privileges`,
`--read-only` (rootfs), `--network none`, limites de CPU/memória/pids.

| Caso | Identidade | Mount `/dados` | Leitura | Criação de arquivo | Mecanismo que negou |
|---|---|---|---|---|---|
| **D1** (principal) | uid 65534 (nobody) | `ro` | OK | **NEGADA — errno 30 `EROFS`** | flag `ro` do mount |
| D2 (controle) | uid 0 (root), sem capabilities | `ro` | OK | **NEGADA — `EROFS`** | flag `ro` do mount |
| D3 (controle) | uid 65534 (nobody) | `rw` (cópia sintética) | OK | **NEGADA — errno 13 `EACCES`** | permissão DAC (dono 1000, modo 755) |

Evidências em `resultados/parte_d/D*.log`:
- `/proc/self/status`: `CapEff: 0000000000000000`, `CapBnd: 0…0`, `NoNewPrivs: 1`, `Seccomp: 2` (filtro ativo).
- `/proc/self/mountinfo`: `… /dados ro,relatime - ext4 /dev/sdd rw,…`. O **ponto de montagem** é `ro`,
  embora o superbloco do ext4 do host continue `rw` (o host segue podendo escrever).
- `sha256` e `ls -ln` do diretório no host idênticos antes/depois: nada foi criado.

### Interpretação: diferenciar os mecanismos

- **Mount namespace:** dá ao contêiner sua própria árvore de montagens. É por isso que `/dados` existe
  só ali e que o restante do host não é visível. Ele define *o que é visível*, não *o que é gravável*.
- **Montagem read-only (bind mount `ro`):** flag por ponto de montagem (`MNT_READONLY`); o VFS recusa a
  escrita com `EROFS` **antes** de checar permissões, independentemente de quem é o usuário (D2: até root).
- **Permissões/identidade (DAC):** uid/gid e modo do arquivo; nobody não é dono → `EACCES` (D3), mesmo em mount rw.
- **Proteção do kernel (capabilities, no_new_privs, seccomp, LSM):** sem `CAP_DAC_OVERRIDE`/`CAP_SYS_ADMIN`,
  root no contêiner não ignora permissões nem pode remontar `/dados` como rw. `no_new_privs` impede
  ganho de privilégio por binários setuid. **Neste ambiente não há AppArmor/SELinux** (kernel WSL2),
  então essa camada não está presente, uma limitação a declarar.
- **Cgroup** é outro eixo: limita *quanto* recurso se consome; não controla acesso a arquivos.

**O que a negação não prova:** isolamento absoluto. O kernel é compartilhado (uma vulnerabilidade de
kernel/runtime contorna tudo isso), o daemon é rootful, o `mountinfo` revela o caminho do host e o
conteúdo continua **legível**: `ro` protege integridade, não confidencialidade.
Em inferência, montar o corpus/modelo `ro` impede que um processo comprometido envenene os dados ou os
pesos compartilhados, mas não impede que ele os leia e vaze (por isso também `--network none`, menor
privilégio e atualização de kernel/runtime).

## Limitações

- WSL2: há uma VM intermediária (Hyper-V) entre o hardware e o kernel Linux; o ruído do Windows não é controlado.
- Sem AppArmor/SELinux no kernel WSL2; seccomp builtin ativo.
- n=3 por condição; carga somente CPU-bound single-thread.
- Logs contêm caminhos do host (`/home/anderson/...`): revisar antes de publicar se for sensível.
