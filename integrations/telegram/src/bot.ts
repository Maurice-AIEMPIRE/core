import { readFileSync } from 'fs';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';

// Load .env from same directory as this script
try {
  const envPath = resolve(dirname(fileURLToPath(import.meta.url)), '..', '.env');
  const envContent = readFileSync(envPath, 'utf-8');
  for (const line of envContent.split('\n')) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const eqIdx = trimmed.indexOf('=');
    if (eqIdx > 0) {
      const key = trimmed.slice(0, eqIdx).trim();
      const val = trimmed.slice(eqIdx + 1).trim();
      if (!process.env[key]) process.env[key] = val;
    }
  }
} catch {}

import { callTelegramApi, formatUser } from './utils';
import { extractMedia, downloadTelegramFile, extractUrls, classifyUrl, getStorageStats } from './media';
import { chat, clearSession, generatePromo } from './chat';
import { runAgentTask } from './agentic';
import { getSystemStatus } from './tools';
import { execSync, exec } from 'child_process';
import { promisify } from 'util';
const execAsync = promisify(exec);

const SERVER_HOST = process.env.SERVER_SSH_HOST || '65.21.203.174';
const SERVER_USER = process.env.SERVER_SSH_USER || 'root';
const SERVER_KEY  = process.env.SERVER_SSH_KEY  || `${process.env.HOME}/.ssh/id_ed25519`;

async function sshExec(cmd: string): Promise<string> {
  const ssh = `ssh -i ${SERVER_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=10 ${SERVER_USER}@${SERVER_HOST}`;
  const { stdout, stderr } = await execAsync(`${ssh} "${cmd.replace(/"/g, '\\"')}"`, { timeout: 30000 });
  return (stdout + (stderr ? `\nSTDERR: ${stderr}` : '')).trim();
}

const ADMIN_ID = process.env.TELEGRAM_ADMIN_ID ? Number(process.env.TELEGRAM_ADMIN_ID) : undefined;
const TARGET_CHANNEL = process.env.TELEGRAM_TARGET_CHANNEL || '';

// Store pending promos for approve/reject flow
const pendingPromos = new Map<string, { chatId: number; promo: string; url?: string }>();

async function sendTyping(botToken: string, chatId: number) {
  try {
    await callTelegramApi(botToken, 'sendChatAction', { chat_id: chatId, action: 'typing' });
  } catch (_) {}
}

async function handleMessage(botToken: string, message: any) {
  const chatId = message.chat.id;
  const text = (message.text ?? message.caption ?? '').trim();
  const from = message.from ? formatUser(message.from) : 'Unknown';
  const userId = message.from?.id;

  console.log(`[${new Date().toISOString()}] ${from}: ${text || '[media]'}`);

  // --- Commands ---
  if (text.startsWith('/')) {
    const handled = await handleCommand(botToken, chatId, text, userId);
    if (handled) return;
  }

  // --- Media handling ---
  const media = extractMedia(message);
  if (media) {
    await sendTyping(botToken, chatId);
    try {
      const localPath = await downloadTelegramFile(botToken, media.fileId, media.fileName, media.type);
      const sizeKB = media.fileSize ? (media.fileSize / 1024).toFixed(1) : '?';

      await callTelegramApi(botToken, 'sendMessage', {
        chat_id: chatId,
        text: `${mediaEmoji(media.type)} Gespeichert: ${media.fileName} (${sizeKB} KB)\n${localPath}`,
      });
    } catch (err: any) {
      await callTelegramApi(botToken, 'sendMessage', {
        chat_id: chatId,
        text: `Fehler beim Download: ${err.message}`,
      });
    }

    // Check caption for URLs → promo flow
    const urls = extractUrls(message);
    if (urls.length > 0) {
      await handlePromoFlow(botToken, chatId, urls, text);
    }
    return;
  }

  const isHarveyPersona = process.env.BOT_PERSONA === 'harvey';

  // --- URL handling → Promo Flow (not for Harvey: legal URLs go to AI) ---
  const urls = extractUrls(message);
  if (urls.length > 0 && !isHarveyPersona) {
    await sendTyping(botToken, chatId);
    await handlePromoFlow(botToken, chatId, urls, text);
    return;
  }

  // --- Forwarded / Long text → Promo Flow (not for Harvey) ---
  if (!isHarveyPersona) {
    if (message.forward_from || message.forward_from_chat) {
      if (text.length > 20) {
        await sendTyping(botToken, chatId);
        await handlePromoFlow(botToken, chatId, [], text);
        return;
      }
    }
    if (text.length > 100 && !text.endsWith('?')) {
      // Long text that's not a question → treat as content for promo
      await sendTyping(botToken, chatId);
      await handlePromoFlow(botToken, chatId, [], text);
      return;
    }
  }

  // --- Contact ---
  if (message.contact) {
    const c = message.contact;
    await callTelegramApi(botToken, 'sendMessage', {
      chat_id: chatId,
      text: `Kontakt: ${c.first_name} ${c.last_name ?? ''} ${c.phone_number ? `| Tel: ${c.phone_number}` : ''}`.trim(),
    });
    return;
  }

  // --- Location ---
  if (message.location) {
    await callTelegramApi(botToken, 'sendMessage', {
      chat_id: chatId,
      text: `Standort: ${message.location.latitude}, ${message.location.longitude}`,
    });
    return;
  }

  // --- AI Chat (default for all text) ---
  if (text) {
    await sendTyping(botToken, chatId);
    const reply = await chat(chatId, text);

    // Split long messages (Telegram limit: 4096 chars)
    const chunks = splitMessage(reply, 4000);
    for (const chunk of chunks) {
      await callTelegramApi(botToken, 'sendMessage', {
        chat_id: chatId,
        text: chunk,
        parse_mode: 'Markdown',
      }).catch(() => {
        // Fallback without markdown if parsing fails
        return callTelegramApi(botToken, 'sendMessage', {
          chat_id: chatId,
          text: chunk,
        });
      });
    }
    return;
  }

  // Fallback
  await callTelegramApi(botToken, 'sendMessage', {
    chat_id: chatId,
    text: 'Nachricht empfangen.',
  });
}

async function handleCommand(botToken: string, chatId: number, text: string, userId?: number): Promise<boolean> {
  const cmd = text.split(' ')[0].toLowerCase();
  const args = text.slice(cmd.length).trim();

  switch (cmd) {
    case '/start': {
      const isHarvey = process.env.BOT_PERSONA === 'harvey';
      await callTelegramApi(botToken, 'sendMessage', {
        chat_id: chatId,
        text: isHarvey
          ? [
              '⚡ JARVIS — Pfeifer Galaxia OS',
              '',
              'Vollzugriff auf alle Systeme:',
              '🖥  Hetzner-Server (65.21.203.174)',
              '💻  Mac (lokale Shell & Dateien)',
              '🤖  Agenten: Monica, Dwight, Kelly, Ryan...',
              '🧠  Claude Code & OpenClaw',
              '⚖️  Recht: Vertraege, DSGVO, GmbH, IP',
              '',
              '/task <Aufgabe> — Autonome Multi-Step-Ausfuehrung',
              '/server <cmd>  — Hetzner SSH',
              '/mac <cmd>     — Mac Shell',
              '/agents        — Agenten-Status',
              '/galaxia       — Vollstaendiger System-Status',
              '/help          — Alle Befehle',
              '',
              'Oder einfach schreiben — ich handle alles.',
            ].join('\n')
          : [
              'M0Claw - Dein KI-Agent',
              '',
              'Schreib mir einfach - ich antworte mit KI.',
              'Links/Content → automatischer Promo-Post',
              '',
              '/clear - Chat zuruecksetzen',
              '/status - System-Status',
              '/models - Ollama Models',
              '/exec <cmd> - Shell Command',
              '/help - Alle Befehle',
            ].join('\n'),
      });
      return true;
    }

    case '/clear':
      clearSession(chatId);
      await callTelegramApi(botToken, 'sendMessage', {
        chat_id: chatId,
        text: 'Chat-Verlauf geloescht.',
      });
      return true;

    case '/status': {
      const isHarvey = process.env.BOT_PERSONA === 'harvey';
      const uptime = process.uptime();
      const h = Math.floor(uptime / 3600);
      const m = Math.floor((uptime % 3600) / 60);
      const stats = getStorageStats();
      const model = process.env.AI_MODEL || 'unbekannt';
      const provider = process.env.OLLAMA_BASE_URL
        ? `Ollama (${process.env.OLLAMA_BASE_URL})`
        : process.env.ANTHROPIC_API_KEY
          ? 'Anthropic'
          : process.env.OPENAI_API_KEY
            ? `OpenAI-compatible (${process.env.AI_API_BASE || 'openai'})`
            : 'kein Provider';

      await callTelegramApi(botToken, 'sendMessage', {
        chat_id: chatId,
        text: [
          isHarvey ? 'Harvey Status' : 'M0Claw Status',
          `Uptime: ${h}h ${m}m`,
          `Model: ${model}`,
          `Provider: ${provider}`,
          `Dateien: ${stats.totalFiles} (${stats.totalSizeMB} MB)`,
        ].join('\n'),
      });
      return true;
    }

    case '/ping':
      await callTelegramApi(botToken, 'sendMessage', { chat_id: chatId, text: 'Pong!' });
      return true;

    case '/models': {
      try {
        const out = execSync('ollama list 2>/dev/null', { timeout: 10000 }).toString().trim();
        const lines = out.split('\n').slice(0, 15); // max 15 lines
        await callTelegramApi(botToken, 'sendMessage', {
          chat_id: chatId,
          text: `Ollama Models:\n\n${lines.join('\n')}`,
        });
      } catch {
        await callTelegramApi(botToken, 'sendMessage', {
          chat_id: chatId,
          text: 'Ollama nicht erreichbar.',
        });
      }
      return true;
    }

    case '/server': {
      if (ADMIN_ID && userId !== ADMIN_ID) {
        await callTelegramApi(botToken, 'sendMessage', { chat_id: chatId, text: 'Nicht autorisiert.' });
        return true;
      }
      if (!args) {
        await callTelegramApi(botToken, 'sendMessage', { chat_id: chatId, text: `Usage: /server <command>\nServer: ${SERVER_USER}@${SERVER_HOST}` });
        return true;
      }
      await sendTyping(botToken, chatId);
      try {
        const out = await sshExec(args);
        const result = out.substring(0, 3500) || '(keine Ausgabe)';
        await callTelegramApi(botToken, 'sendMessage', { chat_id: chatId, text: `🖥 ${SERVER_HOST}\n$ ${args}\n\n${result}` });
      } catch (err: any) {
        await callTelegramApi(botToken, 'sendMessage', { chat_id: chatId, text: `SSH-Fehler: ${err.message.substring(0, 1000)}` });
      }
      return true;
    }

    case '/mac': {
      if (ADMIN_ID && userId !== ADMIN_ID) {
        await callTelegramApi(botToken, 'sendMessage', { chat_id: chatId, text: 'Nicht autorisiert.' });
        return true;
      }
      if (!args) {
        await callTelegramApi(botToken, 'sendMessage', { chat_id: chatId, text: 'Usage: /mac <command>' });
        return true;
      }
      try {
        const out = execSync(args, { timeout: 30000, maxBuffer: 1024 * 1024 }).toString().trim();
        await callTelegramApi(botToken, 'sendMessage', { chat_id: chatId, text: `💻 Mac\n$ ${args}\n\n${out.substring(0, 3500) || '(keine Ausgabe)'}` });
      } catch (err: any) {
        await callTelegramApi(botToken, 'sendMessage', { chat_id: chatId, text: `Mac-Fehler:\n${(err.stderr?.toString() || err.message).substring(0, 2000)}` });
      }
      return true;
    }

    case '/agents': {
      await sendTyping(botToken, chatId);
      try {
        const stateFile = `${process.env.HOME}/.openclaw/workspace/ai-empire/../../../.openclaw/workspace/ai-empire/../../openclaw/memory/agents-state.json`;
        let status = '🤖 Agenten-Status:\n\n';
        try {
          const raw = require('fs').readFileSync(stateFile.replace(/\.\.\//g, ''), 'utf-8');
          const state = JSON.parse(raw);
          const agents = ['monica', 'dwight', 'kelly', 'ryan', 'chandler', 'ross'];
          for (const name of agents) {
            const a = state[name] || {};
            const emoji = a.status === 'running' ? '🟢' : a.status === 'error' ? '🔴' : '⚪';
            status += `${emoji} ${name.toUpperCase()}: ${a.status || 'idle'} (${a.totalRuns || 0} runs)\n`;
          }
        } catch {
          status += 'Monica ⚪ Kelly ⚪ Dwight ⚪\nRyan ⚪ Chandler ⚪ Ross ⚪\n(State-Datei nicht lesbar)';
        }
        await callTelegramApi(botToken, 'sendMessage', { chat_id: chatId, text: status });
      } catch (err: any) {
        await callTelegramApi(botToken, 'sendMessage', { chat_id: chatId, text: `Agenten-Fehler: ${err.message}` });
      }
      return true;
    }

    case '/services': {
      await sendTyping(botToken, chatId);
      try {
        const out = await sshExec('systemctl is-active ollama telegram-bot.service webhook.service 2>/dev/null; echo "---"; systemctl status ollama --no-pager -l | tail -3');
        await callTelegramApi(botToken, 'sendMessage', { chat_id: chatId, text: `🖥 Server Services:\n\n${out.substring(0, 3000)}` });
      } catch (err: any) {
        await callTelegramApi(botToken, 'sendMessage', { chat_id: chatId, text: `Services nicht erreichbar: ${err.message.substring(0, 500)}` });
      }
      return true;
    }

    case '/deploy': {
      if (ADMIN_ID && userId !== ADMIN_ID) {
        await callTelegramApi(botToken, 'sendMessage', { chat_id: chatId, text: 'Nicht autorisiert.' });
        return true;
      }
      await sendTyping(botToken, chatId);
      try {
        const out = await sshExec('cd /opt/money-machine && git pull origin main 2>&1 | tail -5 && echo "Deploy OK"');
        await callTelegramApi(botToken, 'sendMessage', { chat_id: chatId, text: `🚀 Deploy:\n\n${out.substring(0, 2000)}` });
      } catch (err: any) {
        await callTelegramApi(botToken, 'sendMessage', { chat_id: chatId, text: `Deploy-Fehler: ${err.message.substring(0, 1000)}` });
      }
      return true;
    }

    case '/logs': {
      await sendTyping(botToken, chatId);
      const logName = args || 'harvey';
      const logMap: Record<string, string> = {
        harvey: '/tmp/harvey-bot.log',
        ollama: '/tmp/ollama.log',
        openclaw: `${process.env.HOME}/.openclaw/workspace/ai-empire/../../openclaw/memory/main.log`,
      };
      try {
        if (logMap[logName]) {
          const out = execSync(`tail -30 ${logMap[logName]} 2>/dev/null || echo "(Log leer oder nicht gefunden)"`, { timeout: 5000 }).toString();
          await callTelegramApi(botToken, 'sendMessage', { chat_id: chatId, text: `📋 ${logName} logs:\n\n${out.substring(0, 3500)}` });
        } else {
          const out = await sshExec(`tail -30 /opt/money-machine/openclaw/memory/${logName}.log 2>/dev/null || journalctl -u ${logName} -n 30 --no-pager 2>/dev/null || echo "Log nicht gefunden"`);
          await callTelegramApi(botToken, 'sendMessage', { chat_id: chatId, text: `📋 Server/${logName}:\n\n${out.substring(0, 3500)}` });
        }
      } catch (err: any) {
        await callTelegramApi(botToken, 'sendMessage', { chat_id: chatId, text: `Log-Fehler: ${err.message.substring(0, 500)}` });
      }
      return true;
    }

    case '/exec': {
      if (ADMIN_ID && userId !== ADMIN_ID) {
        await callTelegramApi(botToken, 'sendMessage', { chat_id: chatId, text: 'Nicht autorisiert.' });
        return true;
      }
      if (!args) {
        await callTelegramApi(botToken, 'sendMessage', {
          chat_id: chatId,
          text: 'Usage: /exec <command>',
        });
        return true;
      }
      try {
        const out = execSync(args, { timeout: 30000, maxBuffer: 1024 * 1024 }).toString().trim();
        const result = out.substring(0, 3500) || '(keine Ausgabe)';
        await callTelegramApi(botToken, 'sendMessage', {
          chat_id: chatId,
          text: `$ ${args}\n\n${result}`,
        });
      } catch (err: any) {
        const errMsg = (err.stderr?.toString() || err.message || 'Fehler').substring(0, 2000);
        await callTelegramApi(botToken, 'sendMessage', {
          chat_id: chatId,
          text: `Fehler:\n${errMsg}`,
        });
      }
      return true;
    }

    case '/system': {
      try {
        const hostname = execSync('hostname').toString().trim();
        const diskRaw = execSync("df -h / | tail -1 | awk '{print $4}'").toString().trim();
        const memRaw = execSync("vm_stat | head -5").toString().trim();
        const ollamaRunning = execSync("pgrep -x ollama >/dev/null 2>&1 && echo 'running' || echo 'stopped'").toString().trim();

        await callTelegramApi(botToken, 'sendMessage', {
          chat_id: chatId,
          text: [
            `System: ${hostname}`,
            `Disk frei: ${diskRaw}`,
            `Ollama: ${ollamaRunning}`,
          ].join('\n'),
        });
      } catch (err: any) {
        await callTelegramApi(botToken, 'sendMessage', {
          chat_id: chatId,
          text: `System-Info Fehler: ${err.message}`,
        });
      }
      return true;
    }

    case '/help': {
      const isHarvey = process.env.BOT_PERSONA === 'harvey';
      await callTelegramApi(botToken, 'sendMessage', {
        chat_id: chatId,
        text: isHarvey
          ? [
              '⚡ JARVIS — Alle Befehle:',
              '',
              '🧠  /task <Aufgabe> — Autonomer Multi-Step Agent',
              '🌌  /galaxia        — Vollstaendiger System-Status',
              '🖥  /server <cmd>  — Hetzner Server SSH',
              '💻  /mac <cmd>     — Mac Shell',
              '🤖  /agents        — Agenten-Status',
              '⚙️   /services      — Server-Services',
              '🚀  /deploy        — Git Pull & Deploy',
              '📋  /logs [name]   — Logs (harvey/ollama/openclaw)',
              '📊  /status        — Bot-Status',
              '🔄  /clear         — Chat zuruecksetzen',
              '',
              'Einfach schreiben — JARVIS antwortet direkt.',
              'Fuer komplexe Tasks: /task <Beschreibung>',
            ].join('\n')
          : [
              'M0Claw Befehle:',
              '',
              '/start - Willkommen',
              '/clear - Chat loeschen',
              '/status - Bot-Status',
              '/ping - Pong',
              '/models - Ollama Models',
              '/exec <cmd> - Shell ausfuehren',
              '/system - System-Info',
              '/help - Diese Hilfe',
              '',
              'Oder einfach schreiben - KI antwortet!',
              'Links → Promo-Post mit Freigabe',
            ].join('\n'),
      });
      return true;
    }

    case '/task':
    case '/do': {
      if (ADMIN_ID && userId !== ADMIN_ID) {
        await callTelegramApi(botToken, 'sendMessage', { chat_id: chatId, text: 'Nicht autorisiert.' });
        return true;
      }
      if (!args) {
        await callTelegramApi(botToken, 'sendMessage', {
          chat_id: chatId,
          text: 'Usage: /task <Aufgabe>\nBeispiel: /task Prüfe Server-Status und starte Ollama neu falls nötig',
        });
        return true;
      }
      await sendTyping(botToken, chatId);
      await callTelegramApi(botToken, 'sendMessage', {
        chat_id: chatId,
        text: `⚙️ Starte Agentic Task...\n${args}`,
      });
      try {
        const result = await runAgentTask(args, async (step: string) => {
          // Send step updates for tool calls (short ones)
          if (step.startsWith('⚡')) {
            await callTelegramApi(botToken, 'sendMessage', { chat_id: chatId, text: step }).catch(() => {});
          }
        });
        const chunks = splitMessage(result, 4000);
        for (const chunk of chunks) {
          await callTelegramApi(botToken, 'sendMessage', {
            chat_id: chatId,
            text: chunk,
            parse_mode: 'Markdown',
          }).catch(() => callTelegramApi(botToken, 'sendMessage', { chat_id: chatId, text: chunk }));
        }
      } catch (err: any) {
        await callTelegramApi(botToken, 'sendMessage', { chat_id: chatId, text: `Task-Fehler: ${err.message.substring(0, 1000)}` });
      }
      return true;
    }

    case '/galaxia':
    case '/fullstatus': {
      await sendTyping(botToken, chatId);
      try {
        const status = await getSystemStatus();
        await callTelegramApi(botToken, 'sendMessage', { chat_id: chatId, text: status });
      } catch (err: any) {
        await callTelegramApi(botToken, 'sendMessage', { chat_id: chatId, text: `Status-Fehler: ${err.message.substring(0, 500)}` });
      }
      return true;
    }

    default:
      return false; // not a known command, pass to AI
  }
}

async function handlePromoFlow(botToken: string, chatId: number, urls: string[], content: string) {
  const url = urls[0]; // primary URL
  const sourceText = content || (url ? `Inhalt von: ${url}` : 'Content');

  // Generate promo
  const promo = await generatePromo(sourceText, url);
  const promoId = `promo_${Date.now()}_${chatId}`;

  pendingPromos.set(promoId, { chatId, promo, url });

  // Send with inline keyboard
  await callTelegramApi(botToken, 'sendMessage', {
    chat_id: chatId,
    text: `Promo-Vorschlag:\n\n${promo}`,
    reply_markup: {
      inline_keyboard: [
        [
          { text: 'Freigeben', callback_data: `approve:${promoId}` },
          { text: 'Neu generieren', callback_data: `regen:${promoId}` },
        ],
        [
          { text: 'Bearbeiten', callback_data: `edit:${promoId}` },
          { text: 'Verwerfen', callback_data: `reject:${promoId}` },
        ],
      ],
    },
  });
}

async function handleCallbackQuery(botToken: string, callback: any) {
  const data = callback.data || '';
  const chatId = callback.message?.chat?.id;
  const messageId = callback.message?.message_id;

  if (!chatId) return;

  const [action, promoId] = data.split(':');
  const pending = promoId ? pendingPromos.get(`${action === 'approve' || action === 'regen' || action === 'edit' || action === 'reject' ? '' : ''}${promoId}`) : undefined;

  // Re-construct key
  const fullKey = `${promoId}`;
  const promoData = pendingPromos.get(fullKey);

  // Acknowledge the callback
  await callTelegramApi(botToken, 'answerCallbackQuery', {
    callback_query_id: callback.id,
  }).catch(() => {});

  switch (action) {
    case 'approve': {
      if (!promoData) {
        await callTelegramApi(botToken, 'sendMessage', { chat_id: chatId, text: 'Promo nicht mehr verfuegbar.' });
        return;
      }

      if (TARGET_CHANNEL) {
        try {
          await callTelegramApi(botToken, 'sendMessage', {
            chat_id: TARGET_CHANNEL,
            text: promoData.promo,
            disable_web_page_preview: false,
          });
          await callTelegramApi(botToken, 'sendMessage', {
            chat_id: chatId,
            text: `Promo gepostet in Channel!`,
          });
        } catch (err: any) {
          await callTelegramApi(botToken, 'sendMessage', {
            chat_id: chatId,
            text: `Post-Fehler: ${err.message}\n\nPrüfe ob der Bot Admin im Channel ist.`,
          });
        }
      } else {
        await callTelegramApi(botToken, 'sendMessage', {
          chat_id: chatId,
          text: `Freigegeben! (Kein Ziel-Channel konfiguriert)\n\nSetze TELEGRAM_TARGET_CHANNEL in .env`,
        });
      }
      pendingPromos.delete(fullKey);
      break;
    }

    case 'regen': {
      if (!promoData) return;
      await sendTyping(botToken, chatId);
      const newPromo = await generatePromo(promoData.promo, promoData.url);
      promoData.promo = newPromo;

      await callTelegramApi(botToken, 'sendMessage', {
        chat_id: chatId,
        text: `Neuer Vorschlag:\n\n${newPromo}`,
        reply_markup: {
          inline_keyboard: [
            [
              { text: 'Freigeben', callback_data: `approve:${fullKey}` },
              { text: 'Neu generieren', callback_data: `regen:${fullKey}` },
            ],
            [
              { text: 'Bearbeiten', callback_data: `edit:${fullKey}` },
              { text: 'Verwerfen', callback_data: `reject:${fullKey}` },
            ],
          ],
        },
      });
      break;
    }

    case 'edit': {
      await callTelegramApi(botToken, 'sendMessage', {
        chat_id: chatId,
        text: 'Schick mir den bearbeiteten Text - ich poste ihn dann.',
      });
      // The next message will be treated as edited promo (handled via AI chat)
      break;
    }

    case 'reject': {
      pendingPromos.delete(fullKey);
      await callTelegramApi(botToken, 'sendMessage', {
        chat_id: chatId,
        text: 'Promo verworfen.',
      });
      break;
    }
  }
}

function splitMessage(text: string, maxLen: number): string[] {
  if (text.length <= maxLen) return [text];
  const chunks: string[] = [];
  let remaining = text;
  while (remaining.length > 0) {
    if (remaining.length <= maxLen) {
      chunks.push(remaining);
      break;
    }
    // Find last newline within limit
    let splitAt = remaining.lastIndexOf('\n', maxLen);
    if (splitAt < maxLen / 2) splitAt = maxLen;
    chunks.push(remaining.substring(0, splitAt));
    remaining = remaining.substring(splitAt).trimStart();
  }
  return chunks;
}

function mediaEmoji(type: string): string {
  const map: Record<string, string> = {
    photo: '[Foto]', video: '[Video]', document: '[Datei]', audio: '[Audio]',
    voice: '[Sprach]', video_note: '[VideoMsg]', sticker: '[Sticker]', animation: '[GIF]',
  };
  return map[type] ?? '[Medien]';
}

// --- Polling loop ---
async function pollUpdates(botToken: string) {
  let offset = 0;

  // Clear pending updates
  try {
    const pending = await callTelegramApi(botToken, 'getUpdates', { offset: -1, limit: 1, timeout: 0 });
    if (pending.length > 0) {
      offset = pending[pending.length - 1].update_id + 1;
    }
  } catch (_) {}

  const botName = process.env.BOT_PERSONA === 'harvey' ? 'HarveyHeavyLegalbot' : 'M0Claw';
  const providerInfo = process.env.OLLAMA_BASE_URL
    ? `Ollama @ ${process.env.OLLAMA_BASE_URL}`
    : process.env.ANTHROPIC_API_KEY
      ? 'Anthropic'
      : process.env.OPENAI_API_KEY
        ? `Groq/OpenAI @ ${process.env.AI_API_BASE || 'openai'}`
        : 'KEIN PROVIDER';
  console.log(`[${new Date().toISOString()}] ${botName} polling (offset=${offset})`);
  console.log(`Model   : ${process.env.AI_MODEL || 'standard'}`);
  console.log(`Provider: ${providerInfo}`);

  while (true) {
    try {
      const updates = await callTelegramApi(botToken, 'getUpdates', {
        offset,
        limit: 100,
        timeout: 30,
        allowed_updates: ['message', 'callback_query'],
      });

      for (const update of updates) {
        offset = update.update_id + 1;

        if (update.callback_query) {
          try {
            await handleCallbackQuery(botToken, update.callback_query);
          } catch (err: any) {
            console.error(`Callback error:`, err.message);
          }
        } else if (update.message) {
          try {
            await handleMessage(botToken, update.message);
          } catch (err: any) {
            console.error(`Message error ${update.update_id}:`, err.message);
          }
        }
      }
    } catch (err: any) {
      console.error(`[${new Date().toISOString()}] Poll error: ${err.message}`);
      await new Promise((r) => setTimeout(r, 5000));
    }
  }
}

// --- Main ---
const botToken = process.env.TELEGRAM_BOT_TOKEN;

if (!botToken) {
  console.error('TELEGRAM_BOT_TOKEN is required.');
  process.exit(1);
}

const botName = process.env.BOT_PERSONA === 'harvey' ? 'HarveyHeavyLegalbot' : 'M0Claw';
console.log(`Starting ${botName}...`);
pollUpdates(botToken).catch((err) => {
  console.error('Fatal:', err);
  process.exit(1);
});
