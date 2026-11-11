#!/usr/bin/env python3
"""Executado DENTRO do contêiner. Lê a interface cgroup v2 do próprio contêiner
(/sys/fs/cgroup, visível graças ao cgroup namespace privado), roda carga_cpu.py,
amostra memory.current durante a execução e emite um JSON com valores antes,
depois e deltas. Apenas LEITURA de /sys; nada é escrito em /sys.
"""
import json
import os
import subprocess
import sys
import threading
import time

CG = "/sys/fs/cgroup"
ARQ_SIMPLES = ["cpu.max", "cpu.weight", "memory.max", "memory.swap.max",
               "memory.high", "pids.max", "memory.current", "memory.peak",
               "pids.current", "pids.peak", "cgroup.controllers"]


def ler(nome):
    try:
        with open(os.path.join(CG, nome)) as f:
            return f.read().strip()
    except OSError as e:
        return f"<indisponivel: {e.strerror}>"


def ler_kv(nome):
    txt = ler(nome)
    if txt.startswith("<"):
        return {}
    out = {}
    for linha in txt.splitlines():
        k, v = linha.split()
        out[k] = int(v)
    return out


def instantaneo():
    return {
        "arquivos": {n: ler(n) for n in ARQ_SIMPLES},
        "cpu.stat": ler_kv("cpu.stat"),
        "memory.events": ler_kv("memory.events"),
        "pids.events": ler_kv("pids.events"),
    }


def main():
    n = sys.argv[1]
    antes = instantaneo()

    amostras = []
    parar = threading.Event()

    def amostrador():
        while not parar.is_set():
            v = ler("memory.current")
            if v.isdigit():
                amostras.append(int(v))
            parar.wait(0.2)

    th = threading.Thread(target=amostrador, daemon=True)
    th.start()
    t0 = time.perf_counter()
    proc = subprocess.run([sys.executable, "-B", "/lab/carga_cpu.py", n],
                          capture_output=True, text=True)
    wall_externo = time.perf_counter() - t0
    parar.set()
    th.join()
    depois = instantaneo()

    try:
        carga = json.loads(proc.stdout.strip().splitlines()[-1])
    except (IndexError, json.JSONDecodeError):
        carga = {"status": "saida_invalida", "stdout": proc.stdout}

    sa, sd = antes["cpu.stat"], depois["cpu.stat"]
    delta = {k: sd[k] - sa[k] for k in sd if k in sa}

    print(json.dumps({
        "carga": carga,
        "carga_exit_code": proc.returncode,
        "carga_stderr": proc.stderr[-2000:],
        "wall_externo_s": round(wall_externo, 6),
        "cgroup_antes": antes,
        "cgroup_depois": depois,
        "cpu_stat_delta": delta,
        "memory_current_amostras": {
            "n": len(amostras),
            "min_bytes": min(amostras) if amostras else None,
            "max_bytes": max(amostras) if amostras else None,
            "media_bytes": int(sum(amostras) / len(amostras)) if amostras else None,
            "intervalo_s": 0.2,
        },
        "identidade": {"uid": os.getuid(), "gid": os.getgid()},
    }, indent=2))
    return proc.returncode


if __name__ == "__main__":
    sys.exit(main())
