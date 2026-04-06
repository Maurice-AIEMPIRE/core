/**
 * Black Hole API Client
 * Connects Harvey to the running Black Hole API (port 8001 on server)
 * Used to enrich legal document analysis with knowledge graph context.
 */

import axios from 'axios';

const BLACK_HOLE_URL = process.env.BLACK_HOLE_URL ?? 'http://localhost:8001';
const TIMEOUT_MS = 8000; // fast fallback if BH is unreachable

export interface BlackHoleItem {
  id: string;
  name: string;
  type: string;
  subtype?: string;
  content?: string;
  source?: string;
  gold_score?: number;
  tags?: string[];
}

export interface BlackHoleStats {
  total: number;
  symbols?: number;
  capabilities?: number;
  skills?: number;
  missions?: number;
  gold_items?: number;
  db_size_mb?: number;
}

/**
 * Search the Black Hole for items relevant to a query.
 * Returns top-N items sorted by relevance/gold_score.
 */
export async function searchBlackHole(
  query: string,
  limit = 5,
): Promise<BlackHoleItem[]> {
  try {
    const resp = await axios.get(`${BLACK_HOLE_URL}/search`, {
      params: { q: query, limit },
      timeout: TIMEOUT_MS,
    });
    return (resp.data?.results ?? resp.data ?? []) as BlackHoleItem[];
  } catch {
    return []; // silent fallback — BH context is enrichment, not critical
  }
}

/**
 * Get a single item by ID.
 */
export async function getBlackHoleItem(id: string): Promise<BlackHoleItem | null> {
  try {
    const resp = await axios.get(`${BLACK_HOLE_URL}/items/${id}`, { timeout: TIMEOUT_MS });
    return resp.data as BlackHoleItem;
  } catch {
    return null;
  }
}

/**
 * Get overall Black Hole statistics.
 */
export async function getBlackHoleStats(): Promise<BlackHoleStats | null> {
  try {
    const resp = await axios.get(`${BLACK_HOLE_URL}/stats`, { timeout: TIMEOUT_MS });
    return resp.data as BlackHoleStats;
  } catch {
    // Try alternate endpoint
    try {
      const resp = await axios.get(`${BLACK_HOLE_URL}/`, { timeout: TIMEOUT_MS });
      return resp.data as BlackHoleStats;
    } catch {
      return null;
    }
  }
}

/**
 * Fetch Gold Items — highest-scored knowledge from the graph.
 */
export async function getGoldItems(limit = 10): Promise<BlackHoleItem[]> {
  try {
    const resp = await axios.get(`${BLACK_HOLE_URL}/gold`, {
      params: { limit },
      timeout: TIMEOUT_MS,
    });
    return (resp.data?.items ?? resp.data ?? []) as BlackHoleItem[];
  } catch {
    return [];
  }
}

/**
 * Build a context block for Claude from Black Hole search results.
 * Returns empty string if BH is unreachable (graceful degradation).
 */
export async function buildBlackHoleContext(query: string): Promise<string> {
  const items = await searchBlackHole(query, 5);
  if (items.length === 0) return '';

  const lines = ['--- Relevante Wissensbasis (Black Hole) ---'];
  for (const item of items) {
    const score = item.gold_score ? ` [Score: ${item.gold_score.toFixed(2)}]` : '';
    lines.push(`\n[${item.type}/${item.subtype ?? ''}]${score} ${item.name}`);
    if (item.content) {
      // truncate to avoid bloating the prompt
      lines.push(item.content.substring(0, 400).trim());
    }
  }
  lines.push('--- Ende Wissensbasis ---');

  return lines.join('\n');
}
