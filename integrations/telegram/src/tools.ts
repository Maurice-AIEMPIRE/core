/**
 * JARVIS Tools — Pfeifer Galaxia OS
 * Alle Werkzeuge für vollständigen System-Zugriff
 */

import { execSync, exec } from 'child_process';
import { promisify } from 'util';
import * as fs from 'fs';
import * as path from 'path';
import axios from 'axios';

const execAsync = promisify(exec);

// ── Konfiguration ─────────────────────────────────────────────────────────────
export const CONFIG = {
  server: {
    host: process.env.SERVER_SSH_HOST || '65.21.203.174',
    user: process.env.SERVER_SSH_USER || 'root',
    key:  process.env.SERVER_SSH_KEY  || `${process.env.HOME}/.ssh/id_ed25519`,
    workspace: '/opt/money-machine',
    ollamaPort: 11434,
  },
  mac: {
    home: process.env.HOME || '/Users/maurice',
    workspace: `${process.env.HOME}/.openclaw/workspace/ai-empire`,
    openclawPort: parseInt(process.env.OPENCLAW_GATEWAY_PORT || '18789'),
  },
  agents: ['monica', 'dwight', 'kelly', 'pam', 'ryan', 'chandler', 'ross'],
};

// ── SSH Helper ────────────────────────────────────────────────────────────────
export async function sshExec(cmd: string, timeoutMs = 30000): Promise<string> {
  const { host, user, key } = CONFIG.server;
  const ssh = `ssh -i ${key} -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes ${user}@${host}`;
  try {
    const { stdout, stderr } = await execAsync(
      `${ssh} ${JSON.stringify(cmd)}`,
      { timeout: timeoutMs }
    );
    return (stdout + (stderr ? `\n[stderr] ${stderr}` : '')).trim();
  } catch (err: any) {
    throw new Error(`SSH fehlgeschlagen: ${err.message?.substring(0, 500)}`);
  }
}

// ── Mac Shell ─────────────────────────────────────────────────────────────────
export function macExec(cmd: string, timeoutMs = 30000): string {
  try {
    return execSync(cmd, { timeout: timeoutMs, maxBuffer: 2 * 1024 * 1024 }).toString().trim();
  } catch (err: any) {
    throw new Error(err.stderr?.toString()?.trim() || err.message);
  }
}

// ── Datei-Operationen ─────────────────────────────────────────────────────────
export function readFile(filePath: string): string {
  const resolved = filePath.startsWith('~')
    ? filePath.replace('~', CONFIG.mac.home)
    : filePath;
  if (!fs.existsSync(resolved)) throw new Error(`Datei nicht gefunden: ${resolved}`);
  return fs.readFileSync(resolved, 'utf-8');
}

export function writeFile(filePath: string, content: string): void {
  const resolved = filePath.startsWith('~')
    ? filePath.replace('~', CONFIG.mac.home)
    : filePath;
  fs.mkdirSync(path.dirname(resolved), { recursive: true });
  fs.writeFileSync(resolved, content, 'utf-8');
}

export function listDir(dirPath: string): string {
  const resolved = dirPath.startsWith('~')
    ? dirPath.replace('~', CONFIG.mac.home)
    : dirPath;
  if (!fs.existsSync(resolved)) return `Verzeichnis nicht gefunden: ${resolved}`;
  return fs.readdirSync(resolved).join('\n');
}

// ── OpenClaw API ──────────────────────────────────────────────────────────────
export async function callOpenClaw(
  action: string,
  params: Record<string, any> = {}
): Promise<any> {
  const url = `http://localhost:${CONFIG.mac.openclawPort}`;
  try {
    const res = await axios.post(`${url}/api/${action}`, params, { timeout: 15000 });
    return res.data;
  } catch (err: any) {
    // Fallback: try GET
    try {
      const res = await axios.get(`${url}/api/${action}`, { params, timeout: 10000 });
      return res.data;
    } catch {
      throw new Error(`OpenClaw nicht erreichbar (${url}): ${err.message}`);
    }
  }
}

// ── Agenten-Trigger ───────────────────────────────────────────────────────────
export async function triggerAgent(agentName: string, task: string): Promise<string> {
  const name = agentName.toLowerCase();
  if (!CONFIG.agents.includes(name)) {
    throw new Error(`Unbekannter Agent: ${name}. Verfügbar: ${CONFIG.agents.join(', ')}`);
  }
  try {
    // Versuche OpenClaw API
    const result = await callOpenClaw('agent/run', { agent: name, task, async: false });
    return typeof result === 'string' ? result : JSON.stringify(result, null, 2);
  } catch {
    // Fallback: Claude Code CLI
    try {
      const out = macExec(
        `cd ${CONFIG.mac.home}/core/core && claude --print "Agent ${name}: ${task}" 2>&1 | tail -100`,
        60000
      );
      return out;
    } catch (err2: any) {
      throw new Error(`Agent ${name} nicht erreichbar: ${err2.message}`);
    }
  }
}

// ── Claude Code CLI ───────────────────────────────────────────────────────────
export async function runClaudeCode(prompt: string, workdir?: string): Promise<string> {
  const dir = workdir || `${CONFIG.mac.home}/core/core`;
  const escaped = prompt.replace(/"/g, '\\"').replace(/\n/g, ' ');
  try {
    const out = macExec(
      `cd "${dir}" && claude --print "${escaped}" 2>&1 | tail -200`,
      120000
    );
    return out || '(keine Ausgabe)';
  } catch (err: any) {
    throw new Error(`Claude Code Fehler: ${err.message?.substring(0, 500)}`);
  }
}

// ── Server Ollama (direkt via SSH-Tunnel oder Tailscale) ──────────────────────
export async function queryServerOllama(model: string, prompt: string): Promise<string> {
  const serverOllama = process.env.SERVER_OLLAMA_URL ||
    `http://${CONFIG.server.host}:${CONFIG.server.ollamaPort}`;
  const res = await axios.post(
    `${serverOllama}/v1/chat/completions`,
    {
      model,
      messages: [{ role: 'user', content: prompt }],
      max_tokens: 2048,
    },
    { timeout: 120000 }
  );
  return res.data.choices?.[0]?.message?.content?.trim() ?? '';
}

// ── Workspace-Dateien lesen ───────────────────────────────────────────────────
export function readWorkspace(filename: string): string {
  const paths = [
    `${CONFIG.mac.workspace}/${filename}`,
    `${CONFIG.mac.home}/.openclaw/workspace/ai-empire/${filename}`,
    `${CONFIG.mac.home}/core/core/openclaw/workspace/${filename}`,
  ];
  for (const p of paths) {
    if (fs.existsSync(p)) return fs.readFileSync(p, 'utf-8');
  }
  throw new Error(`Workspace-Datei nicht gefunden: ${filename}`);
}

// ── Logs lesen ────────────────────────────────────────────────────────────────
export async function readLogs(name: string, lines = 50): Promise<string> {
  const localLogs: Record<string, string> = {
    harvey: '/tmp/harvey-bot.log',
    ollama: '/tmp/ollama.log',
    openclaw: `${CONFIG.mac.home}/.openclaw/logs/main.log`,
  };
  if (localLogs[name]) {
    try {
      return macExec(`tail -${lines} "${localLogs[name]}" 2>/dev/null || echo "(leer)"`);
    } catch {
      return '(Log nicht gefunden)';
    }
  }
  // Server-Log via SSH
  return sshExec(
    `tail -${lines} ${CONFIG.server.workspace}/openclaw/memory/${name}.log 2>/dev/null ` +
    `|| journalctl -u ${name} -n ${lines} --no-pager 2>/dev/null ` +
    `|| echo "(${name} log nicht gefunden)"`
  );
}

// ── System-Status ─────────────────────────────────────────────────────────────
export async function getSystemStatus(): Promise<string> {
  const lines: string[] = ['🌌 Galaxia OS Status\n'];

  // Mac
  try {
    const cpu = macExec("ps -Ao pcpu | awk 'NR>1{s+=$1}END{printf \"%.0f\",s}'");
    const mem = macExec("vm_stat | awk '/free/{free=$3} /active/{act=$3} /inactive/{inact=$3} /wired/{wire=$4} END{total=free+act+inact+wire; printf \"%.0f%%\", (1-(free/total))*100}'");
    lines.push(`💻 Mac: CPU ${cpu}% | RAM ${mem}`);
  } catch {
    lines.push('💻 Mac: nicht lesbar');
  }

  // Harvey
  try {
    const pid = fs.existsSync('/tmp/harvey-bot.pid')
      ? fs.readFileSync('/tmp/harvey-bot.pid', 'utf-8').trim()
      : '';
    lines.push(`🤖 Harvey: ${pid ? `PID ${pid} ✅` : '❌ gestoppt'}`);
  } catch {
    lines.push('🤖 Harvey: unbekannt');
  }

  // OpenClaw
  try {
    await axios.get(`http://localhost:${CONFIG.mac.openclawPort}/health`, { timeout: 3000 });
    lines.push(`🦅 OpenClaw: ✅ aktiv (Port ${CONFIG.mac.openclawPort})`);
  } catch {
    lines.push(`🦅 OpenClaw: ⚠️ nicht erreichbar`);
  }

  // Server
  try {
    const up = await sshExec('uptime -p && free -h | grep Mem | awk \'{print $3"/"$2}\'', 8000);
    lines.push(`🖥  Server: ✅\n   ${up.replace('\n', ' | ')}`);
  } catch {
    lines.push('🖥  Server: ❌ nicht erreichbar');
  }

  return lines.join('\n');
}

// ── Tool-Definitionen für LLM Tool-Use ───────────────────────────────────────
export const TOOL_DEFINITIONS = [
  {
    name: 'exec_mac',
    description: 'Führt einen Shell-Befehl auf dem Mac (MinivonMaurice) aus',
    input_schema: {
      type: 'object',
      properties: { cmd: { type: 'string', description: 'Shell-Befehl' } },
      required: ['cmd'],
    },
  },
  {
    name: 'exec_server',
    description: 'Führt einen Shell-Befehl auf dem Hetzner-Server (65.21.203.174) via SSH aus',
    input_schema: {
      type: 'object',
      properties: { cmd: { type: 'string', description: 'Shell-Befehl' } },
      required: ['cmd'],
    },
  },
  {
    name: 'read_file',
    description: 'Liest den Inhalt einer Datei (Mac oder absoluter Pfad)',
    input_schema: {
      type: 'object',
      properties: { path: { type: 'string', description: 'Dateipfad' } },
      required: ['path'],
    },
  },
  {
    name: 'write_file',
    description: 'Schreibt Inhalt in eine Datei (erstellt Verzeichnisse automatisch)',
    input_schema: {
      type: 'object',
      properties: {
        path:    { type: 'string', description: 'Dateipfad' },
        content: { type: 'string', description: 'Dateiinhalt' },
      },
      required: ['path', 'content'],
    },
  },
  {
    name: 'trigger_agent',
    description: 'Startet einen Galaxia-Agenten (monica/dwight/kelly/pam/ryan/chandler/ross)',
    input_schema: {
      type: 'object',
      properties: {
        agent: { type: 'string', description: 'Agent-Name' },
        task:  { type: 'string', description: 'Aufgabe für den Agenten' },
      },
      required: ['agent', 'task'],
    },
  },
  {
    name: 'run_claude_code',
    description: 'Führt eine Claude Code Aufgabe aus (Programmierung, Analyse, Refactoring)',
    input_schema: {
      type: 'object',
      properties: {
        prompt:  { type: 'string', description: 'Aufgabe für Claude Code' },
        workdir: { type: 'string', description: 'Arbeitsverzeichnis (optional)' },
      },
      required: ['prompt'],
    },
  },
  {
    name: 'read_workspace',
    description: 'Liest eine Datei aus dem Galaxia-Workspace (SOUL.md, AGENTS.md, REVENUE-LOG.md, ...)',
    input_schema: {
      type: 'object',
      properties: { filename: { type: 'string', description: 'Dateiname im Workspace' } },
      required: ['filename'],
    },
  },
] as const;

// ── Tool ausführen ─────────────────────────────────────────────────────────────
export async function executeTool(name: string, input: Record<string, any>): Promise<string> {
  try {
    switch (name) {
      case 'exec_mac':       return macExec(input.cmd);
      case 'exec_server':    return await sshExec(input.cmd);
      case 'read_file':      return readFile(input.path);
      case 'write_file':     writeFile(input.path, input.content); return `✓ Geschrieben: ${input.path}`;
      case 'trigger_agent':  return await triggerAgent(input.agent, input.task);
      case 'run_claude_code': return await runClaudeCode(input.prompt, input.workdir);
      case 'read_workspace': return readWorkspace(input.filename);
      default:               return `Unbekanntes Tool: ${name}`;
    }
  } catch (err: any) {
    return `[Fehler in ${name}]: ${err.message}`;
  }
}
