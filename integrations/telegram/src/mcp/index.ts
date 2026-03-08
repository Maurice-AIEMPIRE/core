import axios, { AxiosInstance } from 'axios';
import { z } from 'zod';
import { zodToJsonSchema } from 'zod-to-json-schema';

const TELEGRAM_API = 'https://api.telegram.org';

let client: AxiosInstance;
let botToken: string;

function initClient(token: string) {
  botToken = token;
  client = axios.create({ baseURL: `${TELEGRAM_API}/bot${token}` });
}

async function tg(method: string, data?: Record<string, any>) {
  const response = await client.post(`/${method}`, data ?? {});
  if (!response.data.ok) {
    throw new Error(`Telegram API [${method}]: ${response.data.description}`);
  }
  return response.data.result;
}

// ── Schemas ──────────────────────────────────────────────────────────────────

const SendMessageSchema = z.object({
  chat_id: z.union([z.string(), z.number()]).describe('Chat ID or @username'),
  text: z.string().describe('Message text (supports Markdown/HTML)'),
  parse_mode: z
    .enum(['Markdown', 'MarkdownV2', 'HTML'])
    .optional()
    .describe('Text formatting mode'),
  reply_to_message_id: z
    .number()
    .optional()
    .describe('Reply to a specific message ID'),
  disable_notification: z
    .boolean()
    .optional()
    .describe('Send silently without notification'),
});

const SendPhotoSchema = z.object({
  chat_id: z.union([z.string(), z.number()]).describe('Chat ID or @username'),
  photo: z.string().describe('URL of the photo or file_id'),
  caption: z.string().optional().describe('Caption for the photo'),
  parse_mode: z.enum(['Markdown', 'MarkdownV2', 'HTML']).optional(),
});

const EditMessageSchema = z.object({
  chat_id: z.union([z.string(), z.number()]).describe('Chat ID'),
  message_id: z.number().describe('ID of the message to edit'),
  text: z.string().describe('New message text'),
  parse_mode: z.enum(['Markdown', 'MarkdownV2', 'HTML']).optional(),
});

const DeleteMessageSchema = z.object({
  chat_id: z.union([z.string(), z.number()]).describe('Chat ID'),
  message_id: z.number().describe('ID of the message to delete'),
});

const PinMessageSchema = z.object({
  chat_id: z.union([z.string(), z.number()]).describe('Chat ID'),
  message_id: z.number().describe('ID of the message to pin'),
  disable_notification: z.boolean().optional(),
});

const GetChatInfoSchema = z.object({
  chat_id: z.union([z.string(), z.number()]).describe('Chat ID or @username'),
});

const GetChatMembersSchema = z.object({
  chat_id: z.union([z.string(), z.number()]).describe('Chat ID'),
});

const GetUpdatesSchema = z.object({
  offset: z.number().optional().describe('Update ID offset'),
  limit: z.number().optional().default(20).describe('Max updates to fetch (1-100)'),
});

const ForwardMessageSchema = z.object({
  chat_id: z.union([z.string(), z.number()]).describe('Target chat ID'),
  from_chat_id: z.union([z.string(), z.number()]).describe('Source chat ID'),
  message_id: z.number().describe('ID of the message to forward'),
});

const SendDocumentSchema = z.object({
  chat_id: z.union([z.string(), z.number()]).describe('Chat ID'),
  document: z.string().describe('URL of the document or file_id'),
  caption: z.string().optional(),
});

// ── Tool registry ─────────────────────────────────────────────────────────────

const TOOLS = [
  {
    name: 'send_message',
    description: 'Send a text message to a Telegram chat or channel',
    inputSchema: zodToJsonSchema(SendMessageSchema),
  },
  {
    name: 'send_photo',
    description: 'Send a photo to a Telegram chat',
    inputSchema: zodToJsonSchema(SendPhotoSchema),
  },
  {
    name: 'edit_message',
    description: 'Edit an existing message in a chat',
    inputSchema: zodToJsonSchema(EditMessageSchema),
  },
  {
    name: 'delete_message',
    description: 'Delete a message from a chat',
    inputSchema: zodToJsonSchema(DeleteMessageSchema),
  },
  {
    name: 'pin_message',
    description: 'Pin a message in a chat',
    inputSchema: zodToJsonSchema(PinMessageSchema),
  },
  {
    name: 'get_chat_info',
    description: 'Get information about a chat, group, or channel',
    inputSchema: zodToJsonSchema(GetChatInfoSchema),
  },
  {
    name: 'get_chat_member_count',
    description: 'Get the number of members in a chat',
    inputSchema: zodToJsonSchema(GetChatMembersSchema),
  },
  {
    name: 'get_updates',
    description: 'Fetch recent Telegram updates (messages, commands)',
    inputSchema: zodToJsonSchema(GetUpdatesSchema),
  },
  {
    name: 'forward_message',
    description: 'Forward a message from one chat to another',
    inputSchema: zodToJsonSchema(ForwardMessageSchema),
  },
  {
    name: 'send_document',
    description: 'Send a file/document to a chat',
    inputSchema: zodToJsonSchema(SendDocumentSchema),
  },
  {
    name: 'get_bot_info',
    description: 'Get information about the connected Telegram bot',
    inputSchema: zodToJsonSchema(z.object({})),
  },
];

export async function getTools() {
  return TOOLS;
}

export async function callTool(
  name: string,
  args: Record<string, any>,
  token: string,
) {
  initClient(token);

  try {
    switch (name) {
      case 'send_message': {
        const v = SendMessageSchema.parse(args);
        const result = await tg('sendMessage', {
          chat_id: v.chat_id,
          text: v.text,
          parse_mode: v.parse_mode,
          reply_to_message_id: v.reply_to_message_id,
          disable_notification: v.disable_notification,
        });
        return {
          content: [
            {
              type: 'text',
              text: `Message sent. ID: ${result.message_id} | Chat: ${result.chat.id}`,
            },
          ],
        };
      }

      case 'send_photo': {
        const v = SendPhotoSchema.parse(args);
        const result = await tg('sendPhoto', {
          chat_id: v.chat_id,
          photo: v.photo,
          caption: v.caption,
          parse_mode: v.parse_mode,
        });
        return {
          content: [
            { type: 'text', text: `Photo sent. ID: ${result.message_id}` },
          ],
        };
      }

      case 'edit_message': {
        const v = EditMessageSchema.parse(args);
        await tg('editMessageText', {
          chat_id: v.chat_id,
          message_id: v.message_id,
          text: v.text,
          parse_mode: v.parse_mode,
        });
        return {
          content: [{ type: 'text', text: 'Message updated successfully' }],
        };
      }

      case 'delete_message': {
        const v = DeleteMessageSchema.parse(args);
        await tg('deleteMessage', {
          chat_id: v.chat_id,
          message_id: v.message_id,
        });
        return {
          content: [{ type: 'text', text: 'Message deleted' }],
        };
      }

      case 'pin_message': {
        const v = PinMessageSchema.parse(args);
        await tg('pinChatMessage', {
          chat_id: v.chat_id,
          message_id: v.message_id,
          disable_notification: v.disable_notification,
        });
        return {
          content: [{ type: 'text', text: 'Message pinned' }],
        };
      }

      case 'get_chat_info': {
        const v = GetChatInfoSchema.parse(args);
        const result = await tg('getChat', { chat_id: v.chat_id });
        return {
          content: [
            {
              type: 'text',
              text: `Chat: ${result.title ?? result.username ?? result.first_name}
ID: ${result.id}
Type: ${result.type}
Members: ${result.members_count ?? 'N/A'}
Description: ${result.description ?? 'N/A'}`,
            },
          ],
        };
      }

      case 'get_chat_member_count': {
        const v = GetChatMembersSchema.parse(args);
        const count = await tg('getChatMemberCount', { chat_id: v.chat_id });
        return {
          content: [{ type: 'text', text: `Member count: ${count}` }],
        };
      }

      case 'get_updates': {
        const v = GetUpdatesSchema.parse(args);
        const updates = await tg('getUpdates', {
          offset: v.offset,
          limit: v.limit,
        });
        const summary = updates
          .map((u: any) => {
            const msg = u.message || u.edited_message || u.channel_post;
            if (!msg) return `Update ${u.update_id}: [non-message event]`;
            const sender =
              msg.from?.username ?? msg.from?.first_name ?? 'unknown';
            return `[${u.update_id}] @${sender}: ${(msg.text ?? '[media]').substring(0, 80)}`;
          })
          .join('\n');
        return {
          content: [
            {
              type: 'text',
              text: updates.length
                ? `${updates.length} update(s):\n${summary}`
                : 'No new updates',
            },
          ],
        };
      }

      case 'forward_message': {
        const v = ForwardMessageSchema.parse(args);
        const result = await tg('forwardMessage', {
          chat_id: v.chat_id,
          from_chat_id: v.from_chat_id,
          message_id: v.message_id,
        });
        return {
          content: [
            { type: 'text', text: `Message forwarded. New ID: ${result.message_id}` },
          ],
        };
      }

      case 'send_document': {
        const v = SendDocumentSchema.parse(args);
        const result = await tg('sendDocument', {
          chat_id: v.chat_id,
          document: v.document,
          caption: v.caption,
        });
        return {
          content: [
            { type: 'text', text: `Document sent. ID: ${result.message_id}` },
          ],
        };
      }

      case 'get_bot_info': {
        const result = await tg('getMe');
        return {
          content: [
            {
              type: 'text',
              text: `Bot: @${result.username} (ID: ${result.id})
Name: ${result.first_name}
Can join groups: ${result.can_join_groups}
Can read all messages: ${result.can_read_all_group_messages}`,
            },
          ],
        };
      }

      default:
        throw new Error(`Unknown tool: ${name}`);
    }
  } catch (error: any) {
    return {
      content: [
        {
          type: 'text',
          text: `Error: ${error.message}`,
        },
      ],
    };
  }
}
