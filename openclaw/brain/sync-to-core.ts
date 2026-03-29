#!/usr/bin/env node
/**
 * OpenClaw Brain → CORE Memory Sync
 *
 * Reads all OpenClaw memory files and workspace docs,
 * pushes them into CORE as persistent memories.
 *
 * Run modes:
 *   node sync-to-core.js           — single sync run
 *   node sync-to-core.js --watch   — watch for file changes (inotifywait)
 *   node sync-to-core.js --daemon  — run every 15 minutes
 *
 * Required env:
 *   GALAXIA_BRAIN_URL    — CORE server URL
 *   GALAXIA_BRAIN_TOKEN  — CORE API token
 */

import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import { createHash } from "crypto";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, "../..");
const MEMORY_DIR = path.join(REPO_ROOT, "openclaw/memory");
const WORKSPACE_DIR = path.join(REPO_ROOT, "openclaw/workspace");

const CORE_URL = process.env.GALAXIA_BRAIN_URL ?? "http://localhost:3033";
const CORE_TOKEN = process.env.GALAXIA_BRAIN_TOKEN ?? "";

// Track last-synced content hashes to avoid duplicate ingestion
const STATE_FILE = path.join(REPO_ROOT, "openclaw/brain/.sync-state.json");

type SyncState = Record<string, string>; // filepath → contentHash

function loadState(): SyncState {
  try {
    return JSON.parse(fs.readFileSync(STATE_FILE, "utf-8"));
  } catch {
    return {};
  }
}

function saveState(state: SyncState): void {
  fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));
}

function hash(content: string): string {
  return createHash("sha256").update(content).digest("hex").slice(0, 16);
}

async function ingestToCore(
  content: string,
  title: string,
  sessionId: string,
  contentHash: string
): Promise<void> {
  if (!CORE_TOKEN) {
    console.error("[OpenClaw Brain] GALAXIA_BRAIN_TOKEN not set. Skipping.");
    return;
  }

  const body = {
    episodeBody: content,
    referenceTime: new Date().toISOString(),
    source: "openclaw",
    type: "DOCUMENT",
    title,
    sessionId,
    contentHash,
    metadata: {
      brain: "openclaw",
      repo: REPO_ROOT,
    },
  };

  const res = await fetch(`${CORE_URL}/api/v1/add`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${CORE_TOKEN}`,
    },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`CORE ingest failed ${res.status}: ${text}`);
  }

  const data = (await res.json()) as { id: string };
  console.log(`  ✓ Ingested [${title}] → queue:${data.id}`);
}

function readJsonAsMarkdown(filePath: string, label: string): string {
  try {
    const raw = fs.readFileSync(filePath, "utf-8");
    const data = JSON.parse(raw);
    return `# ${label}\n\n\`\`\`json\n${JSON.stringify(data, null, 2)}\n\`\`\``;
  } catch {
    return "";
  }
}

async function syncFile(
  filePath: string,
  title: string,
  sessionId: string,
  state: SyncState,
  isJson = false
): Promise<SyncState> {
  if (!fs.existsSync(filePath)) return state;

  const raw = isJson
    ? readJsonAsMarkdown(filePath, title)
    : fs.readFileSync(filePath, "utf-8").trim();

  if (!raw || raw.length < 20) return state;

  const contentHash = hash(raw);
  const relPath = path.relative(REPO_ROOT, filePath);

  if (state[relPath] === contentHash) {
    console.log(`  ~ Unchanged [${title}]`);
    return state;
  }

  await ingestToCore(raw, title, sessionId, contentHash);
  return { ...state, [relPath]: contentHash };
}

async function runSync(): Promise<void> {
  console.log("\n[OpenClaw Brain] Starting sync to CORE...");
  let state = loadState();
  const runId = `openclaw-${Date.now()}`;

  // --- Memory JSON Files ---
  const memoryFiles: Array<{ file: string; title: string; id: string }> = [
    {
      file: "agents-state.json",
      title: "OpenClaw: Agent States & Task History",
      id: `${runId}-agents`,
    },
    {
      file: "knowledge.json",
      title: "OpenClaw: Skill & Topic Knowledge Base",
      id: `${runId}-knowledge`,
    },
    {
      file: "discoveries.json",
      title: "OpenClaw: Dwight Research Discoveries",
      id: `${runId}-discoveries`,
    },
    {
      file: "revenue.json",
      title: "OpenClaw: Revenue Tracking & Goals",
      id: `${runId}-revenue`,
    },
  ];

  for (const { file, title, id } of memoryFiles) {
    const filePath = path.join(MEMORY_DIR, file);
    state = await syncFile(filePath, title, id, state, true);
  }

  // --- Workspace Markdown Files ---
  const workspaceFiles: Array<{ file: string; title: string; id: string }> = [
    {
      file: "GALAXIA_CORE.md",
      title: "Galaxia: System DNA & Agent Constitution",
      id: `${runId}-galaxia-core`,
    },
    {
      file: "SOUL.md",
      title: "Galaxia: Agent Identities & Soul Rules",
      id: `${runId}-soul`,
    },
    {
      file: "USER.md",
      title: "Galaxia: Maurice Pfeifer — User Profile",
      id: `${runId}-user`,
    },
    {
      file: "AGENTS.md",
      title: "Galaxia: Inner Circle Agent Specifications",
      id: `${runId}-agents-spec`,
    },
    {
      file: "TOOLS.md",
      title: "Galaxia: Available Tools Registry",
      id: `${runId}-tools`,
    },
    {
      file: "CONTEXT_SNAPSHOT.md",
      title: "Galaxia: Current System Context Snapshot",
      id: `${runId}-context`,
    },
  ];

  for (const { file, title, id } of workspaceFiles) {
    const filePath = path.join(WORKSPACE_DIR, file);
    state = await syncFile(filePath, title, id, state, false);
  }

  // --- Skills Brain (content-graph) ---
  const skillsDir = path.join(REPO_ROOT, "skills/content-graph");
  if (fs.existsSync(skillsDir)) {
    const skillFiles = fs
      .readdirSync(skillsDir, { recursive: true })
      .filter((f): f is string => typeof f === "string" && f.endsWith(".md"))
      .slice(0, 20); // cap at 20 skill files

    for (const skillFile of skillFiles) {
      const filePath = path.join(skillsDir, skillFile);
      const title = `Skill: ${skillFile.replace(/\//g, " / ").replace(".md", "")}`;
      state = await syncFile(filePath, title, `${runId}-skill-${skillFile}`, state, false);
    }
  }

  saveState(state);
  console.log("[OpenClaw Brain] Sync complete.\n");
}

async function main(): Promise<void> {
  const args = process.argv.slice(2);

  if (args.includes("--watch")) {
    // Watch mode: sync immediately, then watch for changes
    await runSync();
    console.log("[OpenClaw Brain] Watch mode: monitoring for file changes...");

    const { execSync } = await import("child_process");
    const watchPaths = [MEMORY_DIR, WORKSPACE_DIR].join(" ");

    try {
      // Use inotifywait if available (Linux)
      const cmd = `inotifywait -m -r -e modify,create,delete ${watchPaths}`;
      const child = execSync(cmd, { encoding: "utf-8" });
      console.log(child);
    } catch {
      // Fallback: poll every 5 minutes
      console.log("[OpenClaw Brain] inotifywait not available, falling back to 5min polling");
      setInterval(runSync, 5 * 60 * 1000);
    }
  } else if (args.includes("--daemon")) {
    // Daemon mode: sync every 15 minutes
    await runSync();
    setInterval(runSync, 15 * 60 * 1000);
    console.log("[OpenClaw Brain] Daemon mode: syncing every 15 minutes.");
  } else {
    // Single run
    await runSync();
  }
}

main().catch((err) => {
  console.error("[OpenClaw Brain] Fatal error:", err);
  process.exit(1);
});
