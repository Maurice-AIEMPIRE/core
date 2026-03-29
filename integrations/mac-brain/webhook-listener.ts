#!/usr/bin/env node
/**
 * Mac Brain — iCloud Document Writer
 *
 * Listens on port 9001 for two types of requests:
 *
 * 1. Direct document writes:
 *    POST /write-document  { title, content, folder? }
 *    → SSH to Mac → writes Markdown to iCloud Drive
 *
 * 2. CORE activity webhooks (registered via /api/v1/webhooks):
 *    POST /core-webhook  { event: "activity.created", data: {...} }
 *    → If type=DOCUMENT → forward to /write-document handler
 *
 * Required env:
 *   MAC_SSH_HOST      — Mac IP or Tailscale hostname
 *   MAC_SSH_USER      — SSH user on Mac (default: maurice)
 *   MAC_SSH_PORT      — SSH port (default: 22)
 *   MAC_SSH_KEY       — Path to SSH private key
 *   MAC_ICLOUD_PATH   — iCloud Drive base path on Mac
 *                       (default: /Users/maurice/Library/Mobile Documents/com~apple~CloudDocs)
 */

import http from "http";
import { execFile } from "child_process";
import { promisify } from "util";
import path from "path";
import { fileURLToPath } from "url";

const execFileAsync = promisify(execFile);
const __dirname = path.dirname(fileURLToPath(import.meta.url));

const PORT = parseInt(process.env.MAC_BRAIN_PORT ?? "9001", 10);

const SSH_HOST = process.env.MAC_SSH_HOST ?? "";
const SSH_USER = process.env.MAC_SSH_USER ?? "maurice";
const SSH_PORT = process.env.MAC_SSH_PORT ?? "22";
const SSH_KEY = process.env.MAC_SSH_KEY ?? "/root/.ssh/mac_id_ed25519";

const ICLOUD_BASE =
  process.env.MAC_ICLOUD_PATH ??
  "/Users/maurice/Library/Mobile\\ Documents/com~apple~CloudDocs";

interface WriteDocumentRequest {
  title: string;
  content: string;
  folder?: string;
}

function sanitizeFilename(title: string): string {
  return title
    .replace(/[^a-zA-Z0-9\-_äöüÄÖÜß ]/g, "")
    .trim()
    .replace(/\s+/g, "-")
    .slice(0, 80);
}

function datePrefix(): string {
  return new Date().toISOString().slice(0, 10);
}

async function writeToICloud(req: WriteDocumentRequest): Promise<void> {
  if (!SSH_HOST) {
    console.warn("[Mac Brain] MAC_SSH_HOST not set — cannot write to iCloud");
    return;
  }

  const folder = req.folder ?? "GalaxiaBrain";
  const filename = `${datePrefix()}-${sanitizeFilename(req.title)}.md`;
  const remotePath = `${ICLOUD_BASE}/${folder}/${filename}`;

  // Build markdown content
  const markdown = [
    `# ${req.title}`,
    `_Generated: ${new Date().toLocaleString("de-DE")} by Galaxia Brain_`,
    `_Folder: ${folder}_`,
    "",
    req.content,
  ].join("\n");

  // Escape content for SSH heredoc
  const escapedContent = markdown.replace(/'/g, `'"'"'`);

  // SSH command: create dir + write file
  const sshCmd = [
    `mkdir -p "$(dirname '${remotePath}')"`,
    `&&`,
    `cat > '${remotePath}' << 'GALAXIA_EOF'`,
    escapedContent,
    `GALAXIA_EOF`,
  ].join(" ");

  try {
    await execFileAsync("ssh", [
      "-i", SSH_KEY,
      "-p", SSH_PORT,
      "-o", "StrictHostKeyChecking=no",
      "-o", "ConnectTimeout=10",
      `${SSH_USER}@${SSH_HOST}`,
      sshCmd,
    ]);
    console.log(`[Mac Brain] ✓ Written to iCloud: ${folder}/${filename}`);
  } catch (err) {
    console.error("[Mac Brain] SSH write failed:", (err as Error).message);
    throw err;
  }
}

function parseBody(req: http.IncomingMessage): Promise<unknown> {
  return new Promise((resolve, reject) => {
    let body = "";
    req.on("data", (chunk) => {
      body += chunk;
      if (body.length > 10 * 1024 * 1024) reject(new Error("Body too large"));
    });
    req.on("end", () => {
      try {
        resolve(JSON.parse(body));
      } catch {
        resolve({});
      }
    });
    req.on("error", reject);
  });
}

function sendJson(res: http.ServerResponse, status: number, data: unknown): void {
  const body = JSON.stringify(data);
  res.writeHead(status, {
    "Content-Type": "application/json",
    "Content-Length": Buffer.byteLength(body),
  });
  res.end(body);
}

const server = http.createServer(async (req, res) => {
  const url = req.url ?? "/";
  const method = req.method ?? "GET";

  // Health check
  if (method === "GET" && url === "/health") {
    return sendJson(res, 200, { status: "ok", service: "mac-brain" });
  }

  // Direct document write
  if (method === "POST" && url === "/write-document") {
    try {
      const body = (await parseBody(req)) as WriteDocumentRequest;

      if (!body.title || !body.content) {
        return sendJson(res, 400, { error: "title and content required" });
      }

      await writeToICloud(body);
      return sendJson(res, 200, { success: true, file: `${body.folder ?? "GalaxiaBrain"}/${datePrefix()}-${sanitizeFilename(body.title)}.md` });
    } catch (err) {
      return sendJson(res, 500, { error: (err as Error).message });
    }
  }

  // CORE webhook receiver
  if (method === "POST" && url === "/core-webhook") {
    try {
      const event = (await parseBody(req)) as {
        event: string;
        data?: { type?: string; title?: string; content?: string };
      };

      console.log(`[Mac Brain] CORE webhook: ${event.event}`);

      // Only forward DOCUMENT type activities to iCloud
      if (
        event.event === "activity.created" &&
        event.data?.type === "DOCUMENT" &&
        event.data.title &&
        event.data.content
      ) {
        await writeToICloud({
          title: event.data.title,
          content: event.data.content,
          folder: "GalaxiaBrain",
        });
      }

      return sendJson(res, 200, { received: true });
    } catch (err) {
      console.error("[Mac Brain] Webhook error:", (err as Error).message);
      return sendJson(res, 500, { error: (err as Error).message });
    }
  }

  return sendJson(res, 404, { error: "Not found" });
});

server.listen(PORT, "0.0.0.0", () => {
  console.log(`[Mac Brain] iCloud Writer listening on port ${PORT}`);
  console.log(`  SSH Target: ${SSH_USER}@${SSH_HOST}:${SSH_PORT}`);
  console.log(`  iCloud Base: ${ICLOUD_BASE}`);
  console.log(`  Endpoints: POST /write-document, POST /core-webhook, GET /health`);
});

server.on("error", (err) => {
  console.error("[Mac Brain] Server error:", err);
  process.exit(1);
});
