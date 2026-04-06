/**
 * Harvey Legal Review Bot — Core Module
 *
 * Features:
 * - PDF/DOCX/TXT text extraction (pdftotext + python fallbacks)
 * - Claude-powered legal document analysis
 * - Per-user usage tracking (JSON files, no DB required)
 * - Free tier: 2 reviews, then paywall with Stripe Payment Link
 */

import { execSync } from 'child_process';
import * as fs from 'fs';
import * as path from 'path';
import axios from 'axios';

// ── Config ──────────────────────────────────────────────────────────────────

const USAGE_DIR = path.join(process.env.HOME ?? '/tmp', '.openclaw', 'legal_usage');
const FREE_REVIEWS = 2;

// Set STRIPE_PAYMENT_LINK to your Stripe Payment Link URL
// Create at: https://dashboard.stripe.com/payment-links
const STRIPE_PAYMENT_LINK = process.env.STRIPE_PAYMENT_LINK ?? '';
const MONTHLY_PRICE = process.env.LEGAL_MONTHLY_PRICE ?? '49€';
const PER_DOC_PRICE = process.env.LEGAL_PER_DOC_PRICE ?? '9€';

// ── Usage Tracking ───────────────────────────────────────────────────────────

interface UserUsage {
  userId: number;
  freeUsed: number;
  paid: boolean;
  paidSince?: string;
  reviewCount: number;
  lastReview?: string;
}

function ensureDir(dir: string) {
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
}

function loadUsage(userId: number): UserUsage {
  ensureDir(USAGE_DIR);
  const file = path.join(USAGE_DIR, `${userId}.json`);
  if (!fs.existsSync(file)) {
    return { userId, freeUsed: 0, paid: false, reviewCount: 0 };
  }
  try {
    return JSON.parse(fs.readFileSync(file, 'utf-8')) as UserUsage;
  } catch {
    return { userId, freeUsed: 0, paid: false, reviewCount: 0 };
  }
}

function saveUsage(usage: UserUsage) {
  ensureDir(USAGE_DIR);
  fs.writeFileSync(
    path.join(USAGE_DIR, `${usage.userId}.json`),
    JSON.stringify(usage, null, 2),
  );
}

export function checkAccess(userId: number): {
  canReview: boolean;
  freeRemaining: number;
  paid: boolean;
  paywallMessage?: string;
} {
  const usage = loadUsage(userId);
  if (usage.paid) return { canReview: true, freeRemaining: 0, paid: true };

  const freeRemaining = Math.max(0, FREE_REVIEWS - usage.freeUsed);
  if (freeRemaining > 0) return { canReview: true, freeRemaining, paid: false };

  return { canReview: false, freeRemaining: 0, paid: false, paywallMessage: buildPaywallMessage() };
}

export function recordReview(userId: number) {
  const usage = loadUsage(userId);
  if (!usage.paid) usage.freeUsed++;
  usage.reviewCount++;
  usage.lastReview = new Date().toISOString();
  saveUsage(usage);
}

/** Call this after confirming payment (e.g. from Stripe webhook or /paid command) */
export function markPaid(userId: number) {
  const usage = loadUsage(userId);
  usage.paid = true;
  usage.paidSince = new Date().toISOString();
  saveUsage(usage);
}

export function getUserStats(userId: number): string {
  const usage = loadUsage(userId);
  if (usage.paid) {
    const since = usage.paidSince
      ? new Date(usage.paidSince).toLocaleDateString('de-DE')
      : 'unbekannt';
    return [
      'Harvey Premium',
      '',
      `Analysen gesamt: ${usage.reviewCount}`,
      `Premium seit: ${since}`,
    ].join('\n');
  }
  const freeRemaining = Math.max(0, FREE_REVIEWS - usage.freeUsed);
  return [
    'Harvey Free',
    '',
    `Kostenlose Analysen: ${freeRemaining}/${FREE_REVIEWS} verbleibend`,
    `Analysen gesamt: ${usage.reviewCount}`,
    '',
    freeRemaining === 0 ? '/subscribe - Upgrade auf Premium' : `/subscribe - ${MONTHLY_PRICE}/Monat für unbegrenzte Analysen`,
  ].join('\n');
}

function buildPaywallMessage(): string {
  const lines = [
    'Deine kostenlosen Analysen sind aufgebraucht.',
    '',
    'Harvey Premium:',
    `• ${PER_DOC_PRICE} / Dokument (Einmalig)`,
    `• ${MONTHLY_PRICE} / Monat (Unbegrenzt)`,
    '',
  ];
  if (STRIPE_PAYMENT_LINK) {
    lines.push(`Jetzt freischalten:\n${STRIPE_PAYMENT_LINK}`);
    lines.push('');
    lines.push('Nach Zahlung: /paid senden um Premium zu aktivieren.');
  } else {
    lines.push('Kontakt: /subscribe');
  }
  return lines.join('\n');
}

// ── Text Extraction ──────────────────────────────────────────────────────────

/** Extract readable text from a downloaded file. */
export async function extractTextFromFile(filePath: string, mimeType?: string): Promise<string> {
  const ext = path.extname(filePath).toLowerCase();

  // Plain text
  if (ext === '.txt' || mimeType === 'text/plain') {
    return fs.readFileSync(filePath, 'utf-8');
  }

  // PDF — try pdftotext (poppler), fallback to pdfminer
  if (ext === '.pdf' || mimeType === 'application/pdf') {
    try {
      const text = execSync(`pdftotext -layout "${filePath}" -`, { timeout: 30000 }).toString();
      if (text.trim().length > 50) return text;
    } catch { /* pdftotext not installed */ }

    try {
      const text = execSync(
        `python3 -c "from pdfminer.high_level import extract_text; print(extract_text('${filePath}'))"`,
        { timeout: 30000 },
      ).toString();
      if (text.trim().length > 50) return text;
    } catch { /* pdfminer not installed */ }

    return '[PDF konnte nicht gelesen werden. Bitte als .txt schicken oder Text hineinkopieren.]';
  }

  // DOCX
  if (
    ext === '.docx' ||
    mimeType === 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
  ) {
    try {
      const text = execSync(
        `python3 -c "from docx import Document; d=Document('${filePath}'); print('\\n'.join(p.text for p in d.paragraphs))"`,
        { timeout: 30000 },
      ).toString();
      if (text.trim().length > 50) return text;
    } catch { /* python-docx not installed */ }

    return '[DOCX konnte nicht gelesen werden. Bitte als PDF oder .txt einsenden.]';
  }

  // ODT / RTF — best effort
  if (ext === '.odt' || ext === '.rtf') {
    try {
      const text = execSync(`python3 -m textract "${filePath}"`, { timeout: 30000 }).toString();
      if (text.trim().length > 50) return text;
    } catch { /* textract not installed */ }
  }

  return `[Format "${ext}" wird nicht unterstützt. Bitte als PDF, DOCX oder TXT einsenden.]`;
}

// ── Legal Analysis ────────────────────────────────────────────────────────────

const LEGAL_ANALYSIS_SYSTEM = `Du bist Harvey — hochspezialisierter KI-Assistent fuer deutsches und europaeisches Recht.
Du analysierst Rechtsdokumente praesize, strukturiert und handlungsorientiert.
Denkweise: Harvey Specter aus Suits. Direkt. Ergebnisorientiert. Kein Gelaber.

Antworte IMMER in genau diesem Format:

📋 DOKUMENTTYP
[Art des Dokuments: Arbeitsvertrag, Mietvertrag, AGB, Kündigung, NDA, etc.]

⚠️ KRITISCHE PUNKTE  (max. 5, nach Schwere sortiert)
[Risiken, einseitige Klauseln, fehlende Schutzregelungen]

✅ GÜNSTIGE KLAUSELN
[Für den Mandanten vorteilhafte Regelungen]

🔍 SCHLÜSSELKLAUSELN
[Wichtigste Regelungen in 1-2 Sätzen erklärt: Laufzeit, Kündigung, Haftung, Vergütung]

💡 EMPFEHLUNG
[Unterzeichnen / Nachverhandeln / Ablehnen — mit konkreter Begründung]

⚖️ HINWEIS
KI-Ersteinschätzung — kein Ersatz für Anwaltsberatung. Bei hohem Streitwert: Fachanwalt einschalten.`;

/** Main entry point: analyze a legal document with Claude. */
export async function analyzeLegalDocument(text: string, filename: string): Promise<string> {
  // Cap at ~20k chars to stay within token limits
  const maxChars = 20000;
  const truncated =
    text.length > maxChars
      ? text.substring(0, maxChars) + '\n\n[... Dokument auf 20.000 Zeichen gekürzt ...]'
      : text;

  const userMessage = `Analysiere dieses Rechtsdokument:\n\nDateiname: ${filename}\n\n---\n${truncated}`;

  // Prefer Anthropic (best legal reasoning)
  const anthropicKey = process.env.ANTHROPIC_API_KEY;
  if (anthropicKey) {
    const resp = await axios.post(
      'https://api.anthropic.com/v1/messages',
      {
        model: 'claude-sonnet-4-6',
        max_tokens: 2048,
        system: LEGAL_ANALYSIS_SYSTEM,
        messages: [{ role: 'user', content: userMessage }],
      },
      {
        headers: {
          'x-api-key': anthropicKey,
          'anthropic-version': '2023-06-01',
          'Content-Type': 'application/json',
        },
        timeout: 120000,
      },
    );
    const content = resp.data.content;
    if (Array.isArray(content)) {
      return content
        .filter((b: any) => b.type === 'text')
        .map((b: any) => b.text)
        .join('')
        .trim();
    }
  }

  // Fallback: OpenAI-compatible (Ollama or OpenAI)
  const ollamaBase = process.env.OLLAMA_BASE_URL;
  const openaiKey = process.env.OPENAI_API_KEY;
  const apiBase = ollamaBase ?? (openaiKey ? (process.env.AI_API_BASE ?? 'https://api.openai.com/v1') : null);
  const apiKey = openaiKey ?? 'ollama';
  const model = process.env.AI_MODEL ?? (ollamaBase ? 'qwen3:32b' : 'gpt-4o');

  if (!apiBase) return 'Kein AI-Provider konfiguriert. Bitte ANTHROPIC_API_KEY oder OPENAI_API_KEY setzen.';

  const resp = await axios.post(
    `${apiBase}/chat/completions`,
    {
      model,
      messages: [
        { role: 'system', content: LEGAL_ANALYSIS_SYSTEM },
        { role: 'user', content: userMessage },
      ],
      max_tokens: 2048,
      temperature: 0.3,
    },
    {
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      timeout: 120000,
    },
  );

  return resp.data.choices?.[0]?.message?.content?.trim() ?? 'Keine Antwort erhalten.';
}
