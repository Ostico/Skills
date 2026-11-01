#!/usr/bin/env python3
"""How much context window a local Ollama model can get on this Mac right now.

Usage: ctx_budget.py MODEL [--margin-gib 4] [--buffers-gib 1.5] [--parallel 1]

Reads the memory in use now (vm_stat), the model's weight size and its attention shape from
the Ollama API, and prints the largest context that fits for an f16 and a q8_0 KV cache.
Close or open the apps you will keep running before you measure: the number is only as good as
the snapshot. If MODEL is already loaded, its memory is already counted as used; unload it first
(`ollama stop MODEL`).

The KV figure is an upper bound: models with sliding-window or hybrid attention use less.
"""
import argparse
import json
import re
import subprocess
import sys
import urllib.request

GIB = 1024 ** 3
OLLAMA = "http://127.0.0.1:11434"


def api(path: str, body: dict | None = None) -> dict:
    """POST (or GET when body is None) to the local Ollama API and decode the JSON reply."""
    data = None if body is None else json.dumps(body).encode()
    with urllib.request.urlopen(urllib.request.Request(OLLAMA + path, data=data), timeout=10) as r:
        return json.load(r)


def used_gib() -> float:
    """Memory in use on macOS: app (anonymous minus purgeable) + wired + compressor pages."""
    out = subprocess.run(["vm_stat"], capture_output=True, text=True, check=True).stdout

    def number(pattern: str) -> int:
        m = re.search(pattern, out)
        if m is None:
            raise SystemExit(f"vm_stat has no match for {pattern!r}; this script reads macOS memory only")
        return int(m.group(1))

    page = number(r"page size of (\d+)")

    def pages(label: str) -> int:
        return number(rf"{label}:\s+(\d+)")

    used = pages("Anonymous pages") - pages("Pages purgeable") + pages("Pages wired down")
    used += pages("Pages occupied by compressor")
    return used * page / GIB


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("model")
    ap.add_argument("--margin-gib", type=float, default=4.0, help="kept free for macOS")
    ap.add_argument("--buffers-gib", type=float, default=1.5, help="compute buffers")
    ap.add_argument("--parallel", type=int, default=1, help="OLLAMA_NUM_PARALLEL")
    a = ap.parse_args()

    total = int(subprocess.run(["sysctl", "-n", "hw.memsize"], capture_output=True, text=True).stdout) / GIB
    loaded = [m["name"] for m in api("/api/ps").get("models", [])]
    tags = {m["name"]: m["size"] for m in api("/api/tags")["models"]}
    name = a.model if a.model in tags else f"{a.model}:latest"
    if name not in tags:
        print(f"model {a.model} not found in ollama list", file=sys.stderr)
        return 2
    info = api("/api/show", {"model": name})["model_info"]
    arch = info["general.architecture"]
    layers = info[f"{arch}.block_count"]
    kv_heads = info[f"{arch}.attention.head_count_kv"]
    # Hybrid models (linear-attention or SSM layers) list KV heads per layer, 0 where a layer
    # keeps no KV cache; the per-token cost is then the sum over layers.
    kv_layer_heads = sum(kv_heads) if isinstance(kv_heads, list) else layers * kv_heads
    k_len = info.get(f"{arch}.attention.key_length") or info[f"{arch}.embedding_length"] // info[f"{arch}.attention.head_count"]
    v_len = info.get(f"{arch}.attention.value_length") or k_len
    max_ctx = info.get(f"{arch}.context_length", 0)
    sliding = any("sliding_window" in k for k in info)

    per_tok_f16 = kv_layer_heads * (k_len + v_len) * 2 * a.parallel
    weights = tags[name] / GIB
    used = used_gib()
    free = total - used - a.margin_gib - weights - a.buffers_gib

    print(f"total {total:.1f} GiB, in use now {used:.1f} GiB, margin {a.margin_gib} GiB")
    print(f"model {name}: weights {weights:.1f} GiB + buffers {a.buffers_gib} GiB; trained context {max_ctx}")
    print(f"KV per token (f16, parallel {a.parallel}): {per_tok_f16 / 1024:.0f} KiB")
    if any(m.split(":")[0] == name.split(":")[0] for m in loaded):
        print("WARNING: this model is loaded now, so its memory is counted twice; unload it and measure again")
    if sliding:
        print("NOTE: sliding-window attention; the real KV is smaller than this upper bound")
    print(f"free for the KV cache: {free:.1f} GiB")
    if free <= 0:
        print("no room: close apps or pick a smaller model")
        return 1
    for label, per_tok in (("f16", per_tok_f16), ("q8_0", per_tok_f16 / 2)):
        fit = int(free * GIB / per_tok) // 4096 * 4096
        if max_ctx:
            fit = min(fit, max_ctx)
        print(f"max context with a {label} KV cache: {fit}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
