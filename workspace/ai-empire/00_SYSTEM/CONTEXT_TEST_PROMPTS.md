# Context Sync Test-Prompts

> Diese Prompts testen, ob der persistente Kontext korrekt funktioniert.
> In OpenClaw oder einem Agent eingeben.

---

## Test 1: Yesterday Recall

```
What did I work on yesterday? Use CONTEXT_SNAPSHOT.md.
```

**Erwartung:** Agent liest `shared-context/CONTEXT_SNAPSHOT.md` und gibt die
"Yesterday" Bullets zurück. Keine Halluzinationen.

---

## Test 2: Automation Candidates

```
What repetitive stuff should I automate next? Use CONTEXT_SNAPSHOT.md.
```

**Erwartung:** Agent liest "Repetitive Tasks Candidates" Sektion und schlägt
konkrete Automatisierungen vor.

---

## Test 3: Manual Refresh

```
Refresh context now.
```

**Erwartung:** Agent führt `context_sync.py` aus und bestätigt dass
`CONTEXT_SNAPSHOT.md` aktualisiert wurde.

**Mac-Kommando für manuellen Refresh:**

```bash
Mac: python3 ~/.openclaw/workspace/ai-empire/automation/context_sync.py
```

---

## Test 4: Snapshot Existenz

```bash
Mac: cat ~/.openclaw/workspace/ai-empire/shared-context/CONTEXT_SNAPSHOT.md
```

**Erwartung:** Datei existiert, hat aktuellen Timestamp, enthält keine Secrets.

---

## Test 5: Scheduler aktiv

```bash
Mac: launchctl list | grep ai.empire
```

**Erwartung:** `ai.empire.contextsync.hourly` ist gelistet mit PID oder Status 0.
