/**
 * JARVIS Agentic Loop — Pfeifer Galaxia OS
 * Multi-step tool-use via Ollama OpenAI-compatible API (kein API-Key noetig)
 */

import axios from 'axios';
import { TOOL_DEFINITIONS, executeTool } from './tools.js';

const MAX_ITERATIONS = 15;

/** Ollama-Basis-URL (local zuerst, dann Server-Fallback) */
function getOllamaBase(): string {
  // Wenn OLLAMA_BASE_URL gesetzt, nutze das (aber ohne /v1 doppelt)
  const base = process.env.OLLAMA_BASE_URL || 'http://localhost:11434';
  return base.endsWith('/v1') ? base : `${base}/v1`;
}

/** Welches Modell hat Tool-Support? Bevorzuge grosse Modelle. */
function getAgentModel(): string {
  const m = process.env.AGENT_MODEL || process.env.AI_MODEL || '';
  // Modelle mit bekanntem Tool-Support in Ollama
  const toolModels = ['qwen3:32b', 'qwen2.5:32b', 'llama4', 'llama3.3:70b', 'llama3.1:70b', 'qwen2.5:14b', 'qwen3:14b'];
  if (m && toolModels.some((t) => m.toLowerCase().includes(t.split(':')[0]))) return m;
  return m || 'qwen3:32b';
}

/** Konvertiere Anthropic-Format → OpenAI/Ollama-Format */
function toOllamaTools(defs: typeof TOOL_DEFINITIONS) {
  return defs.map((d) => ({
    type: 'function' as const,
    function: {
      name: d.name,
      description: d.description,
      parameters: d.input_schema,
    },
  }));
}

const JARVIS_SYSTEM = `Du bist JARVIS — die vollautomatische KI von Maurice, Pfeifer Galaxia OS.
Du hast VOLLEN Zugriff auf alle Systeme und fuehrst Aufgaben selbstaendig aus.
Nutze die Tools proaktiv, um Aufgaben vollstaendig zu erledigen. Antworte auf Deutsch.
Server: 65.21.203.174 (Hetzner) | Mac: lokal | Agenten: monica/dwight/kelly/pam/ryan/chandler/ross`;

type OllamaMessage =
  | { role: 'system' | 'user' | 'assistant'; content: string }
  | { role: 'tool'; tool_call_id: string; name: string; content: string }
  | { role: 'assistant'; content: string | null; tool_calls: OllamaToolCall[] };

interface OllamaToolCall {
  id: string;
  type: 'function';
  function: { name: string; arguments: string };
}

export async function runAgentTask(
  task: string,
  onStep?: (msg: string) => Promise<void> | void,
): Promise<string> {
  const ollamaBase = getOllamaBase();
  const model = getAgentModel();
  const tools = toOllamaTools(TOOL_DEFINITIONS);

  const messages: OllamaMessage[] = [
    { role: 'system', content: JARVIS_SYSTEM },
    { role: 'user',   content: task },
  ];

  let iterations = 0;
  let finalText = '';

  while (iterations < MAX_ITERATIONS) {
    iterations++;

    let response: any;
    try {
      const res = await axios.post(
        `${ollamaBase}/chat/completions`,
        { model, messages, tools, stream: false },
        { timeout: 120000 },
      );
      response = res.data;
    } catch (err: any) {
      // Fallback: Server-Ollama
      if (!ollamaBase.includes('65.21.203.174')) {
        const serverBase = `http://65.21.203.174:11434/v1`;
        if (onStep) await onStep(`⚠️ Lokales Ollama nicht erreichbar, versuche Server…`);
        const res2 = await axios.post(
          `${serverBase}/chat/completions`,
          { model, messages, tools, stream: false },
          { timeout: 180000 },
        );
        response = res2.data;
      } else {
        throw new Error(`Ollama nicht erreichbar: ${err.message}`);
      }
    }

    const choice = response.choices?.[0];
    if (!choice) break;

    const msg = choice.message;
    const finishReason: string = choice.finish_reason || 'stop';

    // Text-Inhalt sammeln
    if (msg.content) {
      finalText = msg.content;
      if (onStep && msg.content.trim()) await onStep(msg.content);
    }

    // Fertig?
    if (finishReason !== 'tool_calls' || !msg.tool_calls?.length) break;

    // Assistant-Turn mit tool_calls hinzufuegen
    messages.push({ role: 'assistant', content: msg.content ?? null, tool_calls: msg.tool_calls });

    // Tools ausfuehren
    for (const tc of msg.tool_calls as OllamaToolCall[]) {
      let input: Record<string, any> = {};
      try {
        input = JSON.parse(tc.function.arguments || '{}');
      } catch {}

      const preview = tc.function.arguments?.substring(0, 60) ?? '';
      if (onStep) await onStep(`⚡ ${tc.function.name}(${preview}…)`);

      const result = await executeTool(tc.function.name, input);
      const truncated = result.length > 8000 ? result.substring(0, 8000) + '\n…[gekuerzt]' : result;

      messages.push({
        role: 'tool',
        tool_call_id: tc.id,
        name: tc.function.name,
        content: truncated,
      });
    }
  }

  if (!finalText) finalText = '(Aufgabe abgeschlossen)';
  if (iterations >= MAX_ITERATIONS) finalText += '\n\n⚠️ Maximale Schritte erreicht.';
  return finalText;
}
