# SO_UFS_2026_2 — Atividade 3

**Virtualização, contêineres, namespaces e cgroups**

Universidade Federal de Sergipe, Departamento de Computação.
Sistemas Operacionais, Turma 02, 2026.2. Docente: Glauco de Figueiredo Carneiro.

Pergunta norteadora: *como namespaces alteram a visão de processos, mounts e rede, e como cgroups limitam recursos
sem transformar um contêiner em uma máquina virtual independente?*

Entrega: 10/11/2026 · Apresentação: 11/11/2026

---

## 1. Equipe e contribuições

| # | Integrante | Contribuição |
|---|---|---|
| 1 | Antônio José Martins Mascarenhas | Ambiente Docker, diagrama de infraestrutura, coleta dos namespaces (Partes A e B), criação do repositório |
| 2 | Anderson Soares de Santana Júnior | Testes de cgroups com carga de CPU, montagem read-only e logs brutos (Partes C e D) |
| 3 | Antônio Carlos Bispo Cunha | Tabela comparativa de handles e explicação do PID 1 |
| 4 | Kaíque Teixeira Rodrigues | Processamento dos logs de cgroups, trabalho/s e gráfico comparativo |
| 5 | José Gustavo Abreu Alves | Análise do teste de montagem; teoria de kernel compartilhado, throttling e segurança em inferência |
| 6 | João Felipe Tunes Oliveira | Relatório PDF, README e declaração de uso de IA |
| 7 | Davi Oliveira Machado | Vídeo da equipe e slides |

Equipe (a mesma das atividades anteriores): Antônio José Martins Mascarenhas, José Gustavo Abreu Alves,
Davi Oliveira Machado, Antônio Carlos Bispo Cunha, Kaique Teixeira Rodrigues,
Anderson Soares de Santana Júnior, João Felipe Tunes Oliveira.

## 2. Vídeo

**URL:** <https://youtu.be/LrUAWQ2_1Oc> Também deve constar em [`VIDEO.md`](VIDEO.md) e no relatório.

## 3. Status dos entregáveis

| Item | Onde | Status |
|---|---|---|
| Ambiente, cgroup v2 e digest da imagem (Parte A) | [`evidencias/ambiente.txt`](evidencias/ambiente.txt), [`evidencias/controladores.txt`](evidencias/controladores.txt), [`evidencias/imagem_digest.txt`](evidencias/imagem_digest.txt) | ✅ |
| Diagrama de camadas | [`diagrama/infraestrutura.png`](diagrama/infraestrutura.png) (fonte `.svg`) | ✅ |
| Namespaces PID/mnt/net em dois contêineres (Parte B) | [`evidencias/namespaces.txt`](evidencias/namespaces.txt) (coleta 1 preservada em `namespaces_coleta1.txt`), [`docs/partes_A_B.md`](docs/partes_A_B.md) | ✅ coleta · ⏳ tabela final (Integrante 3) |
| Seis execuções C1/C2 + piloto (Parte C) | `resultados/` | ✅ |
| CSV e gráfico | `resultados/execucoes.csv`, gráfico | ✅ |
| Teste read-only (Parte D) | `evidencias/` |✅ |
| Relatório PDF | `docs/relatorio.pdf` | ✅ |
| Slides | `docs/apresentacao.pdf` | ✅ |
| Vídeo | [`VIDEO.md`](VIDEO.md) | ✅ |

## 4. Ambientes

A coleta usou **dois ambientes Linux**. O diagrama mostra ambos:

| | Partes A e B | Partes C e D |
|---|---|---|
| Host do daemon | Linux nativo (sem VM) | VM WSL2 sobre Windows/Hyper-V |
| Distribuição / kernel | Ubuntu 26.04.1 LTS / `7.0.0-43-generic` | Ubuntu 24.04.5 LTS / `6.18.54.1-microsoft-standard-WSL2` |
| CPUs lógicas / RAM | 8 / 15 GiB | 12 / 13 GiB |
| Docker | 29.9.3 rootful, Compose v5.7.0 | 29.1.3 rootful (nativo na distro) |
| cgroup | v2, driver systemd | v2, driver systemd |

**Imagem (a mesma nos dois):** `python:3.12-slim` fixada por digest:

```
python@sha256:5e2bdb1b0d542d5039cffb8181c65930093949194a65c365dfb1b0fe13a4fa5b
```

## 5. Reprodução

Pré-requisitos: Linux (ou WSL2) com Docker Engine e cgroup v2. Internet apenas no primeiro `docker pull`.

```bash
git clone https://github.com/antoniomartins13/SO_UFS_2026_2_Mascarenhas_Antonio_Alves_Jose_AV3.git
cd SO_UFS_2026_2_Mascarenhas_Antonio_Alves_Jose_AV3

# Parte A: ambiente, digest e limites vistos dentro do contêiner
bash scripts/coleta_ambiente.sh
export IMAGEM_LAB="$(cat evidencias/imagem_digest.txt)"

# Parte B: dois contêineres, handles de pid/mnt/net
sudo -v && bash scripts/coleta_namespaces.sh   # sudo só para LER /proc de outros processos
```

Partes C e D: _a documentar pelo Integrante 2_.

**Limpeza:** os scripts removem os contêineres que criam. Se algo for interrompido:
`docker rm -f so3_ns_a so3_ns_b`. Não use `docker system prune -a`.

## 6. Estrutura

```
scripts/      coleta_ambiente.sh, coleta_namespaces.sh (+ scripts das Partes C/D)
evidencias/   logs brutos (ambiente, controladores, digest, namespaces, read-only)
diagrama/     infraestrutura.svg / .png
docs/         partes_A_B.md, relatório, slides, declaração de IA
resultados/   logs das 6 execuções, CSV e gráfico (Parte C)
```

## 7. Referências

- Linux man-pages. *namespaces(7)*. <https://man7.org/linux/man-pages/man7/namespaces.7.html>
- Linux Kernel Documentation. *Control Group v2*. <https://docs.kernel.org/admin-guide/cgroup-v2.html>
- Docker. *Resource constraints*. <https://docs.docker.com/engine/containers/resource_constraints/>
