# Atividade 3 SO — Namespaces: tabela comparativa e explicação do PID 1

Parte do Integrante 3 · Sistemas Operacionais 2026.2 (UFS) · Dados da coleta do Integrante 1, em 09/11/2026

## Tabela comparativa dos handles (Parte B)

Handles lidos com `docker exec NOME readlink /proc/1/ns/{pid,mnt,net}`, em Linux nativo (sem VM), com os contêineres `so3_ns_a` e `so3_ns_b`.

| Recurso | Handle em A (`so3_ns_a`) | Handle em B (`so3_ns_b`) | Host (namespace inicial) | Iguais? | Interpretação |
|---|---|---|---|---|---|
| PID | `pid:[4026532569]` | `pid:[4026533035]` | `pid:[4026531836]` | Diferentes | Três árvores de PIDs distintas. Cada contêiner só enxerga os próprios processos (`1 sleep` e `39 sh`) e a numeração começa em 1. |
| mount | `mnt:[4026532554]` | `mnt:[4026533032]` | `mnt:[4026531832]` | Diferentes | Cada contêiner tem sua própria tabela de montagens. Uma montagem feita em um não aparece no outro nem no host. |
| network | `net:[4026532571]` | `net:[4026533037]` | `net:[4026531833]` | Diferentes | Cada contêiner tem sua própria pilha de rede. Com `--network none`, cada um só tem `lo`, com contadores zerados, e nenhuma interface em comum com o host. |

Pela namespaces(7), dois processos estão no mesmo namespace se e somente se o handle (número de inode no `nsfs`) é idêntico. Aqui todos diferem, então A, B e o host estão em namespaces PID, mount e network distintos.

## Explicação do PID 1

Dentro de `so3_ns_a` e de `so3_ns_b`, `/proc/1/comm` retorna `sleep`. Os dois contêineres têm um "PID 1", mas não são o mesmo processo. O PID 1 de cada um é um processo diferente do kernel: no host, o de A é o PID 10474 e o de B é o PID 10529, ambos `sleep 600` com usuário root.

A linha `NSpid: 10474 1` em `/proc/10474/status` mostra isso diretamente. O mesmo processo tem dois números: 10474 no namespace PID do host e 1 no namespace PID do contêiner. Um namespace PID novo reinicia a numeração, e o primeiro processo criado nele é o `init` daquele namespace, mas continua existindo no namespace pai com um PID "real". O B segue a mesma lógica (`NSpid: 10529 1`).

Os handles `pid:[4026532569]` e `pid:[4026533035]` são diferentes. Por isso o número 1 se repete sem conflito: a unicidade do PID vale dentro de cada namespace, não no kernel inteiro. O `sh` de PID 39 é o processo do `docker exec`, que entrou no namespace já existente. Esse número é alto porque os PIDs do namespace avançam a cada processo criado nele, inclusive nos `exec` anteriores da coleta.

## O que a evidência não demonstra

Handles diferentes provam que os namespaces são distintos, ou seja, que a visão de PIDs, mounts e rede é separada. Eles não provam:

- isolamento de segurança absoluto, porque os contêineres compartilham o kernel do host e uma falha no kernel ou no runtime pode ultrapassar os namespaces;
- limite de consumo de recursos, que é função dos cgroups (Parte C);
- restrição de privilégios, que depende de identidade, capabilities, AppArmor e seccomp. Aqui `--cap-drop ALL` e `no-new-privileges` foram usados, mas isso é independente dos namespaces.

Em uma frase: namespaces mudam o que o processo vê, e cgroups, identidade e políticas de acesso mudam o que ele pode consumir e fazer.

## Fontes

- Dados brutos: `evidencias/namespaces.txt` e `docs/partes_A_B.md` do repositório da equipe.
- Linux man-pages. *namespaces(7)*. https://man7.org/linux/man-pages/man7/namespaces.7.html
