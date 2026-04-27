# Maintenance checklist

The vault is plain markdown — it doesn't rot mechanically, but signal does.
Run these on schedule to keep the AI's memory honest.

## Weekly (Sunday)

- [ ] **Inbox sweep** — every file in `inbox/` either gets classified into
      `vault/`, `people/`, `work/`, `personal/` or deleted. Inbox should
      end the week empty.
- [ ] **Orphan review** — open `vault/ORPHANS.md` (refreshed Sunday 22:00).
      For each orphan, decide: link from a relevant page, archive, or
      delete.
- [ ] **Daily note pass** — skim Mon–Sun daily notes. Anything that became
      a stable fact gets promoted to `vault/`. Anything that became a
      recurring workflow gets a `vault/SKILLS/<name>.md`.
- [ ] **Hot-memory check** — run `scripts/promote-to-vault.sh`. If over
      67%, ask the AI to compact per the protocol in `system-prompt.md`.

## Monthly (1st)

- [ ] **Project pass** — for every section in `vault/PROJECTS.md`, confirm
      `last touched` is within 30 days. Archive dormant projects.
- [ ] **Person pass** — for every file in `people/`, check the last
      backlink date. Archive contacts you haven't engaged in 90 days.
- [ ] **Troubleshooting digest** — read `vault/TROUBLESHOOTING.md`. Promote
      patterns (e.g. "this fix has fired 3 times") to a skill file.
- [ ] **USER.md audit** — re-read top to bottom. Stale entries get edited
      or deleted. The AI uses this every turn; don't let it drift.
- [ ] **Backup** — push the vault to your private git remote (or zip and
      upload to wherever cold storage lives).

## Quarterly

- [ ] **Graph review** — open Obsidian's graph view. Disconnected clusters
      mean the routing rules aren't working. Add backlinks or rethink the
      taxonomy.
- [ ] **Skills cull** — read every file in `vault/SKILLS/`. Skills not
      invoked in 90 days get archived.
- [ ] **System prompt review** — re-read `system-prompt.md`. If the AI
      has been getting routing wrong in a consistent way, update the
      prompt rather than re-correcting the AI weekly.

## When you switch AI providers

The vault is the source of truth. To migrate:

1. Point the new provider at `system-prompt.md`.
2. Inject `MEMORY.md` + `USER.md` on every turn (same contract).
3. Confirm it can read/write the vault folder.
4. No data migration required — the markdown is the data.
