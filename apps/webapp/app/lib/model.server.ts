import {
  embed,
  generateText,
  generateObject,
  streamText,
  type ModelMessage,
} from "ai";
import { type z } from "zod";
import {
  createOpenAI,
  openai,
  type OpenAIResponsesProviderOptions,
} from "@ai-sdk/openai";
import { logger } from "~/services/logger.service";

import { createOllama } from "ollama-ai-provider-v2";
import { anthropic } from "@ai-sdk/anthropic";
import { google } from "@ai-sdk/google";

export type ModelComplexity = "high" | "low";

/**
 * Get the appropriate model for a given complexity level.
 * HIGH complexity uses the configured MODEL.
 * LOW complexity automatically downgrades to cheaper variants if possible.
 */
export function getModelForTask(complexity: ModelComplexity = "high"): string {
  const baseModel = process.env.MODEL || "gpt-4.1-2025-04-14";

  // HIGH complexity - always use the configured model
  if (complexity === "high") {
    return baseModel;
  }

  // Ollama models (local/cloud-proxied) have no cheaper variant — use as-is
  if (baseModel.startsWith("ollama/") || process.env.OLLAMA_URL) {
    return baseModel;
  }

  // LOW complexity - automatically downgrade expensive models to cheaper variants
  // If already using a cheap model, keep it
  const downgrades: Record<string, string> = {
    // OpenAI downgrades
    "gpt-5.2-2025-12-11": "gpt-5-mini-2025-08-07",
    "gpt-5.1-2025-11-13": "gpt-5-mini-2025-08-07",
    "gpt-5-2025-08-07": "gpt-5-mini-2025-08-07",
    "gpt-4.1-2025-04-14": "gpt-4.1-mini-2025-04-14",

    // Anthropic downgrades
    "claude-sonnet-4-5": "claude-3-5-haiku-20241022",
    "claude-3-7-sonnet-20250219": "claude-3-5-haiku-20241022",
    "claude-3-opus-20240229": "claude-3-5-haiku-20241022",

    // Google downgrades
    "gemini-2.5-pro-preview-03-25": "gemini-2.5-flash-preview-04-17",
    "gemini-2.0-flash": "gemini-2.0-flash-lite",

    // AWS Bedrock downgrades (keep same model - already cost-optimized)
    "us.amazon.nova-premier-v1:0": "us.amazon.nova-premier-v1:0",
  };

  return downgrades[baseModel] || baseModel;
}

export const getModel = (takeModel?: string) => {
  let model = takeModel;

  const anthropicKey = process.env.ANTHROPIC_API_KEY;
  const googleKey = process.env.GOOGLE_GENERATIVE_AI_API_KEY;
  const openaiKey = process.env.OPENAI_API_KEY;
  const ollamaUrl = process.env.OLLAMA_URL;
  model = model || process.env.MODEL || "gpt-4.1-2025-04-14";

  // Handle ollama/modelname format (used by OpenClaw gateway)
  if (model.startsWith("ollama/")) {
    const ollamaModelName = model.slice("ollama/".length);
    const baseURL = ollamaUrl || "http://localhost:11434";
    const ollama = createOllama({ baseURL });
    return ollama(ollamaModelName);
  }

  let modelInstance;

  // Use Ollama when OLLAMA_URL is configured
  if (ollamaUrl) {
    const ollama = createOllama({ baseURL: ollamaUrl });
    modelInstance = ollama(model);
    return modelInstance;
  }

  // Cloud providers
  if (model.includes("claude")) {
    if (!anthropicKey) {
      throw new Error("No Anthropic API key found. Set ANTHROPIC_API_KEY");
    }
    modelInstance = anthropic(model);
  } else if (model.includes("gemini")) {
    if (!googleKey) {
      throw new Error("No Google API key found. Set GOOGLE_GENERATIVE_AI_API_KEY");
    }
    modelInstance = google(model);
  } else {
    if (!openaiKey) {
      throw new Error("No OpenAI API key found. Set OPENAI_API_KEY");
    }
    modelInstance = openai.responses(model);
  }

  return modelInstance;
};

/**
 * Returns the ordered list of models to try: [primary, ...fallbacks].
 * Primary comes from getModelForTask(complexity), fallbacks from MODEL_FALLBACKS env var.
 */
export function getModelList(complexity: ModelComplexity = "high"): string[] {
  const primary = getModelForTask(complexity);
  const fallbacksRaw = process.env.MODEL_FALLBACKS ?? "";
  const fallbacks = fallbacksRaw
    .split(",")
    .map((m) => m.trim())
    .filter(Boolean);
  const seen = new Set<string>();
  return [primary, ...fallbacks].filter((m) => {
    if (seen.has(m)) return false;
    seen.add(m);
    return true;
  });
}

/**
 * Safely instantiate a model. Returns null if provider is not configured
 * (missing API key etc.) instead of throwing.
 */
function tryGetModel(modelName: string): ReturnType<typeof getModel> | null {
  try {
    return getModel(modelName);
  } catch (err) {
    logger.warn(`[model-rotation] cannot init "${modelName}": ${err}`);
    return null;
  }
}

/**
 * Quick reachability check for Ollama: returns true if the Ollama server
 * responds within 3 seconds. Does NOT check for a specific model name
 * because cloud-proxy models (e.g. glm-4.7:cloud) are always listed
 * even when they require an outbound connection.
 */
async function isOllamaReachable(baseURL: string): Promise<boolean> {
  try {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 3000);
    const res = await fetch(`${baseURL}/api/tags`, {
      signal: controller.signal,
    });
    clearTimeout(timer);
    return res.ok;
  } catch {
    return false;
  }
}

/**
 * Resolves the first model from `models` that can actually be used right now:
 * - provider config present (API key / Ollama URL)
 * - for Ollama models: server is reachable (3s timeout)
 * Returns `{ modelName, modelInstance }` or throws if all models are exhausted.
 */
async function resolveWorkingModel(
  models: string[],
  label: string,
): Promise<{ modelName: string; modelInstance: NonNullable<ReturnType<typeof getModel>> }> {
  let ollamaReachable: boolean | null = null; // cache the ping result

  for (const modelName of models) {
    const instance = tryGetModel(modelName);
    if (!instance) continue;

    if (modelName.startsWith("ollama/")) {
      const baseURL = process.env.OLLAMA_URL || "http://localhost:11434";
      if (ollamaReachable === null) {
        ollamaReachable = await isOllamaReachable(baseURL);
      }
      if (!ollamaReachable) {
        logger.warn(`[model-rotation] Ollama unreachable, skipping "${modelName}"`);
        continue;
      }
    }

    logger.info(`[model-rotation] "${modelName}" selected for ${label}`);
    return { modelName, modelInstance: instance };
  }

  throw new Error(
    `[model-rotation] all models exhausted for ${label}: ${models.join(", ")}`,
  );
}

/**
 * Convenience wrapper: resolves the first working model for a given complexity
 * and returns it as a LanguageModel ready for streamText / generateText.
 * Use this instead of bare `getModel()` to benefit from MODEL_FALLBACKS rotation.
 */
export async function getWorkingModel(
  complexity: ModelComplexity = "high",
  label = "call",
): Promise<{ modelName: string; model: ReturnType<typeof getModel> }> {
  const models = getModelList(complexity);
  const { modelName, modelInstance } = await resolveWorkingModel(models, label);
  return { modelName, model: modelInstance };
}

export interface TokenUsage {
  promptTokens?: number;
  completionTokens?: number;
  totalTokens?: number;
  cachedInputTokens?: number;
}

function buildOpenAIProviderOptions(
  model: string,
  cacheKey?: string,
  reasoningEffort?: "low" | "medium" | "high",
): Record<string, any> {
  if (!model.includes("gpt")) return {};

  const openaiOptions: OpenAIResponsesProviderOptions = {
    promptCacheKey: cacheKey || `ingestion-high`,
  };

  if (model.startsWith("gpt-5")) {
    if (model.includes("mini")) {
      openaiOptions.reasoningEffort = "low";
    } else {
      openaiOptions.promptCacheRetention = "24h";
      openaiOptions.reasoningEffort = reasoningEffort ?? "none";
    }
  }

  return { providerOptions: { openai: openaiOptions } };
}

export async function makeModelCall(
  stream: boolean,
  messages: ModelMessage[],
  onFinish: (text: string, model: string, usage?: TokenUsage) => void,
  options?: any,
  complexity: ModelComplexity = "high",
  cacheKey?: string,
  reasoningEffort?: "low" | "medium" | "high",
) {
  const models = getModelList(complexity);

  // ── Streaming path ────────────────────────────────────────────────────────
  // Resolve the first usable model upfront (Ollama ping included), then
  // hand the stream back. Mid-stream failures cannot be recovered from, but
  // at least config/connectivity errors are caught before the stream starts.
  if (stream) {
    const { modelName, modelInstance } = await resolveWorkingModel(
      models,
      `stream/${complexity}`,
    );
    const extraOptions = buildOpenAIProviderOptions(modelName, cacheKey, reasoningEffort);
    return streamText({
      model: modelInstance,
      messages,
      ...options,
      ...extraOptions,
      onFinish: async ({ text, usage }) => {
        const tokenUsage = usage
          ? {
              promptTokens: usage.inputTokens,
              completionTokens: usage.outputTokens,
              totalTokens: usage.totalTokens,
            }
          : undefined;
        if (tokenUsage) {
          logger.log(
            `[${complexity.toUpperCase()}] ${modelName} - Tokens: ${tokenUsage.totalTokens} (prompt: ${tokenUsage.promptTokens}, completion: ${tokenUsage.completionTokens})`,
          );
        }
        onFinish(text, modelName, tokenUsage);
      },
    });
  }

  // ── Non-streaming path — full try/catch rotation ──────────────────────────
  let lastError: unknown;

  for (const modelName of models) {
    const modelInstance = tryGetModel(modelName);
    if (!modelInstance) continue;

    const extraOptions = buildOpenAIProviderOptions(modelName, cacheKey, reasoningEffort);

    try {
      logger.info(`[model-rotation] trying "${modelName}" (${complexity})`);
      const { text, usage } = await generateText({
        model: modelInstance,
        messages,
        ...extraOptions,
      });

      const tokenUsage = usage
        ? {
            promptTokens: usage.inputTokens,
            completionTokens: usage.outputTokens,
            totalTokens: usage.totalTokens,
            cachedInputTokens: usage.cachedInputTokens,
          }
        : undefined;

      if (tokenUsage) {
        logger.log(
          `[${complexity.toUpperCase()}] ${modelName} - Tokens: ${tokenUsage.totalTokens} (prompt: ${tokenUsage.promptTokens}, completion: ${tokenUsage.completionTokens}, cached: ${tokenUsage.cachedInputTokens})`,
        );
      }

      onFinish(text, modelName, tokenUsage);
      return text;
    } catch (err) {
      lastError = err;
      logger.warn(`[model-rotation] "${modelName}" failed: ${err} — trying next`);
    }
  }

  throw lastError ?? new Error(`All models failed: ${models.join(", ")}`);
}

/**
 * Make a model call that returns structured data using a Zod schema.
 * Uses AI SDK's generateObject for guaranteed structured output.
 */
export async function makeStructuredModelCall<T extends z.ZodType>(
  schema: T,
  messages: ModelMessage[],
  complexity: ModelComplexity = "high",
  cacheKey?: string,
  temperature?: number,
): Promise<{ object: z.infer<T>; usage: TokenUsage | undefined }> {
  const models = getModelList(complexity);
  let lastError: unknown;

  for (const modelName of models) {
    const modelInstance = tryGetModel(modelName);
    if (!modelInstance) continue;

    const generateObjectOptions: any = {};
    if (temperature !== undefined) {
      generateObjectOptions.temperature = temperature;
    }

    if (modelName.includes("gpt")) {
      const openaiOptions: OpenAIResponsesProviderOptions = {
        promptCacheKey: cacheKey || `structured-${complexity}`,
        strictJsonSchema: false,
      };
      if (modelName.startsWith("gpt-5")) {
        if (modelName.includes("mini")) {
          openaiOptions.reasoningEffort = "low";
        } else {
          openaiOptions.promptCacheRetention = "24h";
          openaiOptions.reasoningEffort = "none";
        }
      }
      generateObjectOptions.providerOptions = { openai: openaiOptions };
    }

    try {
      logger.info(`[model-rotation] [Structured] trying "${modelName}" (${complexity})`);
      const { object, usage } = await generateObject({
        model: modelInstance,
        schema,
        messages,
        ...generateObjectOptions,
      });

      const tokenUsage = usage
        ? {
            promptTokens: usage.inputTokens,
            completionTokens: usage.outputTokens,
            totalTokens: usage.totalTokens,
            cachedInputTokens: usage.cachedInputTokens,
          }
        : undefined;

      if (tokenUsage) {
        logger.log(
          `[Structured/${complexity.toUpperCase()}] ${modelName} - Tokens: ${tokenUsage.totalTokens} (prompt: ${tokenUsage.promptTokens}, completion: ${tokenUsage.completionTokens}, cached: ${tokenUsage.cachedInputTokens})`,
        );
      }

      return { object: object as any, usage: tokenUsage };
    } catch (err) {
      lastError = err;
      logger.warn(`[model-rotation] [Structured] "${modelName}" failed: ${err} — trying next`);
    }
  }

  throw lastError ?? new Error(`All models failed (structured): ${models.join(", ")}`);
}

/**
 * Determines if a given model is proprietary (OpenAI, Anthropic, Google, Grok)
 * or open source (accessed via Bedrock, Ollama, etc.)
 */
export function isProprietaryModel(
  modelName?: string,
  complexity: ModelComplexity = "high",
): boolean {
  const model = modelName || getModelForTask(complexity);
  if (!model) return false;

  // Ollama models (local or cloud-proxied via ollama/) are never proprietary
  if (model.startsWith("ollama/") || process.env.OLLAMA_URL) return false;

  // Proprietary model patterns
  const proprietaryPatterns = [
    /^gpt-/, // OpenAI models
    /^claude-/, // Anthropic models
    /^gemini-/, // Google models
    /^grok-/, // xAI models
  ];

  return proprietaryPatterns.some((pattern) => pattern.test(model));
}

export async function getEmbedding(text: string) {
  const ollamaUrl = process.env.OLLAMA_URL;
  const model = process.env.EMBEDDING_MODEL;
  const maxRetries = 3;
  let lastEmbedding: number[] = [];

  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      if (model === "text-embedding-3-small") {
        // Use OpenAI embedding model when explicitly requested
        const { embedding } = await embed({
          model: openai.embedding("text-embedding-3-small"),
          value: text,
        });
        lastEmbedding = embedding;
      } else {
        // Use Ollama's OpenAI-compatible endpoint for embeddings
        // This avoids EmbeddingModelV3/V2 compatibility issues with third-party providers
        // Normalize the URL: remove trailing slash, /api, and /v1 if present, then add /v1
        const baseUrl = ollamaUrl
          ?.replace(/\/+$/, "")
          .replace(/\/v1$/, "")
          .replace(/\/api$/, "");
        const ollamaOpenAI = createOpenAI({
          baseURL: `${baseUrl}/v1`,
          apiKey: "ollama", // Required but not used by Ollama
        });
        const { embedding } = await embed({
          model: ollamaOpenAI.embedding(model as string),
          value: text,
        });
        lastEmbedding = embedding;
      }

      // If embedding is not empty, return it immediately
      if (lastEmbedding.length > 0) {
        return lastEmbedding;
      }

      // If empty, log and retry (unless it's the last attempt)
      if (attempt < maxRetries) {
        logger.warn(
          `Attempt ${attempt}/${maxRetries}: Got empty embedding, retrying...`,
        );
      }
    } catch (error) {
      logger.error(
        `Embedding attempt ${attempt}/${maxRetries} failed: ${error}`,
      );
    }
  }

  // Return last embedding even if empty after all retries
  logger.warn(
    `All ${maxRetries} attempts returned empty embedding, returning last response`,
  );
  return lastEmbedding;
}
