import axios from 'axios';

interface TelegramConfig {
  bot_token: string;
  bot_id?: string;
  bot_username?: string;
}

interface TelegramState {
  lastUpdateId?: number;
}

const TELEGRAM_API = 'https://api.telegram.org';

function telegramUrl(token: string, method: string): string {
  return `${TELEGRAM_API}/bot${token}/${method}`;
}

function createActivityMessage(update: any, botUsername: string) {
  const msg = update.message || update.edited_message || update.channel_post;
  if (!msg) return null;

  const chatId = msg.chat.id;
  const chatTitle =
    msg.chat.title || msg.chat.username || `Chat ${chatId}`;
  const sender =
    msg.from?.username ||
    `${msg.from?.first_name ?? ''} ${msg.from?.last_name ?? ''}`.trim() ||
    'Unknown';
  const text = msg.text || msg.caption || '[media/sticker/file]';
  const date = new Date(msg.date * 1000).toLocaleString();

  // Skip messages from the bot itself
  if (msg.from?.username === botUsername) return null;

  const sourceURL = msg.chat.username
    ? `https://t.me/${msg.chat.username}/${msg.message_id}`
    : `https://t.me/c/${String(chatId).replace('-100', '')}/${msg.message_id}`;

  const body = `## 💬 Telegram Message in ${chatTitle}

**From:** @${sender}
**Time:** ${date}

${text.substring(0, 500)}${text.length > 500 ? '...' : ''}`;

  return {
    type: 'activity',
    data: { text: body, sourceURL },
  };
}

export async function handleSchedule(
  config?: Record<string, string>,
  state?: Record<string, string>,
) {
  if (!config?.bot_token) return [];

  const token = config.bot_token;
  const botUsername = config.bot_username ?? '';
  const currentState = (state ?? {}) as TelegramState;

  // Use offset = lastUpdateId + 1 so we never re-process the same update
  const offset =
    currentState.lastUpdateId != null ? currentState.lastUpdateId + 1 : 0;

  let updates: any[] = [];
  try {
    const response = await axios.get(telegramUrl(token, 'getUpdates'), {
      params: { offset, limit: 100, timeout: 0 },
      timeout: 10_000,
    });
    if (response.data.ok) {
      updates = response.data.result ?? [];
    }
  } catch (error) {
    console.error('Telegram getUpdates failed:', error);
    return [];
  }

  if (updates.length === 0) {
    return [{ type: 'state', data: { ...currentState } }];
  }

  const activities: any[] = [];
  let maxUpdateId = currentState.lastUpdateId ?? -1;

  for (const update of updates) {
    maxUpdateId = Math.max(maxUpdateId, update.update_id);
    const activity = createActivityMessage(update, botUsername);
    if (activity) activities.push(activity);
  }

  activities.push({
    type: 'state',
    data: { ...currentState, lastUpdateId: maxUpdateId },
  });

  return activities;
}
