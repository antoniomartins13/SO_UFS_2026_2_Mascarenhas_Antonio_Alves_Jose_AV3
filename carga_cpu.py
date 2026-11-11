#!/usr/bin/env python3
"""Carga determinística de CPU com trabalho fixo e correção verificável.

Trabalho: acc = sum(i*i for i in range(N)) mod P, com P = 2**61 - 1, em laço
Python puro (um único thread). O resultado é conferido com a forma fechada
N(N-1)(2N-1)/6 mod P, de modo que cada execução prova ter feito o trabalho todo.

Limite interno de segurança: aborta (status "timeout") após LIMITE_S segundos.
Saída: uma linha JSON em stdout.
"""
import json
import os
import resource
import sys
import time

P = (1 << 61) - 1
LIMITE_S = 60.0
BLOCO = 1_000_000  # verifica o tempo a cada BLOCO iterações


def vmrss_kb():
    try:
        with open("/proc/self/status") as f:
            for linha in f:
                if linha.startswith("VmRSS:"):
                    return int(linha.split()[1])
    except OSError:
        pass
    return None


def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else int(os.environ.get("ITERACOES", "20000000"))
    esperado = ((n - 1) * n * (2 * n - 1) // 6) % P

    t0_wall = time.perf_counter()
    t0_cpu = time.process_time()
    acc = 0
    i = 0
    status = "ok"
    while i < n:
        fim = min(i + BLOCO, n)
        for j in range(i, fim):
            acc = (acc + j * j) % P
        i = fim
        if time.perf_counter() - t0_wall > LIMITE_S:
            status = "timeout"
            break
    wall = time.perf_counter() - t0_wall
    cpu = time.process_time() - t0_cpu

    correto = (status == "ok" and acc == esperado)
    if status == "ok" and not correto:
        status = "checksum_incorreto"

    print(json.dumps({
        "iteracoes": n,
        "iteracoes_concluidas": i,
        "checksum": acc,
        "checksum_esperado": esperado,
        "correto": correto,
        "status": status,
        "wall_s": round(wall, 6),
        "cpu_processo_s": round(cpu, 6),
        "rss_pico_processo_kb": resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,
        "vmrss_final_kb": vmrss_kb(),
    }))
    return 0 if correto else 1


if __name__ == "__main__":
    sys.exit(main())
