import { integrationCreate } from './account-create';
import { handleSchedule } from './schedule';
import { getTools, callTool } from './mcp';
import {
  IntegrationCLI,
  IntegrationEventPayload,
  IntegrationEventType,
  Spec,
} from '@redplanethq/sdk';

export async function run(eventPayload: IntegrationEventPayload) {
  switch (eventPayload.event) {
    case IntegrationEventType.SETUP:
      return await integrationCreate(eventPayload.eventBody);

    case IntegrationEventType.SYNC:
      return await handleSchedule(eventPayload.config, eventPayload.state);

    case IntegrationEventType.GET_TOOLS:
      return await getTools();

    case IntegrationEventType.CALL_TOOL: {
      const config = eventPayload.config as any;
      const { name, arguments: args } = eventPayload.eventBody;
      return await callTool(name, args, config?.bot_token);
    }

    default:
      return [
        {
          type: 'error',
          data: `Unknown event type: ${eventPayload.event}`,
        },
      ];
  }
}

class TelegramCLI extends IntegrationCLI {
  constructor() {
    super('telegram', '0.1.0');
  }

  protected async handleEvent(eventPayload: IntegrationEventPayload): Promise<any> {
    return await run(eventPayload);
  }

  protected async getSpec(): Promise<Spec> {
    return {
      name: 'Telegram Bot',
      key: 'telegram',
      description:
        'Connect your Telegram bot. Send messages, receive commands, manage channels, and integrate Telegram into your workflows.',
      icon: 'telegram',
      mcp: {
        type: 'cli',
      },
      schedule: {
        frequency: '*/1 * * * *', // Poll every minute for new messages
      },
      auth: {
        // Telegram uses Bot Token — no OAuth2 needed.
        // User provides their bot token from @BotFather during setup.
        config: [
          {
            name: 'token',
            title: 'Bot Token',
            description:
              'Your Telegram bot token from @BotFather (e.g. 123456:ABC-DEF...)',
            type: 'text',
            required: true,
            secret: true,
          },
        ],
      },
    } as any;
  }
}

function main() {
  const telegramCLI = new TelegramCLI();
  telegramCLI.parse();
}

main();
