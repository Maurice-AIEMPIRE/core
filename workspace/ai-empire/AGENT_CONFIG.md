# AI Empire — Agent Configuration

> Zentrales Dokument für alle Agent-Konfigurationen und Startup-Routinen.

---

## Agent Startup Routine (Amnesia OFF)

Jeder Agent führt beim Start diese Schritte aus — in dieser Reihenfolge:

### 1. Identität laden

```
Read USER.md
```

Enthält: Wer ist der User, Präferenzen, Grenzen.

### 2. Kontext laden

```
Read shared-context/CONTEXT_SNAPSHOT.md
```

Enthält: Was gestern/heute passiert ist, wiederkehrende Tasks, nächste Aktionen.

### 3. Tages-Memory laden

```
Read memory/<YYYY-MM-DD>.md  (heute)
Read memory/<YYYY-MM-DD>.md  (gestern, falls vorhanden)
```

Enthält: Detaillierte Notizen, Entscheidungen, Erkenntnisse.

### 4. Fallback: Snapshot fehlt

Wenn `CONTEXT_SNAPSHOT.md` nicht existiert oder älter als 2h:

```bash
python3 automation/context_sync.py
```

Dann erneut laden.

---

## Regeln für alle Agents

1. **Keine neuen Identitäten/Personas erstellen.** Du bist ein Assistent.
2. **Keine Secrets in Output.** Keys immer als `<REDACTED>`.
3. **Local-first.** Kein Upload privater Daten an externe Dienste.
4. **Kontext nutzen.** Vor jeder Antwort CONTEXT_SNAPSHOT.md konsultieren.
5. **Kurz und präzise.** Keine Floskeln, kein Marketing.

---

## Agent-Typen

### Standard Agent (Default)

- **Modell:** `ollama/qwen3:8b`
- **Thinking:** `minimal`
- **Kontext-Quellen:** USER.md, CONTEXT_SNAPSHOT.md, Tages-Memory
- **Einsatz:** Alltags-Chat, Quick Questions, WhatsApp Replies

### DeepWork Agent

- **Modell:** `ollama/qwen3:32b` (oder bestes verfügbares)
- **Thinking:** `high`
- **Kontext-Quellen:** Alle + relevante Projektdateien
- **Einsatz:** Code Review, Architektur, komplexe Analyse
- **Aktivierung:** `deepwork-on` / `deepwork-off` (siehe PERFORMANCE_PROFILE.md)

### Context Sync Agent (Automatisch)

- **Trigger:** Stündlich via launchd
- **Script:** `automation/context_sync.py`
- **Output:** `shared-context/CONTEXT_SNAPSHOT.md`
- **Kein User-Interaction nötig**

---

## Verzeichnisstruktur

```
~/.openclaw/workspace/ai-empire/
├── AGENTS.md                          ← Diese Datei
├── USER.md                            ← User-Profil (manuell pflegen)
├── 00_SYSTEM/
│   ├── DIAG_OPENCLAW_*.md             ← Diagnose-Reports
│   ├── OPENCLAW_RESTART_SOP.md        ← Restart-Anleitung
│   ├── PERFORMANCE_PROFILE.md         ← Modell-Konfiguration
│   └── CONTEXT_TEST_PROMPTS.md        ← Test-Prompts für Context Sync
├── automation/
│   ├── context_sync.py                ← Stündlicher Context Sync
│   └── ai.empire.contextsync.hourly.plist ← launchd Scheduler
├── memory/
│   └── <YYYY-MM-DD>.md               ← Tages-Notizen (manuell/automatisch)
└── shared-context/
    └── CONTEXT_SNAPSHOT.md            ← Automatisch generiert
```

---

## Startup-Befehl (für Agent-System-Prompt)

```
Bei jedem Start:
1. Lies USER.md — Wer bin ich, was sind meine Präferenzen?
2. Lies shared-context/CONTEXT_SNAPSHOT.md — Was ist der aktuelle Kontext?
3. Lies memory/<heute>.md und memory/<gestern>.md — Detaillierte Tages-Notizen.
4. Falls Snapshot fehlt oder >2h alt: Führe automation/context_sync.py aus.
5. Antworte basierend auf diesem Kontext. Kein Raten. Kein Marketing.
```
