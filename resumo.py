#!/usr/bin/env python3
"""Consolida os registros brutos de resultados/principal/*.json.

Gera:
  resultados/execucoes.csv   — uma linha por execução (6 linhas)
  resultados/resumo.csv      — mediana e variação por condição
  resultados/resumo.md       — mesma tabela em Markdown (para relatório/slides)
  resultados/grafico_c1_c2.png — trabalho/s por condição (barras = mediana,
                                 pontos = repetições, n=3)
Uso: python resumo.py [diretorio_brutos]
"""
import csv
import glob
import json
import os
import re
import statistics as st
import sys

DIR = os.path.dirname(os.path.abspath(__file__))
BRUTOS = sys.argv[1] if len(sys.argv) > 1 else os.path.join(DIR, "resultados", "principal")
OUT = os.path.join(DIR, "resultados")
MIB = 1024 * 1024


def linha(arq):
    cond, rep = re.match(r"(C\d)_r(\d+)\.json$", os.path.basename(arq)).groups()
    with open(arq) as f:
        d = json.load(f)
    c = d["carga"]
    a = d["cgroup_antes"]["arquivos"]
    dep = d["cgroup_depois"]["arquivos"]
    dl = d["cpu_stat_delta"]
    wall = c["wall_s"]
    return {
        "condicao": cond,
        "repeticao": int(rep),
        "iteracoes": c["iteracoes"],
        "checksum": c["checksum"],
        "correto": c["correto"],
        "status": c["status"],
        "wall_s": wall,
        "cpu_processo_s": c["cpu_processo_s"],
        "trabalho_por_s": c["iteracoes"] / wall,
        "cpu_max": a["cpu.max"],
        "memory_max": a["memory.max"],
        "memory_swap_max": a["memory.swap.max"],
        "pids_max": a["pids.max"],
        "usage_usec_delta": dl.get("usage_usec"),
        "nr_periods_delta": dl.get("nr_periods"),
        "nr_throttled_delta": dl.get("nr_throttled"),
        "throttled_usec_delta": dl.get("throttled_usec"),
        "rss_pico_processo_kib": c["rss_pico_processo_kb"],
        "memory_current_max_amostrado_bytes": d["memory_current_amostras"]["max_bytes"],
        "memory_peak_cgroup_bytes": dep["memory.peak"],
        "pids_peak": dep.get("pids.peak"),
    }


def main():
    arqs = sorted(glob.glob(os.path.join(BRUTOS, "C*_r*.json")))
    linhas = [linha(a) for a in arqs]
    linhas.sort(key=lambda r: (r["condicao"], r["repeticao"]))

    with open(os.path.join(OUT, "execucoes.csv"), "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(linhas[0].keys()))
        w.writeheader()
        w.writerows(linhas)

    resumo = []
    for cond in sorted({r["condicao"] for r in linhas}):
        rs = [r for r in linhas if r["condicao"] == cond and r["correto"]]
        tps = [r["trabalho_por_s"] for r in rs]
        walls = [r["wall_s"] for r in rs]
        med = st.median(tps)
        resumo.append({
            "condicao": cond,
            "cpu_max": rs[0]["cpu_max"],
            "n_validas": len(rs),
            "trabalho_por_s_mediana": med,
            "trabalho_por_s_min": min(tps),
            "trabalho_por_s_max": max(tps),
            "amplitude_rel_pct": 100 * (max(tps) - min(tps)) / med,
            "cv_pct": 100 * st.stdev(tps) / st.mean(tps) if len(tps) > 1 else 0.0,
            "wall_s_mediana": st.median(walls),
            "cpu_processo_s_mediana": st.median(r["cpu_processo_s"] for r in rs),
            "nr_throttled_mediana": st.median(r["nr_throttled_delta"] for r in rs),
            "throttled_s_mediana": st.median(r["throttled_usec_delta"] for r in rs) / 1e6,
            "rss_pico_mib_mediana": st.median(r["rss_pico_processo_kib"] for r in rs) / 1024,
            "memory_peak_mib_mediana": st.median(int(r["memory_peak_cgroup_bytes"]) for r in rs) / MIB,
        })

    with open(os.path.join(OUT, "resumo.csv"), "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(resumo[0].keys()))
        w.writeheader()
        w.writerows(resumo)

    r1 = {r["condicao"]: r for r in resumo}
    razao = r1["C2"]["trabalho_por_s_mediana"] / r1["C1"]["trabalho_por_s_mediana"] if {"C1", "C2"} <= r1.keys() else None

    md = ["| Condição | cpu.max | n | Mediana (Mi iter/s) | Mín–Máx (Mi iter/s) | CV (%) | Wall mediano (s) | CPU proc. mediano (s) | nr_throttled | throttled (s) | RSS pico (MiB) | memory.peak (MiB) |",
          "|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for r in resumo:
        md.append(f"| {r['condicao']} | `{r['cpu_max']}` | {r['n_validas']} | {r['trabalho_por_s_mediana']/1e6:.2f} | "
                  f"{r['trabalho_por_s_min']/1e6:.2f}–{r['trabalho_por_s_max']/1e6:.2f} | {r['cv_pct']:.2f} | "
                  f"{r['wall_s_mediana']:.2f} | {r['cpu_processo_s_mediana']:.2f} | {r['nr_throttled_mediana']:.0f} | "
                  f"{r['throttled_s_mediana']:.2f} | {r['rss_pico_mib_mediana']:.1f} | {r['memory_peak_mib_mediana']:.1f} |")
    if razao:
        md.append(f"\nRazão das medianas C2/C1 = {razao:.3f}")
    with open(os.path.join(OUT, "resumo.md"), "w") as f:
        f.write("\n".join(md) + "\n")
    print("\n".join(md))

    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError:
        print("matplotlib indisponível: gráfico não gerado")
        return

    fig, ax = plt.subplots(figsize=(6, 4.2), dpi=150)
    cores = {"C1": "#4C72B0", "C2": "#DD8452"}
    for i, r in enumerate(resumo):
        c = r["condicao"]
        ax.bar(i, r["trabalho_por_s_mediana"] / 1e6, width=0.55, color=cores.get(c, "gray"),
               alpha=0.75, label=f"{c} mediana")
        pts = [x["trabalho_por_s"] / 1e6 for x in linhas if x["condicao"] == c and x["correto"]]
        ax.scatter([i] * len(pts), pts, color="black", zorder=3, s=18,
                   label="repetições" if i == 0 else None)
        ax.text(i, max(pts) + 0.4, f"mediana {r['trabalho_por_s_mediana']/1e6:.2f}",
                ha="center", va="bottom", fontsize=9, fontweight="bold")
    ax.set_xticks(range(len(resumo)))
    ax.set_xticklabels([f"{r['condicao']}\ncpu.max={r['cpu_max']}" for r in resumo])
    ax.set_ylabel("Trabalho concluído (milhões de iterações/s)")
    n_iter = linhas[0]["iteracoes"]
    ax.set_title(f"Throughput sob quota de CPU (N={n_iter/1e6:.0f}M iterações, n=3 por condição)", fontsize=10)
    ax.set_ylim(0, max(x["trabalho_por_s"] for x in linhas) / 1e6 * 1.2)
    ax.legend(fontsize=8, loc="upper left")
    ax.grid(axis="y", alpha=0.3)
    fig.tight_layout()
    fig.savefig(os.path.join(OUT, "grafico_c1_c2.png"))
    print("gráfico: resultados/grafico_c1_c2.png")


if __name__ == "__main__":
    main()
