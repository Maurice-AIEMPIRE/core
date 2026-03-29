/**
 * GalaxiaBrain — Unified Brain Client
 *
 * The single API that every subsystem uses to read from and write to
 * the central CORE memory server (PostgreSQL + Neo4j + pgvector).
 *
 * All brains feed into CORE, all brains pull from CORE.
 * Finale documents are pushed to iCloud Drive via the Mac Brain webhook.
 *
 * Config via env:
 *   GALAXIA_BRAIN_URL   — CORE server URL, e.g. http://65.21.203.174:3033
 *   GALAXIA_BRAIN_TOKEN — JWT API token from CORE Settings → API Key
 *   MAC_BRAIN_URL       — Mac Brain webhook URL, e.g. http://localhost:9001
 */

export type BrainSource =
  | "openclaw"
  | "galaxia"
  | "claude-code"
  | "mac"
  | "telegram"
  | "system";

export interface MemoryResult {
  id: string;
  content: string;
  score: number;
  source: string;
  timestamp: string;
  metadata?: Record<string, unknown>;
}

export interface RememberOptions {
  metadata?: Record<string, string | number | boolean>;
  sessionId?: string;
  title?: string;
  type?: "CONVERSATION" | "DOCUMENT";
  labelIds?: string[];
}

export interface RecallOptions {
  limit?: number;
  startTime?: string;
  endTime?: string;
  labelIds?: string[];
  sortBy?: "relevance" | "recency";
}

export class GalaxiaBrain {
  private readonly baseUrl: string;
  private readonly token: string;
  private readonly macBrainUrl: string;

  constructor(options?: {
    baseUrl?: string;
    token?: string;
    macBrainUrl?: string;
  }) {
    this.baseUrl = options?.baseUrl ?? process.env.GALAXIA_BRAIN_URL ?? "http://localhost:3033";
    this.token = options?.token ?? process.env.GALAXIA_BRAIN_TOKEN ?? "";
    this.macBrainUrl = options?.macBrainUrl ?? process.env.MAC_BRAIN_URL ?? "http://localhost:9001";

    if (!this.token) {
      console.warn(
        "[GalaxiaBrain] No token configured. Set GALAXIA_BRAIN_TOKEN env var."
      );
    }
  }

  private get headers(): Record<string, string> {
    return {
      "Content-Type": "application/json",
      Authorization: `Bearer ${this.token}`,
    };
  }

  /**
   * Store a memory in the central CORE brain.
   * Returns the queue ID of the ingestion job.
   */
  async remember(
    content: string,
    source: BrainSource,
    options: RememberOptions = {}
  ): Promise<string> {
    const body = {
      episodeBody: content,
      referenceTime: new Date().toISOString(),
      source,
      type: options.type ?? "CONVERSATION",
      sessionId: options.sessionId,
      title: options.title,
      labelIds: options.labelIds,
      metadata: {
        brain: source,
        ...options.metadata,
      },
    };

    const res = await fetch(`${this.baseUrl}/api/v1/add`, {
      method: "POST",
      headers: this.headers,
      body: JSON.stringify(body),
    });

    if (!res.ok) {
      const text = await res.text();
      throw new Error(`[GalaxiaBrain.remember] ${res.status}: ${text}`);
    }

    const data = (await res.json()) as { success: boolean; id: string };
    return data.id;
  }

  /**
   * Search memories using vector + graph hybrid search.
   */
  async recall(query: string, options: RecallOptions = {}): Promise<MemoryResult[]> {
    const body = {
      query,
      limit: options.limit ?? 10,
      startTime: options.startTime,
      endTime: options.endTime,
      labelIds: options.labelIds,
      sortBy: options.sortBy ?? "relevance",
      adaptiveFiltering: true,
      structured: true,
    };

    const res = await fetch(`${this.baseUrl}/api/v1/search`, {
      method: "POST",
      headers: this.headers,
      body: JSON.stringify(body),
    });

    if (!res.ok) {
      const text = await res.text();
      throw new Error(`[GalaxiaBrain.recall] ${res.status}: ${text}`);
    }

    const data = (await res.json()) as { results: MemoryResult[] };
    return data.results ?? [];
  }

  /**
   * AI-synthesized deep search — returns a human-readable answer
   * synthesized from all relevant memories.
   */
  async deepSearch(query: string): Promise<string> {
    const body = {
      content: query,
      stream: false,
      metadata: { source: "galaxia-brain" },
    };

    const res = await fetch(`${this.baseUrl}/api/v1/deep-search`, {
      method: "POST",
      headers: this.headers,
      body: JSON.stringify(body),
    });

    if (!res.ok) {
      const text = await res.text();
      throw new Error(`[GalaxiaBrain.deepSearch] ${res.status}: ${text}`);
    }

    const data = (await res.json()) as { text: string };
    return data.text ?? "";
  }

  /**
   * Generate a final document and push it to:
   * 1. CORE memory as DOCUMENT type
   * 2. iCloud Drive via Mac Brain SSH bridge
   */
  async generateDocument(
    title: string,
    content: string,
    folder = "GalaxiaBrain"
  ): Promise<void> {
    // 1. Store in CORE as permanent document
    await this.remember(content, "system", {
      type: "DOCUMENT",
      title,
      metadata: { folder, icloud: "true" },
    });

    // 2. Push to iCloud Drive via Mac Brain
    const res = await fetch(`${this.macBrainUrl}/write-document`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ title, content, folder }),
    }).catch((err) => {
      console.warn(
        `[GalaxiaBrain.generateDocument] Mac Brain not reachable: ${err.message}`
      );
      return null;
    });

    if (res && !res.ok) {
      const text = await res.text();
      console.warn(`[GalaxiaBrain.generateDocument] Mac Brain error: ${text}`);
    }
  }

  /**
   * Register a webhook with CORE so it notifies external services on new activities.
   */
  async registerWebhook(url: string, secret?: string): Promise<string> {
    const res = await fetch(`${this.baseUrl}/api/v1/webhooks`, {
      method: "POST",
      headers: this.headers,
      body: JSON.stringify({
        url,
        secret,
        eventTypes: ["activity.created"],
      }),
    });

    if (!res.ok) {
      const text = await res.text();
      throw new Error(`[GalaxiaBrain.registerWebhook] ${res.status}: ${text}`);
    }

    const data = (await res.json()) as { webhook: { id: string } };
    return data.webhook.id;
  }
}

// Singleton for direct imports
export const brain = new GalaxiaBrain();
