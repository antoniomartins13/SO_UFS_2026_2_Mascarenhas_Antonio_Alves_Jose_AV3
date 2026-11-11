# Atividade 3 — Sistemas Operacionais
## Integrante 4: processamento dos logs de cgroups, trabalho por segundo e gráfico comparativo


### 1. O que foi feito

A partir dos seis registros brutos válidos do Integrante 2 (`resultados/principal/C1_r{1,2,3}.json` e `C2_r{1,2,3}.json`), o script `resumo.py` extrai os campos de cada execução, calcula o trabalho concluído por segundo, consolida mediana e variação por condição e gera o gráfico comparativo.

Saídas geradas (todas em `resultados/`):

| Arquivo | Conteúdo |
|---|---|
| `execucoes.csv` | Uma linha por execução (6 linhas), com todas as métricas mínimas do enunciado |
| `resumo.csv` | Mediana, mínimo, máximo, amplitude e CV por condição |
| `resumo.md` | Mesma tabela consolidada em Markdown (para relatório e slides) |
| `grafico_c1_c2.png` | Gráfico comparativo C1 × C2 |

### 2. Como o trabalho por segundo foi calculado

Trabalho por segundo = `iteracoes ÷ wall_s`, em que `wall_s` é o tempo de parede medido ao redor da carga. Não é tokens/s: a unidade é iterações da carga sintética por segundo (apresentada em milhões, Mi iter/s). Só entram no resumo execuções com `correto = True`, isto é, com checksum igual ao esperado (`662921401752443440`, conferido pela forma fechada N(N−1)(2N−1)/6). As seis execuções são válidas, nenhuma foi descartada e nenhuma falhou.

Mediana e variação por condição (n = 3): a mediana é robusta a uma repetição atípica; o coeficiente de variação (CV) usa o desvio-padrão amostral dividido pela média; a amplitude relativa é (máx − mín) ÷ mediana.

### 3. Resultados

**Por execução** (N = 100.000.000 iterações; ordem real de execução: C1r1, C2r1, C2r2, C1r2, C1r3, C2r3):

| Exec. | Wall (s) | CPU proc. (s) | Mi iter/s | Δnr_periods | Δnr_throttled | Δthrottled (s) | memory.peak (MiB) |
|---|---:|---:|---:|---:|---:|---:|---:|
| C1 r1 | 15,79 | 7,87 | 6,33 | 159 | 159 | 7,96 | 17,9 |
| C1 r2 | 16,07 | 8,01 | 6,22 | 162 | 162 | 6,86 | 18,3 |
| C1 r3 | 16,09 | 8,02 | 6,22 | 162 | 162 | 6,89 | 18,2 |
| C2 r1 | 8,39 | 7,74 | 11,91 | 84 | 0 | 0,00 | 18,2 |
| C2 r2 | 8,43 | 7,78 | 11,86 | 85 | 0 | 0,00 | 18,5 |
| C2 r3 | 10,16 | 9,37 | 9,85 | 103 | 0 | 0,00 | 17,9 |

**Consolidado por condição:**

| Indicador | C1 (`cpu.max = 50000 100000`) | C2 (`cpu.max = 100000 100000`) |
|---|---:|---:|
| Repetições válidas | 3 | 3 |
| Mediana (Mi iter/s) | **6,22** | **11,86** |
| Mín–Máx (Mi iter/s) | 6,22–6,33 | 9,85–11,91 |
| Amplitude relativa | 1,90% | 17,45% |
| CV | 1,05% | 10,52% |
| Wall mediano (s) | 16,07 | 8,43 |
| CPU do processo mediana (s) | 8,01 | 7,78 |
| `nr_throttled` (mediana) | 162 | 0 |
| RSS de pico do processo (MiB) | 15,2 | 15,1 |
| `memory.peak` do cgroup (MiB) | 18,2 | 18,2 |

**Razão das medianas C2/C1 = 1,905.**

### 4. Gráfico

![Trabalho concluído por segundo sob quota de CPU](grafico_c1_c2.png)

*Figura 1 — Trabalho concluído por segundo sob quota de CPU (N = 100M iterações, n = 3 por condição). Barras: mediana; pontos: cada repetição.* O gráfico traz unidades no eixo y (milhões de iterações por segundo), o `cpu.max` de cada condição no eixo x e o número de repetições no título.

### 5. Leitura dos dados (para quem usar o gráfico)

- A mediana de C2 é 1,905 vez a de C1, próxima de 2, mas não idêntica; o enunciado diz que o resultado não precisa ter ganho exato de 2.
- C1 tem pontos praticamente sobrepostos (CV 1,05%); C2 tem um ponto abaixo dos demais (r3, 9,85 Mi iter/s) com o mesmo `nr_throttled = 0`. O tempo de CPU do processo também foi maior nessa repetição (9,37 s contra cerca de 7,8 s), o que indica fatores externos ao cgroup. A causa não foi isolada.
- O tempo de CPU por trabalho fixo é praticamente igual nas duas condições (cerca de 7,8 a 8,0 s), de modo que a quota altera quando o processo executa, e não quanto trabalho custa.

### 6. Verificação e reprodução

Para verificar que os resultados vêm dos registros brutos e não foram digitados, o `resumo.py` foi reexecutado em uma cópia limpa dos dados: `execucoes.csv`, `resumo.csv` e `resumo.md` saíram **byte a byte idênticos** aos entregues, e o gráfico foi regenerado com os mesmos valores. Também foi conferido que as seis execuções têm `correto = True` e o mesmo checksum.

```bash
# a partir da pasta atividade3/ (com resultados/principal/*.json)
python3 resumo.py          # requer Python 3 e, opcionalmente, matplotlib
```

O script lê `resultados/principal/C*_r*.json` e sobrescreve os quatro arquivos de saída em `resultados/`. Com outro diretório de registros brutos: `python3 resumo.py CAMINHO`. Sem matplotlib, os CSV e o Markdown são gerados e o gráfico é pulado.

### 7. Limitações

- Dados do ambiente WSL2 (Partes C e D), com host não controlado; n = 3 por condição e uma única carga sintética, single-thread, em Python.
- As medidas de memória (RSS do processo, `memory.current` amostrado e `memory.peak`) são distintas e não devem ser chamadas de "RAM média".
- O tempo de partida do interpretador e do `medir.py` entra no delta de `usage_usec` do cgroup, mas não no `wall_s` da carga.

### 8. Onde colocar os arquivos no repositório

O repositório atualizado ainda não contém as Partes C e D. Copie para `atividade3/` (ou para a raiz, conforme o README da equipe): `resumo.py` e a pasta `resultados/` com `principal/*.json`, `execucoes.csv`, `resumo.csv`, `resumo.md` e `grafico_c1_c2.png`; e atualize no README a linha da Parte C, que hoje consta como pendente.

### 9. Contribuição individual e IA

**Contribuição individual (para a tabela do relatório):** processamento dos logs de cgroups, cálculo do trabalho por segundo, consolidação (CSV e Markdown) e gráfico comparativo C1 × C2.

**Declaração de IA:** o script `resumo.py` foi escrito com auxílio do Claude Code (Anthropic), conforme o README das Partes C e D, e verificado por execução real. Nesta entrega, o Claude (Anthropic) foi usado para reexecutar o script, comparar as saídas com as entregues e redigir este documento; os números foram conferidos contra os JSON e o CSV. 
