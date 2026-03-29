#!/usr/bin/env node
/**
 * Galaxia Brain Bridge — Galaxia Vector DB → CORE Memory Sync
 *
 * Reads Planet README files and discovery outputs from the Galaxia
 * LanceDB vector system, ingests them into CORE for unified access.
 *
 * Run modes:
 *   node galaxia-bridge.js           — single sync run
 *   node galaxia-bridge.js --daemon  — sync every 30 minutes
 *   node galaxia-bridge.js --planet <name>  — sync one specific planet
 *
 * Required env:
 *   GALAXIA_BRAIN_URL    — CORE server URL
 *   GALAXIA_BRAIN_TOKEN  — CORE API token
 *   GALAXIA_DIR          — Galaxia vector DB root (default: /root/galaxia)
 */

import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import { createHash } from "crypto";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, "../..");

const CORE_URL = process.env.GALAXIA_BRAIN_URL ?? "http://localhost:3033";
const CORE_TOKEN = process.env.GALAXIA_BRAIN_TOKEN ?? "";
const GALAXIA_DIR = process.env.GALAXIA_DIR ?? "/root/galaxia";
const PLANETS_DIR = path.join(GALAXIA_DIR, "planets");

const STATE_FILE = path.join(REPO_ROOT, "galaxia/brain/.sync-state.json");

type SyncState = Record<string, string>;

function loadState(): SyncState {
  try {
    return JSON.parse(fs.readFileSync(STATE_FILE, "utf-8"));
  } catch {
    return {};
  }
}

function saveState(state: SyncState): void {
  fs.mkdirSync(path.dirname(STATE_FILE), { recursive: true });
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
    console.error("[Galaxia Bridge] GALAXIA_BRAIN_TOKEN not set. Skipping.");
    return;
  }

  const body = {
    episodeBody: content,
    referenceTime: new Date().toISOString(),
    source: "galaxia",
    type: "DOCUMENT",
    title,
    sessionId,
    contentHash,
    metadata: {
      brain: "galaxia",
      system: "planet",
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

async function syncPlanet(
  planetName: string,
  state: SyncState,
  runId: string
): Promise<SyncState> {
  const planetDir = path.join(PLANETS_DIR, planetName);
  if (!fs.existsSync(planetDir)) return state;

  const mdFiles = fs
    .readdirSync(planetDir, { recursive: true })
    .filter((f): f is string => typeof f === "string" && f.endsWith(".md"));

  for (const mdFile of mdFiles) {
    const filePath = path.join(planetDir, mdFile);
    const content = fs.readFileSync(filePath, "utf-8").trim();

    if (!content || content.length < 20) continue;

    const contentHash = hash(content);
    const relPath = `galaxia/planets/${planetName}/${mdFile}`;
    const title = `Galaxia Planet [${planetName}]: ${mdFile.replace(".md", "")}`;

    if (state[relPath] === contentHash) {
      continue; // unchanged
    }

    await ingestToCore(content, title, `${runId}-${planetName}`, contentHash);
    state = { ...state, [relPath]: contentHash };
  }

  return state;
}

async function syncGalaxiaDocs(state: SyncState, runId: string): Promise<SyncState> {
  // Sync top-level galaxia docs (core knowledge files in repo)
  const galaxiaRepoDir = path.join(REPO_ROOT, "galaxia");
  const topFiles = [
    path.join(galaxiaRepoDir, "galaxia-vector-core.py"),
  ];

  // Also check for any .md files directly in galaxia/
  const mdFiles = fs
    .readdirSync(galaxiaRepoDir)
    .filter((f) => f.endsWith(".md"))
    .map((f) => path.join(galaxiaRepoDir, f));

  for (const filePath of [...topFiles, ...mdFiles]) {
    if (!fs.existsSync(filePath)) continue;

    const content = fs.readFileSync(filePath, "utf-8").trim();
    if (!content || content.length < 20) continue;

    const contentHash = hash(content);
    const relPath = path.relative(REPO_ROOT, filePath);
    const title = `Galaxia Core: ${path.basename(filePath)}`;

    if (state[relPath] === contentHash) continue;

    await ingestToCore(content, title, `${runId}-core`, contentHash);
    state = { ...state, [relPath]: contentHash };
  }

  return state;
}

async function runSync(specificPlanet?: string): Promise<void> {
  console.log("\n[Galaxia Bridge] Starting sync to CORE...");
  let state = loadState();
  const runId = `galaxia-${Date.now()}`;

  // Sync core galaxia repo files
  state = await syncGalaxiaDocs(state, runId);

  if (!fs.existsSync(PLANETS_DIR)) {
    console.log(`  ~ Planets directory not found: ${PLANETS_DIR}`);
    saveState(state);
    return;
  }

  if (specificPlanet) {
    state = await syncPlanet(specificPlanet, state, runId);
  } else {
    const planets = fs
      .readdirSync(PLANETS_DIR, { withFileTypes: true })
      .filter((d) => d.isDirectory())
      .map((d) => d.name);

    console.log(`  Found ${planets.length} planets`);
    for (const planet of planets) {
      state = await syncPlanet(planet, state, runId);
    }
  }

  saveState(state);
  console.log("[Galaxia Bridge] Sync complete.\n");
}

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const planetIdx = args.indexOf("--planet");
  const specificPlanet = planetIdx >= 0 ? args[planetIdx + 1] : undefined;

  if (args.includes("--daemon")) {
    await runSync(specificPlanet);
    setInterval(() => runSync(), 30 * 60 * 1000);
    console.log("[Galaxia Bridge] Daemon mode: syncing every 30 minutes.");
  } else {
    await runSync(specificPlanet);
  }
}

main().catch((err) => {
  console.error("[Galaxia Bridge] Fatal error:", err);
  process.exit(1);
});
