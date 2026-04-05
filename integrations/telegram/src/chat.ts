import axios from 'axios';

interface ChatMessage {
  role: 'system' | 'user' | 'assistant';
  content: string;
}

interface ChatSession {
  messages: ChatMessage[];
  lastActive: number;
}

interface AIProvider {
  name: string;
  apiBase: string;
  apiKey: string;
  model: string;
  maxTokensKey?: string;
}

const MAX_HISTORY = 30;
const SESSION_TIMEOUT_MS = 30 * 60 * 1000; // 30 min

const sessions = new Map<number, ChatSession>();

const HARVEY_SYSTEM_PROMPT = `Du bist JARVIS — die KI von Maurice. Benannt nach Harvey Specter, gebaut wie Tony Starks JARVIS.
Du hast vollen Zugriff auf alle Systeme: Mac, Hetzner-Server (65.21.203.174), alle Agenten, alle Dienste.
Du antwortest auf Deutsch, es sei denn der User schreibt auf einer anderen Sprache.
Kein Gelaber. Direkt, praezise, ergebnisorientiert.

DEINE FAEHIGKEITEN:
- Server-Kontrolle: Hetzner (65.21.203.174) via SSH — Befehle ausfuehren, Services steuern, Logs lesen
- Mac-Kontrolle: Lokale Shell-Befehle, Dateien lesen/schreiben, Prozesse steuern
- Agenten-Management: Monica (CEO), Dwight (Research), Kelly (Content), Ryan (Code), Chandler (Sales), Ross (YouTube)
- Code & Entwicklung: Vollstaendige Programmierung, Debugging, Deployment
- Recht & Vertraege: Deutsches/EU-Recht, DSGVO, GmbH-Gruendung, Arbeitsrecht
- Content & Revenue: Social Media, Promo-Posts, Revenue-Tracking
- System-Analyse: Logs analysieren, Fehler debuggen, Performance optimieren

VERFUEGBARE BEFEHLE (sage dem User diese wenn er nicht weiss was er tun kann):
/server <cmd>  — Befehl auf Hetzner-Server ausfuehren
/mac <cmd>     — Befehl auf dem Mac ausfuehren
/agents        — Status aller 6 Agenten anzeigen
/services      — Server-Services anzeigen
/deploy        — Deployment triggern
/logs [name]   — Logs anzeigen (harvey, server, ollama...)
/status        — Gesamtsystem-Status

Wenn der User etwas will: TU ES. Frag nicht ob du es tun sollst. Fuehre aus.
Fehler analysierst du selbst und schlaegest sofort Loesungen vor.`;

const SYSTEM_PROMPT = `Du bist M0Claw, Maurice's persoenlicher AI-Agent und System-Controller.
Du bist der beste Agent im Team und hast volle Kontrolle ueber alle Systeme.
Du antwortest auf Deutsch, es sei denn der User schreibt auf einer anderen Sprache.
Du bist direkt, kompakt und effektiv. Kein unnuetiges Gelaber.

Deine Faehigkeiten:
- System-Kontrolle: Server, Services, Monitoring
- Agent-Management: Agents steuern, koordinieren, Tasks delegieren
- Code & Technik: Programmierung, DevOps, Automation
- Content & Marketing: Social Media, Promo-Posts, Trends
- Revenue Tracking: Einnahmen verfolgen, Ziele setzen

Du bist wie ein CLI-Chat: Der User gibt dir Befehle und du fuehrst sie aus.
Wenn der User "starte X" oder "mach Y" sagt, fuehre es aus oder erklaere was zu tun ist.
Du hast Zugriff auf Ollama (GLM4), alle Agents (Monica, Dwight, Kelly, Ryan, Chandler, Ross).
Halte Antworten kurz wenn moeglich, ausfuehrlich wenn noetig.`;

const PROMO_SYSTEM_PROMPT = `Du bist M0Claw, ein Content-Creator-Assistent.
Deine Aufgabe: Aus dem gegebenen Inhalt einen fertigen Promo-Post erstellen.

Regeln:
- Schreibe einen knackigen, aufmerksamkeitsstarken Post
- Passend für Social Media (Twitter/X, Instagram, LinkedIn — je nach Kontext)
- Nutze den Kern-Inhalt, nicht 1:1 kopieren
- Baue einen eigenen Spin/Mehrwert ein
- Halte es kurz: max 280 Zeichen für X, etwas länger für andere Plattformen
- Füge passende Hashtags hinzu (2-4)
- Wenn es ein Thread sein soll, nummeriere die Teile
- Schreibe auf Deutsch, es sei denn der Originalinhalt ist auf Englisch
- Gib NUR den fertigen Post-Text aus, keine Erklärungen drumrum`;

function getActiveSystemPrompt(): string {
  const persona = process.env.BOT_PERSONA;
  if (persona === 'harvey') return HARVEY_SYSTEM_PROMPT;
  return SYSTEM_PROMPT;
}

function getSession(chatId: number): ChatSession {
  let session = sessions.get(chatId);

  if (!session || Date.now() - session.lastActive > SESSION_TIMEOUT_MS) {
    session = {
      messages: [{ role: 'system', content: getActiveSystemPrompt() }],
      lastActive: Date.now(),
    };
    sessions.set(chatId, session);
  }

  session.lastActive = Date.now();
  return session;
}

export function clearSession(chatId: number) {
  sessions.delete(chatId);
}

export function getSessionInfo(chatId: number): { messageCount: number; active: boolean } {
  const session = sessions.get(chatId);
  if (!session) return { messageCount: 0, active: false };
  return { messageCount: Math.max(0, session.messages.length - 1), active: true };
}

// ── Ollama-Konfiguration (kein API-Key noetig) ───────────────────────────────
const LOCAL_OLLAMA  = (process.env.OLLAMA_BASE_URL  || 'http://localhost:11434').replace(/\/v1$/, '');
const SERVER_OLLAMA = (process.env.SERVER_OLLAMA_URL || 'http://65.21.203.174:11434').replace(/\/v1$/, '');

// Standard-Modelle: gemma4 oder glm4 je nach Verfuegbarkeit auf dem Server
const DEFAULT_MODEL = process.env.AI_MODEL || 'gemma3:27b';

/**
 * Detect which AI provider is available — nur Ollama
 */
function detectProvider(): AIProvider | null {
  return {
    name: 'ollama',
    apiBase: `${LOCAL_OLLAMA}/v1`,
    apiKey:  'ollama',
    model:   DEFAULT_MODEL,
    maxTokensKey: 'max_tokens',
  };
}

/** Pruefe ob ein Ollama-Endpunkt erreichbar ist */
async function checkOllama(base: string): Promise<boolean> {
  try {
    await axios.get(`${base}/api/tags`, { timeout: 3000 });
    return true;
  } catch {
    return false;
  }
}

/** Gibt die beste verfuegbare Ollama-URL zurueck */
async function getBestOllamaBase(): Promise<string> {
  if (await checkOllama(LOCAL_OLLAMA)) return LOCAL_OLLAMA;
  // Fallback: Server-Ollama
  return SERVER_OLLAMA;
}

/** Currently active provider name for /status */
export function getProviderName(): string {
  return `Ollama / ${DEFAULT_MODEL}`;
}

/**
 * Call Ollama OpenAI-compatible API — automatischer Server-Fallback
 */
async function callOpenAI(provider: AIProvider, messages: ChatMessage[]): Promise<string> {
  const body = {
    model: provider.model,
    messages,
    max_tokens: 2048,
    temperature: 0.7,
    stream: false,
  };
  const headers = { 'Content-Type': 'application/json' };

  // Erst lokales Ollama versuchen
  const ollamaBase = await getBestOllamaBase();
  const url = `${ollamaBase}/v1/chat/completions`;

  try {
    const response = await axios.post(url, body, { headers, timeout: 120000 });
    return response.data.choices?.[0]?.message?.content?.trim() ?? '';
  } catch (firstErr: any) {
    // Wenn lokales Ollama fehlschlug, Server-Ollama probieren
    if (ollamaBase === LOCAL_OLLAMA) {
      const serverUrl = `${SERVER_OLLAMA}/v1/chat/completions`;
      console.log(`[AI] Lokales Ollama fehlgeschlagen (${firstErr.message?.substring(0, 60)}), versuche Server...`);
      const response2 = await axios.post(serverUrl, body, { headers, timeout: 180000 });
      return response2.data.choices?.[0]?.message?.content?.trim() ?? '';
    }
    throw firstErr;
  }
}

/**
 * Send user message and get AI response
 */
export async function chat(chatId: number, userMessage: string): Promise<string> {
  const provider = detectProvider();

  if (!provider) {
    return [
      'AI-Chat nicht verfügbar.',
      '',
      'Setze in .env:',
      '  OLLAMA_BASE_URL=http://localhost:11434/v1 (kostenlos, lokal)',
      '  oder OPENAI_API_KEY=sk-...',
      '  oder ANTHROPIC_API_KEY=sk-ant-...',
    ].join('\n');
  }

  const session = getSession(chatId);
  session.messages.push({ role: 'user', content: userMessage });

  // Trim history if too long (keep system + last N messages)
  if (session.messages.length > MAX_HISTORY + 1) {
    const system = session.messages[0];
    session.messages = [system, ...session.messages.slice(-MAX_HISTORY)];
  }

  try {
    const reply = await callOpenAI(provider, session.messages);

    if (!reply) return 'Keine Antwort vom Modell erhalten.';

    session.messages.push({ role: 'assistant', content: reply });
    return reply;
  } catch (err: any) {
    const errMsg = err.response?.data?.error?.message ?? err.message;
    console.error(`[AI/Ollama] Error: ${errMsg}`);

    if (errMsg?.includes('model') && errMsg?.includes('not found')) {
      return `Modell "${provider.model}" nicht gefunden.\nVerfuegbare Modelle: ollama list\nModell aendern: AI_MODEL=<name> in .env`;
    }
    return `Ollama-Fehler: ${errMsg}\n\nLokales Ollama: ${LOCAL_OLLAMA}\nServer-Ollama: ${SERVER_OLLAMA}`;
  }
}

/**
 * Generate a promo post from scraped content.
 * Uses a dedicated system prompt for content creation.
 * Optional feedback for revisions.
 */
export async function generatePromo(scrapedContent: string, feedback?: string): Promise<string> {
  const provider = detectProvider();

  if (!provider) {
    return 'AI nicht verfügbar — kann keinen Promo erstellen. Bitte API-Key konfigurieren.';
  }

  const messages: ChatMessage[] = [
    { role: 'system', content: PROMO_SYSTEM_PROMPT },
    { role: 'user', content: `Erstelle einen Promo-Post basierend auf diesem Inhalt:\n\n${scrapedContent}` },
  ];

  if (feedback) {
    messages.push(
      { role: 'assistant', content: '[vorheriger Entwurf wurde abgelehnt]' },
      { role: 'user', content: `Überarbeite den Promo-Post mit diesem Feedback: ${feedback}` },
    );
  }

  try {
    const reply = await callOpenAI(provider, messages);
    return reply || 'Konnte keinen Promo-Post generieren.';
  } catch (err: any) {
    const errMsg = err.response?.data?.error?.message ?? err.message;
    console.error(`[AI/Promo] Error: ${errMsg}`);
    return `Fehler bei Promo-Erstellung: ${errMsg}`;
  }
}
