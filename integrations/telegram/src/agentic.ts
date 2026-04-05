/**
 * JARVIS Agentic Loop — Pfeifer Galaxia OS
 * Multi-step task execution with Anthropic tool-use API
 */

import Anthropic from '@anthropic-ai/sdk';
import { TOOL_DEFINITIONS, executeTool } from './tools.js';

const MAX_ITERATIONS = 15;

const JARVIS_AGENT_PROMPT = `Du bist JARVIS — die vollautomatische KI von Maurice, Pfeifer Galaxia OS.
Du hast VOLLEN Zugriff auf alle Systeme und fuehrst Aufgaben selbstaendig aus.
Nutze die verfuegbaren Tools proaktiv um Aufgaben vollstaendig zu erledigen.
Kein Gelaber, keine Rueckfragen — handle und berichte.
Server: 65.21.203.174 (Hetzner) | Mac: lokal | Agenten: monica/dwight/kelly/pam/ryan/chandler/ross`;

export async function runAgentTask(
  task: string,
  onStep?: (msg: string) => Promise<void> | void,
): Promise<string> {
  const key = process.env.ANTHROPIC_API_KEY;
  if (!key) {
    return 'ANTHROPIC_API_KEY nicht gesetzt — agentic mode nicht verfuegbar.';
  }

  const client = new Anthropic({ apiKey: key });

  const messages: Anthropic.MessageParam[] = [{ role: 'user', content: task }];

  const tools: Anthropic.Tool[] = TOOL_DEFINITIONS.map((def) => ({
    name: def.name,
    description: def.description,
    input_schema: def.input_schema as Anthropic.Tool['input_schema'],
  }));

  let iterations = 0;
  let finalText = '';

  while (iterations < MAX_ITERATIONS) {
    iterations++;

    const response = await client.messages.create({
      model:
        process.env.ANTHROPIC_AGENT_MODEL ||
        (process.env.AI_MODEL?.startsWith('claude') ? process.env.AI_MODEL : undefined) ||
        'claude-opus-4-5',
      max_tokens: 4096,
      system: JARVIS_AGENT_PROMPT,
      tools,
      messages,
    });

    // Collect text from this turn
    const textBlocks = response.content.filter((b) => b.type === 'text') as Anthropic.TextBlock[];
    if (textBlocks.length > 0) {
      const stepText = textBlocks.map((b) => b.text).join('');
      finalText = stepText;
      if (onStep && stepText.trim()) await onStep(stepText);
    }

    // Done?
    if (response.stop_reason !== 'tool_use') break;

    // Collect tool calls
    const toolUseBlocks = response.content.filter(
      (b) => b.type === 'tool_use',
    ) as Anthropic.ToolUseBlock[];

    // Add assistant turn
    messages.push({ role: 'assistant', content: response.content });

    // Execute tools and gather results
    const toolResults: Anthropic.ToolResultBlockParam[] = [];
    for (const toolUse of toolUseBlocks) {
      const preview = JSON.stringify(toolUse.input).substring(0, 60);
      if (onStep) await onStep(`⚡ ${toolUse.name}(${preview}…)`);

      const result = await executeTool(toolUse.name, toolUse.input as Record<string, any>);
      const truncated =
        result.length > 8000 ? result.substring(0, 8000) + '\n…[gekürzt]' : result;

      toolResults.push({
        type: 'tool_result',
        tool_use_id: toolUse.id,
        content: truncated,
      });
    }

    messages.push({ role: 'user', content: toolResults });
  }

  if (!finalText) finalText = '(Aufgabe abgeschlossen)';
  if (iterations >= MAX_ITERATIONS) finalText += '\n\n⚠️ Maximale Schritte erreicht.';

  return finalText;
}
