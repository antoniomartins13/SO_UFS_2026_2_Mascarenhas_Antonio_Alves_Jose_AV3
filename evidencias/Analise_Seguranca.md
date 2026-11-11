# Atividade 3 — Sistemas Operacionais
## Contribuição do Integrante 5: kernel compartilhado, throttling, montagem read-only e segurança em inferência

### 1. Kernel compartilhado e isolamento

Os contêineres Docker compartilham o kernel do ambiente Linux em que o daemon é executado. Diferentemente de máquinas virtuais convencionais, eles não possuem um kernel próprio para cada instância. No experimento, o daemon Docker Engine 29.1.3 foi executado no Ubuntu 24.04.5 LTS sob WSL2, utilizando o kernel `6.18.54.1-microsoft-standard-WSL2`. Portanto, os contêineres compartilham o kernel Linux da VM WSL2, e não diretamente o kernel Windows.

Os **namespaces** isolam a visão de processos, montagens e rede; os **cgroups v2** limitam o consumo de recursos; a **identidade do usuário e as políticas de acesso** determinam o que o processo pode fazer. Esses mecanismos são complementares, mas nenhum transforma o contêiner em uma VM independente. Vulnerabilidades de kernel ou runtime ainda podem afetar outros contêineres e o host do daemon.

### 2. Throttling e interpretação da Parte C

A condição C1 utilizou a quota `cpu.max = 50000 100000`, equivalente a até 50 ms de tempo agregado de CPU a cada período de 100 ms (0,5 CPU). A condição C2 utilizou `cpu.max = 100000 100000`, equivalente a 1,0 CPU. A quota não fixa afinidade em um núcleo nem reserva uma CPU física: ela limita o tempo de execução consumível por período.

Em C1, a carga CPU-bound de uma thread atingiu a quota repetidamente. Os registros indicam throttling em todos os períodos observados (159/159, 162/162 e 162/162 nas três repetições). O processo consumiu aproximadamente 8 segundos de CPU em cerca de 16 segundos de tempo de parede. Em termos práticos, pôde executar por uma parte do período e foi suspenso temporariamente ao esgotar a quota. Em C2, não houve throttling (`nr_throttled = 0` nas três repetições), pois uma thread não ultrapassou a quota de uma CPU completa.

| Indicador | C1 — 0,5 CPU | C2 — 1,0 CPU |
|---|---:|---:|
| Mediana de trabalho (milhões de iterações/s) | 6,22 | 11,86 |
| Tempo de parede mediano (s) | 16,07 | 8,43 |
| Coeficiente de variação | 1,05% | 10,52% |
| Períodos com throttling na repetição mediana | 162 | 0 |

A razão entre as medianas foi de **1,91**, próxima, mas não idêntica, a duas vezes. Em C2, uma das execuções foi mais lenta (9,85 milhões de iterações/s) mesmo sem throttling, o que indica que outros fatores podem ter influenciado a medição. Frequência/turbo, competição por recursos e atividades do Windows sobre WSL2 são hipóteses plausíveis, não causas comprovadas isoladamente. A interpretação deve considerar que foram apenas três repetições por condição e uma única carga Python de uma thread.

### 3. Montagem somente leitura — análise da Parte D

Foi criado um diretório de teste sintético, `dados_demo`, com `texto.txt` contendo `Documento sintetico`, disponibilizado dentro do contêiner em `/dados` como bind mount `ro`. A execução principal utilizou usuário sem privilégios (`uid=65534`, nobody), remoção de todas as capabilities (`--cap-drop ALL`), bloqueio de novos privilégios (`--security-opt no-new-privileges`), root filesystem read-only (`--read-only`) e rede desabilitada (`--network none`). Os logs mostram `CapEff=0`, `CapBnd=0`, `NoNewPrivs=1` e `Seccomp=2`.

| Caso | Identidade | Montagem | Leitura | Tentativa de criar arquivo | Interpretação |
|---|---|---|---|---|---|
| D1 | nobody (UID 65534) | `/dados:ro` | Sucesso | Negada: `EROFS` (errno 30) | Ponto de montagem somente leitura |
| D2 | root (UID 0), sem capabilities | `/dados:ro` | Sucesso | Negada: `EROFS` (errno 30) | Nem root pode escrever através do mount ro |
| D3 | nobody (UID 65534) | `/dados:rw` em cópia sintética | Sucesso | Negada: `EACCES` (errno 13) | Permissões DAC do diretório impedem a escrita |

A comparação demonstra duas razões distintas para a negação. **`EROFS`** indica que o VFS bloqueou a operação pelo caráter somente leitura do ponto de montagem. **`EACCES`** indica que o ponto de montagem permitia escrita, mas as permissões associadas ao usuário e ao diretório não a autorizavam. O `mountinfo` também confirmou que `/dados` estava `ro` em D1/D2, embora o sistema de arquivos ext4 no host continuasse `rw`. Os registros do host e o hash SHA-256 permaneceram iguais antes e depois das tentativas, sem criação de arquivos.

O **mount namespace** controla quais montagens o contêiner enxerga, mas não é sinônimo de montagem somente leitura. A opção `ro` impõe a restrição de integridade; as permissões DAC usam UID/GID e modos dos arquivos; **capabilities**, **no-new-privileges** e **seccomp** reduzem operações privilegiadas. Neste ambiente, o perfil seccomp estava ativo, mas **AppArmor e SELinux não estavam presentes/ativos no kernel WSL2**, de modo que não foi possível observar sua contribuição.

### 4. Segurança em infraestrutura compartilhada de inferência

Em um servidor de inferência compartilhado, quotas de CPU ajudam a evitar que uma execução monopolize o processador. `memory.max` ajuda a conter consumo excessivo de RAM e seus efeitos no grupo; `pids.max` limita a proliferação de processos ou threads. No teste de CPU, os dois contêineres tinham `memory.max = 256 MiB`, `memory.swap.max = 0` e `pids.max = 64`. Não foram observados eventos de OOM nem atingimento do limite de tarefas. Esses limites não eliminam a interferência entre cargas por cache, memória compartilhada ou outros componentes físicos.

Montar o corpus, o diretório de modelos ou os pesos de redes neurais como **read-only** ajuda a impedir alterações acidentais ou maliciosas por meio daquele ponto de montagem, protegendo a integridade de artefatos compartilhados. A medida, porém, **não protege confidencialidade**: dados legíveis ainda podem ser copiados. Também não impede falhas no kernel, ataques por caminhos adicionais de acesso aos mesmos arquivos, nem controla automaticamente a memória de GPU (**VRAM**). O princípio de menor privilégio recomenda liberar apenas os arquivos, redes e operações necessários para cada serviço.

### 5. Riscos e limitações

O experimento ocorreu em WSL2, introduzindo uma camada de VM cujo desempenho é influenciado pelo sistema Windows hospedeiro. Não houve fixação de frequência nem isolamento de núcleos. A amostra incluiu três execuções por condição e uma carga sintética CPU-bound, single-thread, em Python: os resultados não devem ser extrapolados como desempenho de geração de tokens ou de inferência com GPU. O Docker Engine era rootful, e não havia AppArmor/SELinux ativos no kernel; essas características limitam a avaliação da segurança. Os registros podem expor caminhos locais do host e devem ser revisados antes da publicação.

### 6. Conclusão

Os dados sustentam que a quota de 0,5 CPU causou throttling e reduziu a taxa de trabalho, enquanto a quota de 1,0 CPU permitiu throughput mediano 1,91 vez maior sem throttling. A Parte D confirmou leitura permitida e escrita bloqueada no bind mount read-only, inclusive para root sem capabilities, distinguindo esse mecanismo das permissões de usuário. Assim, cgroups, namespaces e controles de privilégio cumprem funções complementares na operação de contêineres; não fornecem isolamento absoluto nem eliminam os riscos associados ao kernel e aos recursos físicos compartilhados.

### Referências

- Linux Kernel Documentation. *Control Group v2*. https://docs.kernel.org/admin-guide/cgroup-v2.html
- Linux man-pages. *namespaces(7)*. https://man7.org/linux/man-pages/man7/namespaces.7.html
- Docker Docs. *Resource constraints*. https://docs.docker.com/engine/containers/resource_constraints/
- Docker Docs. *Bind mounts*. https://docs.docker.com/engine/storage/bind-mounts/
- Evidências locais do grupo: `resultados/principal/C1_r*.json`, `C2_r*.json`, `resultados/execucoes.csv`, `resultados/resumo.md`, `resultados/parte_d/D1_nobody_ro.log`, `D2_root_capdrop_ro.log`, `D3_nobody_rw_controle.log`.

**Contribuição individual sugerida para a tabela do relatório:** Análise da Parte D e interpretação das evidências de montagem somente leitura e permissões; redação da fundamentação sobre kernel compartilhado, CPU throttling, segurança e riscos remanescentes em infraestrutura de inferência.

**Declaração de IA referente a esta seção:** Texto preliminar estruturado com auxílio do ChatGPT (OpenAI) a partir do enunciado e de logs reais fornecidos pela equipe. Dados numéricos e conclusões experimentais conferidos com `README_partes_C_D.md`, resumo e registros D1–D3. A equipe deve revisar criticamente a redação e incluir esse auxílio na declaração geral de uso de IA.
