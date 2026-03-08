import axios from 'axios';

/**
 * Validate bot token and fetch bot info from Telegram API.
 * Called during SETUP event when user provides their bot token.
 */
export async function integrationCreate(data: any) {
  const { token } = data;

  if (!token) {
    throw new Error('Telegram bot token is required');
  }

  // Validate token by calling getMe
  let botInfo: any = null;
  try {
    const response = await axios.get(
      `https://api.telegram.org/bot${token}/getMe`,
    );
    if (!response.data.ok) {
      throw new Error(`Telegram API error: ${response.data.description}`);
    }
    botInfo = response.data.result;
  } catch (error: any) {
    throw new Error(
      `Invalid bot token or Telegram API unreachable: ${error.message}`,
    );
  }

  const integrationConfiguration = {
    bot_token: token,
    bot_id: String(botInfo.id),
    bot_username: botInfo.username,
    bot_name: botInfo.first_name,
    can_join_groups: botInfo.can_join_groups ?? false,
    can_read_all_group_messages: botInfo.can_read_all_group_messages ?? false,
  };

  return [
    {
      type: 'account',
      data: {
        settings: {},
        accountId: String(botInfo.id),
        config: integrationConfiguration,
      },
    },
  ];
}
