/**
 * Stripe Webhook Server — Auto Payment Activation
 *
 * Listens for Stripe events and automatically activates Harvey Premium
 * when payment is confirmed — no more manual /paid commands.
 *
 * Setup:
 *   1. Create Stripe Payment Link with metadata: { telegram_user_id: "12345" }
 *      OR use Stripe Checkout with client_reference_id = telegram_user_id
 *   2. In Stripe Dashboard → Developers → Webhooks → Add endpoint
 *      URL: https://your-server/stripe/webhook
 *      Events: checkout.session.completed, customer.subscription.created
 *   3. Set STRIPE_WEBHOOK_SECRET env var
 *
 * Start: npx tsx src/stripe_webhook.ts
 * Port:  STRIPE_WEBHOOK_PORT (default 3001)
 */

import * as http from 'http';
import * as crypto from 'crypto';
import * as fs from 'fs';
import * as path from 'path';

const PORT = parseInt(process.env.STRIPE_WEBHOOK_PORT ?? '3001', 10);
const STRIPE_WEBHOOK_SECRET = process.env.STRIPE_WEBHOOK_SECRET ?? '';
const TELEGRAM_BOT_TOKEN = process.env.TELEGRAM_BOT_TOKEN ?? '';

// Reuse same usage dir as legal_review.ts
const USAGE_DIR = path.join(process.env.HOME ?? '/tmp', '.openclaw', 'legal_usage');

// ── Stripe signature verification ────────────────────────────────────────────

function verifyStripeSignature(payload: string, sigHeader: string, secret: string): boolean {
  if (!secret) return true; // skip in dev (no secret set)

  const parts: Record<string, string> = {};
  for (const part of sigHeader.split(',')) {
    const [k, v] = part.split('=');
    parts[k] = v;
  }

  const timestamp = parts['t'];
  const sig = parts['v1'];
  if (!timestamp || !sig) return false;

  // Reject events older than 5 minutes
  const age = Math.abs(Date.now() / 1000 - parseInt(timestamp, 10));
  if (age > 300) return false;

  const expected = crypto
    .createHmac('sha256', secret)
    .update(`${timestamp}.${payload}`)
    .digest('hex');

  return crypto.timingSafeEqual(Buffer.from(expected), Buffer.from(sig));
}

// ── User activation ───────────────────────────────────────────────────────────

function activateUser(telegramUserId: string | number) {
  if (!fs.existsSync(USAGE_DIR)) fs.mkdirSync(USAGE_DIR, { recursive: true });

  const file = path.join(USAGE_DIR, `${telegramUserId}.json`);
  let usage: Record<string, unknown> = { userId: Number(telegramUserId), freeUsed: 0, reviewCount: 0 };

  if (fs.existsSync(file)) {
    try { usage = JSON.parse(fs.readFileSync(file, 'utf-8')); } catch { /* keep defaults */ }
  }

  usage.paid = true;
  usage.paidSince = new Date().toISOString();
  fs.writeFileSync(file, JSON.stringify(usage, null, 2));

  console.log(`[Webhook] Activated Premium for Telegram user ${telegramUserId}`);
}

async function sendTelegramMessage(chatId: string | number, text: string) {
  if (!TELEGRAM_BOT_TOKEN) return;
  try {
    const body = JSON.stringify({ chat_id: chatId, text });
    await fetch(`https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body,
    });
  } catch (e) {
    console.error('[Webhook] Telegram notify failed:', e);
  }
}

// ── Event handlers ────────────────────────────────────────────────────────────

async function handleCheckoutCompleted(session: Record<string, unknown>) {
  // Telegram user ID can be passed via:
  //   1. client_reference_id (Stripe Checkout)
  //   2. metadata.telegram_user_id (Payment Links)
  const telegramId =
    (session.client_reference_id as string) ??
    ((session.metadata as Record<string, string>)?.telegram_user_id);

  if (!telegramId) {
    console.warn('[Webhook] checkout.session.completed — no telegram_user_id in metadata');
    return;
  }

  activateUser(telegramId);

  await sendTelegramMessage(
    telegramId,
    [
      'Zahlung bestätigt! Harvey Premium ist jetzt aktiv.',
      '',
      'Du hast unbegrenzte Dokument-Analysen.',
      'Schick einfach ein PDF, DOCX oder TXT.',
      '',
      '/credits — Status anzeigen',
    ].join('\n'),
  );
}

async function handleSubscriptionCreated(subscription: Record<string, unknown>) {
  const metadata = subscription.metadata as Record<string, string> | undefined;
  const telegramId = metadata?.telegram_user_id;
  if (!telegramId) return;
  activateUser(telegramId);
}

// ── HTTP Server ───────────────────────────────────────────────────────────────

const server = http.createServer(async (req, res) => {
  if (req.method === 'GET' && req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', port: PORT }));
    return;
  }

  if (req.method !== 'POST' || !req.url?.startsWith('/stripe/webhook')) {
    res.writeHead(404);
    res.end();
    return;
  }

  // Read body
  const chunks: Buffer[] = [];
  for await (const chunk of req) chunks.push(chunk as Buffer);
  const payload = Buffer.concat(chunks).toString('utf-8');

  // Verify signature
  const sig = req.headers['stripe-signature'] as string ?? '';
  if (STRIPE_WEBHOOK_SECRET && !verifyStripeSignature(payload, sig, STRIPE_WEBHOOK_SECRET)) {
    console.warn('[Webhook] Invalid Stripe signature — rejected');
    res.writeHead(400);
    res.end('Invalid signature');
    return;
  }

  let event: { type: string; data: { object: Record<string, unknown> } };
  try {
    event = JSON.parse(payload);
  } catch {
    res.writeHead(400);
    res.end('Invalid JSON');
    return;
  }

  console.log(`[Webhook] Event: ${event.type}`);

  try {
    switch (event.type) {
      case 'checkout.session.completed':
        await handleCheckoutCompleted(event.data.object);
        break;
      case 'customer.subscription.created':
      case 'customer.subscription.updated':
        await handleSubscriptionCreated(event.data.object);
        break;
      default:
        console.log(`[Webhook] Unhandled event: ${event.type}`);
    }
  } catch (e) {
    console.error('[Webhook] Handler error:', e);
  }

  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ received: true }));
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`[Stripe Webhook] Listening on http://0.0.0.0:${PORT}/stripe/webhook`);
  console.log(`[Stripe Webhook] Health: http://0.0.0.0:${PORT}/health`);
  if (!STRIPE_WEBHOOK_SECRET) {
    console.warn('[Stripe Webhook] WARNING: STRIPE_WEBHOOK_SECRET not set — skipping signature check');
  }
  if (!TELEGRAM_BOT_TOKEN) {
    console.warn('[Stripe Webhook] WARNING: TELEGRAM_BOT_TOKEN not set — can\'t notify users');
  }
});
