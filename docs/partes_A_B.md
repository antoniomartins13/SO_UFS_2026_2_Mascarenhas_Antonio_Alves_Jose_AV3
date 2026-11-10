# Partes A e B — Ambiente e evidências de namespaces

Responsável pela coleta: **Antônio José Martins Mascarenhas** (Integrante 1).
Parte A coletada em **09/11/2026**; Parte B (oficial) em **10/11/2026**. Todos os valores abaixo foram copiados dos logs em [`../evidencias/`](../evidencias/).
Nenhum foi tirado de exemplo.

> **Para o Integrante 3:** a tabela comparativa e a explicação do PID 1 são sua parte. As seções 3 e 4
> trazem os dados já organizados e um rascunho que pode ser revisado ou reescrito.

## 1. Parte A — Ambiente

| Item | Valor | Fonte |
|---|---|---|
| Tipo de host do daemon | **Linux nativo**, sem VM, WSL2 ou Docker Desktop. O daemon roda no mesmo host do terminal. | `systemd-detect-virt = none`; `docker context` = `unix:///var/run/docker.sock` |
| Hardware | Intel Core i5-11300H, 4 núcleos / **8 CPUs lógicas**, VT-x | `lscpu`, `nproc` |
| RAM | 16 GB (15 GiB visíveis), swap 8 GiB | `free -h` |
| Distribuição | Ubuntu 26.04.1 LTS | `/etc/os-release` |
| Kernel | `7.0.0-43-generic` x86_64 (`PREEMPT_DYNAMIC`) | `uname -srvmo` |
| Docker | Engine **29.9.3** (rootful), containerd v2.4.2, runc 1.5.2 | `docker version` |
| Compose | v5.7.0 | `docker compose version` |
| cgroup | **v2** unificado (`cgroup2fs`), driver **systemd** | `docker info`, `stat -fc %T /sys/fs/cgroup` |
| Controladores (raiz) | `cpuset cpu io memory hugetlb pids rdma misc dmem` | `/sys/fs/cgroup/cgroup.controllers` |
| Segurança | AppArmor (`default`), seccomp (`builtin`), cgroupns | `docker info SecurityOptions` |
| Imagem | `python@sha256:5e2bdb1b0d542d5039cffb8181c65930093949194a65c365dfb1b0fe13a4fa5b` (`python:3.12-slim`) | `evidencias/imagem_digest.txt` |

**Verificação dos limites dentro de um contêiner** (`evidencias/controladores.txt`). Executado com as flags da condição C1
(`--cpus 0.5 --memory 256m --memory-swap 256m --pids-limit 64`), o próprio contêiner lê em `/sys/fs/cgroup`:
`cpu.max = 50000 100000`, `memory.max = 268435456`, `memory.swap.max = 0`, `pids.max = 64`.
A raiz vista é `0::/` (cgroup namespace privado). O `uname -r` dentro do contêiner retorna `7.0.0-43-generic`,
o mesmo kernel do host.

O digest é **idêntico** ao usado pelo Integrante 2 nas Partes C/D, então a imagem é a mesma nos dois ambientes.

### Atenção: dois ambientes diferentes

As Partes C/D foram executadas por outro integrante em **WSL2** (Ubuntu 24.04.5, kernel `6.18.54.1-microsoft-standard-WSL2`,
Docker 29.1.3, 12 CPUs). As Partes A/B foram executadas aqui, em **Linux nativo**. O relatório precisa deixar isso explícito:
o diagrama mostra os dois ambientes lado a lado. Os resultados de namespaces valem como mecanismo, mas os números de cgroups
se referem ao ambiente WSL2.

## 2. Diagrama

![Diagrama de infraestrutura](../diagrama/infraestrutura.png)

Fonte editável: [`../diagrama/infraestrutura.svg`](../diagrama/infraestrutura.svg).

## 3. Parte B — Dados brutos dos namespaces

Dois contêineres independentes da mesma imagem, ambos com `--network none --cap-drop ALL --security-opt no-new-privileges`
e o comando `sleep 600`. **Coleta oficial:** [`../evidencias/namespaces.txt`](../evidencias/namespaces.txt)
(10/11/2026, leituras do host feitas como root).

| Campo | Contêiner A (`so3_ns_a`) | Contêiner B (`so3_ns_b`) |
|---|---|---|
| `PID_host` (docker inspect) | 43568 | 43625 |
| Processo pai no host | 43543 `containerd-shim-runc-v2` | 43601 `containerd-shim-runc-v2` |
| `/proc/1/comm` interno | `sleep` | `sleep` |
| `NSpid` no host (`/proc/<PID>/status`) | `43568 1` | `43625 1` |
| Processos visíveis dentro | `1 sleep`, `39 sh` (o próprio `docker exec`) | `1 sleep`, `39 sh` |
| Interfaces de rede visíveis | apenas `lo` | apenas `lo` |
| Raiz `/` (`/proc/1/mountinfo`) | `overlay`, mount ID 1650, `upperdir=…/snapshots/73` | `overlay`, mount ID 1818, `upperdir=…/snapshots/75` |

### Rascunho da tabela comparativa (Integrante 3 revisa)

| Recurso | Handle em A | Handle em B | Host (namespace inicial) | A × B | Interpretação |
|---|---|---|---|---|---|
| PID | `pid:[4026532577]` | `pid:[4026533042]` | `pid:[4026531836]` | Diferentes | Cada contêiner tem a própria árvore de PIDs. Dentro dele só aparecem os seus processos, numerados a partir de 1. |
| mount | `mnt:[4026532554]` | `mnt:[4026533039]` | `mnt:[4026531832]` | Diferentes | Cada contêiner tem a própria tabela de montagens. O `mountinfo` mostra raízes `overlay` distintas. |
| network | `net:[4026532579]` | `net:[4026533044]` | `net:[4026531833]` | Diferentes | Pilhas de rede separadas. Com `--network none`, cada uma só tem `lo`. |

- A coluna "Host" vem do **PID 1 do host (`systemd`)**, lido como root. O shell que rodou o script tem exatamente os mesmos
  handles, ou seja, ambos estão no namespace inicial.
- **Ligação dentro × fora (verificada):** para cada contêiner e cada tipo, `readlink /proc/<PID_host>/ns/<tipo>` no host, como root,
  deu o **mesmo** handle que `readlink /proc/1/ns/<tipo>` dentro do contêiner (6 de 6 marcados `IGUAL` no log).
  O `lsns` do host lista cada um desses namespaces com 1 processo, o respectivo `sleep 600`.
- Os números entre colchetes são inodes no `nsfs`. Dois processos estão no mesmo namespace **se e somente se** o handle é igual
  (namespaces(7)). O kernel **reutiliza** esses números depois que um namespace é destruído. Por isso `mnt:[4026532554]`
  aparece também na coleta 1, cujos contêineres já tinham sido removidos. A comparação só vale entre processos vivos ao mesmo tempo.

### O que o `mountinfo` mostra (e o que não mostra)

- **Observado:** a raiz de cada contêiner é um `overlay`. As camadas inferiores `snapshots/56–59` (a imagem) são as
  **mesmas** nos dois, e são somente leitura. Cada um tem a **própria** camada gravável (`upperdir` 73 × 75) e a própria
  camada de init (72 × 74). Ou seja, a imagem é compartilhada em disco, mas a escrita de um não vai para o outro.
- **Observado:** `/sys` e `/sys/fs/cgroup` são montados `ro`. `/proc/sys`, `/proc/sysrq-trigger` etc. são `ro`, e
  `/proc/kcore`, `/proc/keys` etc. são mascarados com `/dev/null`. É material útil para a parte de segurança (Integrante 5).
- **Não testado:** não foi feita montagem nova dentro de um contêiner para ver se ela aparece no outro. Com `--cap-drop ALL`
  não há `CAP_SYS_ADMIN`, então isso não é possível sem enfraquecer o teste. Fica como mecanismo descrito em namespaces(7)/mount_namespaces(7),
  não como observação.

### Coleta anterior (preservada)

[`../evidencias/namespaces_coleta1.txt`](../evidencias/namespaces_coleta1.txt) (09/11/2026) foi feita **sem root**. Nela não
foi possível ler `/proc/<PID>/ns/*` de fora, o `lsns` saiu vazio, o processo pai não foi identificado e os valores do
"host" eram os do shell. Os resultados qualitativos são os mesmos (handles diferentes, PID 1 em ambos, `NSpid` X→1).
Ela foi substituída como coleta oficial pela versão com root, seguindo a revisão do Integrante 3.

## 4. PID 1 em ambos: dados para a explicação

- Dentro de A e dentro de B, `/proc/1/comm = sleep`. **Os dois contêineres têm um PID 1.**
- São processos **distintos** no kernel: no host, o PID 1 de A é **43568** e o de B é **43625**. Cada um é filho do seu
  próprio `containerd-shim-runc-v2` (43543 e 43601), que é o processo que o runtime deixa como “pai” do contêiner.
- A linha `NSpid: 43568 1` do `/proc/43568/status` é a prova direta: o **mesmo processo** tem PID 43568 no namespace PID do host
  e PID 1 no namespace PID filho. Um namespace PID novo começa a numeração em 1. O primeiro processo criado nele (o `init` do
  namespace) recebe o 1, mas continua tendo um PID no namespace pai.
- Os handles `pid:[…]` diferentes, confirmados de dentro e de fora, mostram que A e B estão em namespaces PID distintos.
  Por isso o número 1 pode se repetir sem conflito.
- O `sh` com PID 39 é o processo criado pelo `docker exec`, que entra (`setns`) no namespace já existente.
- Como o host do daemon é o próprio Linux nativo, foi possível conferir o PID do inspect no `/proc` do terminal.
  Em Docker Desktop ou WSL2 com daemon em outra VM, essa verificação não seria válida.

**O que essa evidência não prova:** não prova isolamento de segurança absoluto. Os contêineres compartilham o kernel, e uma
falha no kernel ou no runtime pode ultrapassar namespaces. Também não diz nada sobre limite de consumo (isso é cgroup)
nem sobre privilégios (usuário, capabilities, AppArmor/seccomp). Namespaces mudam o que o processo **vê**.
**Escopo:** esta evidência é do ambiente Linux nativo. Não vale como observação do ambiente WSL2 das Partes C/D.

## 5. Reprodução

```bash
bash scripts/coleta_ambiente.sh     # Parte A: gera evidencias/ambiente.txt, imagem_digest.txt, controladores.txt
sudo -v && bash scripts/coleta_namespaces.sh   # Parte B (rodar no terminal; sudo só para LER /proc de outros processos)
```

Os scripts só leem `/proc` e `/sys`. `coleta_namespaces.sh` cria apenas `so3_ns_a` e `so3_ns_b` e os remove ao sair (`trap EXIT`).
O script se recusa a sobrescrever `evidencias/namespaces.txt`: renomeie a coleta anterior antes. Os handles e PIDs mudam a cada execução. Os valores acima são os desta coleta.
Limpeza manual, se interrompido: `docker rm -f so3_ns_a so3_ns_b`.
