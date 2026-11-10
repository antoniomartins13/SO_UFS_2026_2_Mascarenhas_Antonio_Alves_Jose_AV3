# Namespaces: tabela comparativa e explicação do PID 1

Atividade 3 de Sistemas Operacionais 2026.2 (UFS) · Parte B · Integrante 3

Dados da coleta oficial de 10/11/2026 (`evidencias/namespaces.txt`), feita em Linux nativo (Ubuntu 26.04.1, kernel `7.0.0-43-generic`, sem VM), com leituras do host como root. Contêineres `so3_ns_a` e `so3_ns_b`, mesma imagem (`python@sha256:5e2bdb1b…4fa5b`), criados com `--network none --cap-drop ALL --security-opt no-new-privileges` e comando `sleep 600`.

## 1. Tabela comparativa dos três namespaces

| Recurso | Handle em A | Handle em B | Host (namespace inicial) | A × B | Interpretação |
|---|---|---|---|---|---|
| PID | `pid:[4026532577]` | `pid:[4026533042]` | `pid:[4026531836]` | Diferentes | Cada contêiner tem a própria árvore de PIDs. Dentro dele só aparecem os seus processos (`1 sleep` e `39 sh`), numerados a partir de 1. |
| mount | `mnt:[4026532554]` | `mnt:[4026533039]` | `mnt:[4026531832]` | Diferentes | Cada contêiner tem a própria tabela de montagens. O `/proc/1/mountinfo` mostra raízes `overlay` distintas (seção 3). |
| network | `net:[4026532579]` | `net:[4026533044]` | `net:[4026531833]` | Diferentes | Pilhas de rede separadas. Com `--network none`, cada uma só tem a interface `lo`, com contadores zerados. |

Como ler a tabela:

- Os números entre colchetes são inodes no `nsfs`. Pela namespaces(7), dois processos estão no mesmo namespace se e somente se o handle é igual. Aqui todos diferem entre A, B e o host.
- A coluna do host vem do PID 1 do host (`systemd`), lido como root. O shell que executou o script tem exatamente os mesmos handles, o que confirma que ambos estão no namespace inicial.
- **Ligação entre dentro e fora (verificada).** Para cada contêiner e cada tipo, `readlink /proc/<PID_host>/ns/<tipo>` no host deu o mesmo handle que `readlink /proc/1/ns/<tipo>` dentro do contêiner (6 de 6 marcados `IGUAL` no log). O `lsns` do host lista cada um desses namespaces com 1 processo, o respectivo `sleep 600`.
- **Reuso de números.** O kernel reutiliza o número do inode depois que um namespace é destruído. Por isso `mnt:[4026532554]` também aparece na coleta anterior (09/11/2026), cujos contêineres já tinham sido removidos. Não é erro de cópia, e a comparação só vale entre processos vivos ao mesmo tempo.

## 2. Por que os dois contêineres têm PID 1

Dentro de `so3_ns_a` e de `so3_ns_b`, `/proc/1/comm` retorna `sleep`. Os dois contêineres têm um "PID 1", mas não são o mesmo processo. No host, o PID 1 de A é o 43568 e o de B é o 43625. Cada um é filho do seu próprio `containerd-shim-runc-v2` (43543 e 43601), o processo que o runtime deixa como pai do contêiner.

A linha `NSpid: 43568 1` em `/proc/43568/status` é a prova direta. O mesmo processo tem dois números: 43568 no namespace PID do host e 1 no namespace PID do contêiner. Um namespace PID novo reinicia a numeração, e o primeiro processo criado nele é o `init` daquele namespace, mas continua existindo no namespace pai com um PID próprio. O contêiner B segue a mesma lógica (`NSpid: 43625 1`).

Os handles `pid:[4026532577]` e `pid:[4026533042]` são diferentes, e isso foi confirmado de dentro e de fora. Por isso o número 1 se repete sem conflito: a unicidade do PID vale dentro de cada namespace, não no kernel inteiro. O `sh` de PID 39 é o processo criado pelo `docker exec`, que entra (`setns`) no namespace já existente.

Como o daemon roda no próprio Linux nativo, o PID informado pelo `docker inspect` pôde ser conferido no `/proc` do terminal. Em Docker Desktop ou WSL2 com daemon em outra VM, essa verificação não seria válida.

## 3. O que o `mountinfo` mostra

**Observado:**

- A raiz de cada contêiner é um `overlay` (mount ID 1650 em A e 1818 em B).
- As camadas inferiores `snapshots/56`, `57`, `58` e `59` (a imagem) são as mesmas nos dois e são somente leitura.
- Cada contêiner tem a própria camada gravável: `upperdir` 73 em A e 75 em B. A primeira camada inferior também difere (72 em A, 74 em B), provavelmente a camada de init criada pelo Docker, o que o log não confirma.
- Em consequência, a imagem é compartilhada em disco, mas o que um contêiner escreve não vai para o outro.

**Não testado:** não foi feita uma montagem nova dentro de um contêiner para verificar se ela aparece no outro. Com `--cap-drop ALL` não há `CAP_SYS_ADMIN`, então isso não é possível sem enfraquecer o teste. A separação de montagens entre namespaces fica como mecanismo descrito em namespaces(7) e mount_namespaces(7), não como observação.

## 4. O que a evidência não demonstra

Handles diferentes provam que os namespaces são distintos, ou seja, que a visão de PIDs, mounts e rede é separada. Eles não provam:

- isolamento de segurança absoluto, porque os contêineres compartilham o kernel do host e uma falha no kernel ou no runtime pode ultrapassar os namespaces;
- limite de consumo de recursos, que é função dos cgroups (Parte C);
- restrição de privilégios, que depende de identidade, capabilities, AppArmor e seccomp. Aqui `--cap-drop ALL` e `no-new-privileges` foram usados, mas isso é independente dos namespaces.

Em uma frase: namespaces mudam o que o processo vê, e cgroups, identidade e políticas de acesso mudam o que ele pode consumir e fazer.

**Escopo.** Esta evidência vale para o ambiente Linux nativo das Partes A e B. Os experimentos de cgroups (Partes C e D) foram feitos em WSL2 e não devem ser tratados como observação do mesmo ambiente.

## Fontes

- Dados brutos: `evidencias/namespaces.txt` (coleta oficial, 10/11/2026) e `evidencias/namespaces_coleta1.txt` (coleta anterior, sem root, preservada).
- Linux man-pages. *namespaces(7)*. https://man7.org/linux/man-pages/man7/namespaces.7.html
- Linux man-pages. *mount_namespaces(7)*. https://man7.org/linux/man-pages/man7/mount_namespaces.7.html
