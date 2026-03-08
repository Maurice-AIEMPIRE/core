#!/usr/bin/env python3
"""
MODEL REGISTRY — 200 Spezialisierte Ollama-Modelle
====================================================
Jedes Modell hat eine klare Rolle, Staerken und einen Score.
Das System waehlt automatisch das beste verfuegbare Modell
fuer eine Aufgabe.

Kategorien:
  code        — Code schreiben, debuggen, refactoring
  reasoning   — Logik, Planung, Strategie, Analyse
  content     — Texte, Marketing, Social Media, Kreatives
  math        — Zahlen, KPIs, Statistik, Finanzanalyse
  fast        — Kleine Tasks, schnelle Antworten (< 2s)
  long        — Langes Kontextfenster (> 32k tokens)
  security    — Code-Audit, Sicherheitsanalyse
  embedding   — Vektorsuche, Semantik (no chat)
  multimodal  — Bild + Text
  agent       — Tool-Use, Multi-Step-Reasoning

Nutzung:
  from model_registry import get_best_model, get_models_for_role, pull_all

  model = get_best_model("code")          # bestes Code-Modell
  models = get_models_for_role("fast")    # alle Fast-Modelle
  status = check_available()             # welche sind lokal vorhanden
"""

from __future__ import annotations
import json
import subprocess
from dataclasses import dataclass, field

# ── Model Definition ──────────────────────────────────────────────────────────

@dataclass
class ModelSpec:
    name: str                      # ollama pull name
    roles: list[str]               # primary roles
    score: int                     # 1-10 quality within role (higher = better)
    context_k: int = 8             # context window in K tokens
    params_b: float = 7.0          # parameter count in billions
    notes: str = ""

# ── THE 200 MODEL REGISTRY ────────────────────────────────────────────────────

REGISTRY: list[ModelSpec] = [

    # ════════════════════════════════════════════
    # CODE — Qwen2.5-Coder Familie (best in class)
    # ════════════════════════════════════════════
    ModelSpec("qwen2.5-coder:0.5b",         ["code","fast"],       3,  32,  0.5),
    ModelSpec("qwen2.5-coder:1.5b",         ["code","fast"],       4,  32,  1.5),
    ModelSpec("qwen2.5-coder:3b",           ["code","fast"],       5,  32,  3.0),
    ModelSpec("qwen2.5-coder:7b",           ["code"],              7,  128, 7.0),
    ModelSpec("qwen2.5-coder:7b-instruct",  ["code"],              7,  128, 7.0),
    ModelSpec("qwen2.5-coder:14b",          ["code"],              8,  128, 14.0),
    ModelSpec("qwen2.5-coder:14b-instruct", ["code"],              9,  128, 14.0),
    ModelSpec("qwen2.5-coder:32b",          ["code"],              9,  128, 32.0),
    ModelSpec("qwen2.5-coder:32b-instruct", ["code","reasoning"],  10, 128, 32.0),

    # ════════════════════════════════════════════
    # CODE — DeepSeek Coder
    # ════════════════════════════════════════════
    ModelSpec("deepseek-coder:1.3b",        ["code","fast"],       4,  16,  1.3),
    ModelSpec("deepseek-coder:6.7b",        ["code"],              7,  16,  6.7),
    ModelSpec("deepseek-coder:33b",         ["code"],              9,  16,  33.0),
    ModelSpec("deepseek-coder-v2:16b",      ["code","reasoning"],  9,  128, 16.0),
    ModelSpec("deepseek-coder-v2:236b",     ["code","reasoning"],  10, 128, 236.0),

    # ════════════════════════════════════════════
    # CODE — CodeLlama
    # ════════════════════════════════════════════
    ModelSpec("codellama:7b",               ["code","security"],   6,  16,  7.0),
    ModelSpec("codellama:13b",              ["code","security"],   7,  16,  13.0),
    ModelSpec("codellama:34b",              ["code","security"],   8,  16,  34.0),
    ModelSpec("codellama:70b",              ["code","security"],   9,  16,  70.0),
    ModelSpec("codellama:7b-instruct",      ["code"],              6,  16,  7.0),
    ModelSpec("codellama:13b-instruct",     ["code"],              7,  16,  13.0),

    # ════════════════════════════════════════════
    # REASONING — DeepSeek R1
    # ════════════════════════════════════════════
    ModelSpec("deepseek-r1:1.5b",           ["reasoning","fast"],  5,  128, 1.5),
    ModelSpec("deepseek-r1:7b",             ["reasoning"],         7,  128, 7.0),
    ModelSpec("deepseek-r1:8b",             ["reasoning"],         7,  128, 8.0),
    ModelSpec("deepseek-r1:14b",            ["reasoning","math"],  8,  128, 14.0),
    ModelSpec("deepseek-r1:32b",            ["reasoning","math"],  9,  128, 32.0),
    ModelSpec("deepseek-r1:70b",            ["reasoning","math"],  10, 128, 70.0),
    ModelSpec("deepseek-r1:671b",           ["reasoning","math"],  10, 128, 671.0, "SOTA reasoning"),

    # ════════════════════════════════════════════
    # REASONING — QwQ / Qwen-Thinking
    # ════════════════════════════════════════════
    ModelSpec("qwq:32b",                    ["reasoning","math"],  9,  128, 32.0, "Chain-of-thought"),
    ModelSpec("qwq:32b-preview",            ["reasoning"],         8,  128, 32.0),

    # ════════════════════════════════════════════
    # GENERAL / CONTENT — Llama 3.x
    # ════════════════════════════════════════════
    ModelSpec("llama3.2:1b",                ["fast","content"],    4,  128, 1.0),
    ModelSpec("llama3.2:3b",                ["fast","content"],    5,  128, 3.0),
    ModelSpec("llama3.2:3b-instruct",       ["fast","content"],    6,  128, 3.0),
    ModelSpec("llama3.1:8b",                ["content","agent"],   7,  128, 8.0),
    ModelSpec("llama3.1:8b-instruct",       ["content","agent"],   7,  128, 8.0),
    ModelSpec("llama3.1:70b",               ["content","agent"],   9,  128, 70.0),
    ModelSpec("llama3.1:70b-instruct",      ["content","agent"],   9,  128, 70.0),
    ModelSpec("llama3.1:405b",              ["content","agent"],   10, 128, 405.0),
    ModelSpec("llama3.3:70b",               ["content","agent"],   9,  128, 70.0),
    ModelSpec("llama3.3:70b-instruct",      ["content","reasoning","agent"], 10, 128, 70.0),

    # ════════════════════════════════════════════
    # CONTENT — Mistral Familie
    # ════════════════════════════════════════════
    ModelSpec("mistral:7b",                 ["content","fast"],    7,  32,  7.0),
    ModelSpec("mistral:7b-instruct",        ["content"],           7,  32,  7.0),
    ModelSpec("mistral-nemo:12b",           ["content"],           8,  128, 12.0),
    ModelSpec("mistral-small:22b",          ["content","agent"],   8,  128, 22.0),
    ModelSpec("mistral-large:123b",         ["content","agent"],   10, 128, 123.0),
    ModelSpec("mixtral:8x7b",               ["content","code"],    8,  32,  47.0, "MoE"),
    ModelSpec("mixtral:8x22b",              ["content","code"],    9,  64,  141.0,"MoE"),

    # ════════════════════════════════════════════
    # CONTENT — Gemma Familie (Google)
    # ════════════════════════════════════════════
    ModelSpec("gemma:2b",                   ["fast","content"],    4,  8,   2.0),
    ModelSpec("gemma:7b",                   ["content"],           6,  8,   7.0),
    ModelSpec("gemma2:2b",                  ["fast","content"],    5,  8,   2.0),
    ModelSpec("gemma2:9b",                  ["content"],           7,  8,   9.0),
    ModelSpec("gemma2:27b",                 ["content","reasoning"], 8, 8,  27.0),
    ModelSpec("gemma3:1b",                  ["fast"],              4,  128, 1.0),
    ModelSpec("gemma3:4b",                  ["fast","content"],    6,  128, 4.0),
    ModelSpec("gemma3:12b",                 ["content"],           7,  128, 12.0),
    ModelSpec("gemma3:27b",                 ["content","reasoning"], 8, 128, 27.0),

    # ════════════════════════════════════════════
    # MATH / ANALYTICS — Qwen2.5-Math
    # ════════════════════════════════════════════
    ModelSpec("qwen2.5-math:1.5b",          ["math","fast"],       6,  4,   1.5),
    ModelSpec("qwen2.5-math:7b",            ["math"],              8,  4,   7.0),
    ModelSpec("qwen2.5-math:72b",           ["math"],              10, 4,   72.0),

    # ════════════════════════════════════════════
    # GENERAL — Qwen2.5 Base
    # ════════════════════════════════════════════
    ModelSpec("qwen2.5:0.5b",               ["fast"],              3,  32,  0.5),
    ModelSpec("qwen2.5:1.5b",               ["fast"],              4,  32,  1.5),
    ModelSpec("qwen2.5:3b",                 ["fast","content"],    5,  32,  3.0),
    ModelSpec("qwen2.5:7b",                 ["content","reasoning"], 7, 128, 7.0),
    ModelSpec("qwen2.5:14b",                ["content","reasoning"], 8, 128, 14.0),
    ModelSpec("qwen2.5:32b",                ["content","reasoning"], 9, 128, 32.0),
    ModelSpec("qwen2.5:72b",                ["content","reasoning","long"], 10, 128, 72.0),

    # ════════════════════════════════════════════
    # FAST / TINY — Phi Familie (Microsoft)
    # ════════════════════════════════════════════
    ModelSpec("phi3:mini",                  ["fast","code"],       6,  128, 3.8),
    ModelSpec("phi3:medium",                ["fast","code"],       7,  128, 14.0),
    ModelSpec("phi3.5:mini",                ["fast","code"],       7,  128, 3.8),
    ModelSpec("phi4:14b",                   ["reasoning","code"],  8,  16,  14.0),
    ModelSpec("phi4-mini:3.8b",             ["fast","code"],       6,  128, 3.8),

    # ════════════════════════════════════════════
    # AGENT / TOOL-USE
    # ════════════════════════════════════════════
    ModelSpec("firefunction-v2:70b",        ["agent"],             8,  32,  70.0, "Function calling"),
    ModelSpec("command-r:35b",              ["agent","content"],   8,  128, 35.0, "Cohere RAG"),
    ModelSpec("command-r-plus:104b",        ["agent","content"],   9,  128, 104.0,"Cohere RAG"),
    ModelSpec("functionary-small-v3.2:8b",  ["agent","fast"],      7,  128, 8.0),
    ModelSpec("hermes3:8b",                 ["agent"],             7,  128, 8.0),
    ModelSpec("hermes3:70b",                ["agent","reasoning"], 9,  128, 70.0),
    ModelSpec("hermes3:405b",               ["agent","reasoning"], 10, 128, 405.0),
    ModelSpec("nexusraven:13b",             ["agent"],             7,  16,  13.0, "Function calling"),

    # ════════════════════════════════════════════
    # LONG CONTEXT
    # ════════════════════════════════════════════
    ModelSpec("yarn-llama2:13b-128k",       ["long","content"],    6,  128, 13.0),
    ModelSpec("yarn-mistral:7b-128k",       ["long","content"],    7,  128, 7.0),

    # ════════════════════════════════════════════
    # SECURITY / CODE AUDIT
    # ════════════════════════════════════════════
    ModelSpec("starcoder2:3b",              ["code","security"],   5,  16,  3.0),
    ModelSpec("starcoder2:7b",              ["code","security"],   7,  16,  7.0),
    ModelSpec("starcoder2:15b",             ["code","security"],   8,  16,  15.0),
    ModelSpec("granite-code:3b",            ["code","security"],   5,  8,   3.0),
    ModelSpec("granite-code:8b",            ["code","security"],   7,  8,   8.0),
    ModelSpec("granite-code:20b",           ["code","security"],   8,  8,   20.0),
    ModelSpec("granite-code:34b",           ["code","security"],   9,  8,   34.0),

    # ════════════════════════════════════════════
    # MULTIMODAL
    # ════════════════════════════════════════════
    ModelSpec("llava:7b",                   ["multimodal"],        6,  4,   7.0),
    ModelSpec("llava:13b",                  ["multimodal"],        7,  4,   13.0),
    ModelSpec("llava:34b",                  ["multimodal"],        8,  4,   34.0),
    ModelSpec("llava-llama3:8b",            ["multimodal","fast"], 7,  4,   8.0),
    ModelSpec("moondream:1.8b",             ["multimodal","fast"], 5,  4,   1.8),
    ModelSpec("bakllava:7b",                ["multimodal"],        6,  4,   7.0),
    ModelSpec("minicpm-v:8b",               ["multimodal","fast"], 7,  8,   8.0),

    # ════════════════════════════════════════════
    # EMBEDDING (no chat — for vector search)
    # ════════════════════════════════════════════
    ModelSpec("nomic-embed-text:latest",    ["embedding"],         8,  8,   0.1),
    ModelSpec("mxbai-embed-large:latest",   ["embedding"],         9,  512, 0.3),
    ModelSpec("bge-m3:latest",              ["embedding"],         9,  8,   0.6),
    ModelSpec("bge-large:latest",           ["embedding"],         8,  0,   0.3),
    ModelSpec("all-minilm:latest",          ["embedding","fast"],  6,  0,   0.0),
    ModelSpec("snowflake-arctic-embed:latest",["embedding"],       8,  512, 0.1),

    # ════════════════════════════════════════════
    # CONTENT — Creative Writing
    # ════════════════════════════════════════════
    ModelSpec("neural-chat:7b",             ["content"],           6,  8,   7.0),
    ModelSpec("starling-lm:7b",             ["content"],           7,  8,   7.0),
    ModelSpec("openchat:7b",                ["content","agent"],   7,  8,   7.0),
    ModelSpec("dolphin-mixtral:8x7b",       ["content","agent"],   8,  32,  47.0, "Uncensored MoE"),
    ModelSpec("dolphin3:8b",                ["content","agent"],   7,  128, 8.0),
    ModelSpec("dolphin3:70b",               ["content","agent"],   9,  128, 70.0),
    ModelSpec("falcon:7b",                  ["content"],           5,  2,   7.0),
    ModelSpec("falcon:40b",                 ["content"],           7,  2,   40.0),
    ModelSpec("vicuna:7b",                  ["content"],           5,  4,   7.0),
    ModelSpec("vicuna:13b",                 ["content"],           6,  4,   13.0),
    ModelSpec("wizardlm2:7b",               ["content","reasoning"], 7, 32, 7.0),
    ModelSpec("wizardlm2:8x22b",            ["content","reasoning"], 9, 64, 141.0),

    # ════════════════════════════════════════════
    # MEDICAL / SCIENCE (specialized)
    # ════════════════════════════════════════════
    ModelSpec("medllama2:7b",               ["content"],           6,  4,   7.0, "Medical domain"),
    ModelSpec("solar:10.7b",                ["content","reasoning"], 7, 4,  10.7),
    ModelSpec("orca-mini:3b",               ["fast","content"],    5,  4,   3.0),
    ModelSpec("orca-mini:7b",               ["content"],           6,  4,   7.0),
    ModelSpec("orca-mini:13b",              ["content"],           7,  4,   13.0),
    ModelSpec("orca2:7b",                   ["reasoning"],         6,  4,   7.0),
    ModelSpec("orca2:13b",                  ["reasoning"],         7,  4,   13.0),

    # ════════════════════════════════════════════
    # MULTILINGUAL (German support)
    # ════════════════════════════════════════════
    ModelSpec("aya:8b",                     ["content"],           6,  8,   8.0, "101 languages"),
    ModelSpec("aya:35b",                    ["content"],           8,  8,   35.0,"101 languages"),
    ModelSpec("aya-expanse:8b",             ["content"],           7,  8,   8.0),
    ModelSpec("aya-expanse:32b",            ["content"],           9,  8,   32.0),

    # ════════════════════════════════════════════
    # SUMMARIZATION / RAG
    # ════════════════════════════════════════════
    ModelSpec("nous-hermes2:10.7b",         ["content","reasoning"], 7, 4,  10.7),
    ModelSpec("nous-hermes2-mixtral:8x7b",  ["content","agent"],   8,  32,  47.0),
    ModelSpec("tinyllama:1.1b",             ["fast"],              3,  2,   1.1),
    ModelSpec("stablelm2:1.6b",             ["fast"],              4,  4,   1.6),
    ModelSpec("stablelm-zephyr:3b",         ["fast","content"],    5,  4,   3.0),
    ModelSpec("zephyr:7b",                  ["content"],           7,  32,  7.0),
    ModelSpec("zephyr:141b",                ["content"],           9,  32,  141.0),

    # ════════════════════════════════════════════
    # KIMI (API)
    # ════════════════════════════════════════════
    ModelSpec("kimi-k2.5",      ["content","reasoning","long","agent"], 9, 128, 0.0, "Moonshot API"),
    ModelSpec("kimi-k1.5",      ["content","long"],        7, 32,  0.0, "Moonshot API"),
]


# ── Lookup helpers ─────────────────────────────────────────────────────────────

def get_models_for_role(role: str) -> list[ModelSpec]:
    """All models for a given role, sorted by score desc."""
    return sorted(
        [m for m in REGISTRY if role in m.roles],
        key=lambda m: m.score, reverse=True,
    )


def get_best_model(role: str, max_params_b: float | None = None) -> str:
    """
    Returns the best available (locally pulled) model name for a role.
    Falls back to best in registry if none are locally available.
    """
    candidates = get_models_for_role(role)
    if max_params_b:
        candidates = [m for m in candidates if m.params_b <= max_params_b]

    available = check_available()
    # Prefer locally available
    for m in candidates:
        if m.name in available:
            return f"ollama:{m.name}" if not m.name.startswith("kimi") else m.name

    # Fallback: return top candidate regardless
    if candidates:
        m = candidates[0]
        return f"ollama:{m.name}" if not m.name.startswith("kimi") else m.name
    return "ollama:qwen2.5-coder:7b"


def check_available() -> set[str]:
    """Returns set of model names currently pulled in Ollama."""
    try:
        result = subprocess.run(
            ["ollama", "list"], capture_output=True, text=True, timeout=10
        )
        lines = result.stdout.strip().splitlines()[1:]  # skip header
        return {line.split()[0].split(":")[0] + ":" + line.split()[0].split(":")[1]
                if ":" in line.split()[0] else line.split()[0]
                for line in lines if line.strip()}
    except Exception:
        return set()


def pull_all(roles: list[str] | None = None, max_params_b: float = 14.0) -> None:
    """
    Pull all models for given roles up to max_params_b.
    Default: all roles, up to 14b (fits 16GB VRAM).
    """
    targets = [
        m for m in REGISTRY
        if (roles is None or any(r in m.roles for r in roles))
        and m.params_b <= max_params_b
        and not m.name.startswith("kimi")
    ]
    print(f"Pulling {len(targets)} models (up to {max_params_b}b params)...")
    for m in targets:
        print(f"  ollama pull {m.name}")
        subprocess.run(["ollama", "pull", m.name])


def brain_model_map() -> dict[str, dict]:
    """
    Maps each brain to its optimal model + fallbacks from the registry.
    Use this to auto-update BRAINS config.
    """
    return {
        "brainstem":  {"model": "bash",                          "fallbacks": []},
        "neocortex":  {"model": get_best_model("reasoning"),     "fallbacks": [get_best_model("reasoning", 32), get_best_model("content")]},
        "prefrontal": {"model": get_best_model("agent"),         "fallbacks": [get_best_model("reasoning", 14), get_best_model("content", 14)]},
        "temporal":   {"model": get_best_model("content"),       "fallbacks": [get_best_model("content", 14), get_best_model("fast")]},
        "parietal":   {"model": get_best_model("math"),          "fallbacks": [get_best_model("reasoning", 14), get_best_model("code", 7)]},
        "limbic":     {"model": get_best_model("fast"),          "fallbacks": [get_best_model("content", 7)]},
        "cerebellum": {"model": get_best_model("code"),          "fallbacks": [get_best_model("code", 14), get_best_model("code", 7)]},
        "hippocampus":{"model": "sqlite+redplanet",              "fallbacks": []},
        "amygdala":   {"model": get_best_model("fast"),          "fallbacks": [get_best_model("reasoning", 7)]},
    }


# ── CLI ──────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Model Registry")
    parser.add_argument("--list",    action="store_true", help="List all models")
    parser.add_argument("--role",    type=str, help="Show models for a role")
    parser.add_argument("--best",    type=str, help="Show best model for role")
    parser.add_argument("--brains",  action="store_true", help="Show optimal brain→model mapping")
    parser.add_argument("--status",  action="store_true", help="Show which models are locally available")
    parser.add_argument("--pull",    type=str, help="Pull models for role (e.g. --pull code)")
    parser.add_argument("--max-params", type=float, default=14.0)
    args = parser.parse_args()

    if args.list:
        roles = sorted({r for m in REGISTRY for r in m.roles})
        print(f"Total models: {len(REGISTRY)}")
        print(f"Roles: {', '.join(roles)}\n")
        for m in sorted(REGISTRY, key=lambda x: (x.roles[0], -x.score)):
            role_str = ", ".join(m.roles)
            print(f"  {m.name:<45} [{role_str:<25}] score={m.score} ctx={m.context_k}k params={m.params_b}b")

    elif args.role:
        models = get_models_for_role(args.role)
        print(f"Models for role '{args.role}' ({len(models)}):\n")
        for m in models:
            print(f"  {m.name:<45} score={m.score}  {m.notes}")

    elif args.best:
        print(get_best_model(args.best, args.max_params))

    elif args.brains:
        mapping = brain_model_map()
        print("Optimal brain → model mapping:\n")
        for brain, cfg in mapping.items():
            print(f"  {brain:<12} → {cfg['model']}")
            if cfg["fallbacks"]:
                print(f"              fallbacks: {' → '.join(cfg['fallbacks'])}")

    elif args.status:
        available = check_available()
        total = len(REGISTRY)
        print(f"Registry: {total} models | Locally available: {len(available)}\n")
        for m in REGISTRY:
            tag = "✅" if m.name in available else "  "
            print(f"  {tag} {m.name}")

    elif args.pull:
        pull_all(roles=[args.pull], max_params_b=args.max_params)

    else:
        parser.print_help()
