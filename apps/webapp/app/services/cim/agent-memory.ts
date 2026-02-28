/**
 * Agent Long-Term Memory (MEMORY.md equivalent)
 *
 * Manages persistent, curated agent memory that evolves over time.
 * Unlike the in-memory ExternalMemoryStore, this persists to the database
 * and survives across sessions.
 *
 * Memory categories:
 *   - preferences: User/agent preferences learned over time
 *   - hard_lessons: Mistakes that must never be repeated
 *   - rules: Behavioral rules from user feedback
 *   - patterns: Successful patterns to reuse
 *   - bad_patterns: Patterns the agent documents as failures
 */

import { prisma } from "~/db.server";
import { logger } from "~/services/logger.service";

import type {
  AgentMemoryEntry,
  AgentMemoryCategory,
  AgentMemorySource,
} from "./types";
import { estimateTokens } from "./memory-manager";

// ---------------------------------------------------------------------------
// Write Operations
// ---------------------------------------------------------------------------

export async function addMemory(
  agentId: string,
  userId: string,
  workspaceId: string,
  memory: {
    category: AgentMemoryCategory;
    content: string;
    priority?: number;
    permanent?: boolean;
    source?: AgentMemorySource;
  },
): Promise<AgentMemoryEntry> {
  const record = await prisma.agentMemory.create({
    data: {
      agentId,
      userId,
      workspaceId,
      category: memory.category,
      content: memory.content,
      priority: memory.priority ?? 0,
      permanent: memory.permanent ?? false,
      source: memory.source ?? "observation",
    },
  });

  logger.info(
    `[CIM:AgentMemory] Added memory for agent ${agentId}: category=${memory.category}`,
  );

  return toMemoryEntry(record);
}

export async function addHardLesson(
  agentId: string,
  userId: string,
  workspaceId: string,
  lesson: string,
  source: AgentMemorySource = "user_feedback",
): Promise<AgentMemoryEntry> {
  return addMemory(agentId, userId, workspaceId, {
    category: "hard_lessons",
    content: lesson,
    priority: 10,
    permanent: true,
    source,
  });
}

export async function addRule(
  agentId: string,
  userId: string,
  workspaceId: string,
  rule: string,
  source: AgentMemorySource = "user_feedback",
): Promise<AgentMemoryEntry> {
  return addMemory(agentId, userId, workspaceId, {
    category: "rules",
    content: rule,
    priority: 8,
    permanent: false,
    source,
  });
}

export async function addBadPattern(
  agentId: string,
  userId: string,
  workspaceId: string,
  pattern: string,
): Promise<AgentMemoryEntry> {
  return addMemory(agentId, userId, workspaceId, {
    category: "bad_patterns",
    content: pattern,
    priority: 7,
    permanent: false,
    source: "self_correction",
  });
}

// ---------------------------------------------------------------------------
// Read Operations
// ---------------------------------------------------------------------------

export async function getMemories(
  agentId: string,
  options: {
    category?: AgentMemoryCategory;
    limit?: number;
    activeOnly?: boolean;
  } = {},
): Promise<AgentMemoryEntry[]> {
  const { category, limit = 50, activeOnly = true } = options;

  const records = await prisma.agentMemory.findMany({
    where: {
      agentId,
      ...(category ? { category } : {}),
      ...(activeOnly ? { active: true } : {}),
    },
    orderBy: [{ priority: "desc" }, { createdAt: "desc" }],
    take: limit,
  });

  return records.map(toMemoryEntry);
}

export async function getMemoriesWithinBudget(
  agentId: string,
  maxTokens: number,
): Promise<AgentMemoryEntry[]> {
  const allMemories = await getMemories(agentId, { limit: 200 });

  const result: AgentMemoryEntry[] = [];
  let totalTokens = 0;

  for (const memory of allMemories) {
    const tokens = estimateTokens(memory.content);
    if (totalTokens + tokens > maxTokens) break;
    result.push(memory);
    totalTokens += tokens;
  }

  return result;
}

// ---------------------------------------------------------------------------
// Update Operations
// ---------------------------------------------------------------------------

export async function deactivateMemory(memoryId: string): Promise<void> {
  await prisma.agentMemory.update({
    where: { id: memoryId },
    data: { active: false },
  });

  logger.info(`[CIM:AgentMemory] Deactivated memory ${memoryId}`);
}

export async function updateMemoryPriority(
  memoryId: string,
  priority: number,
): Promise<void> {
  await prisma.agentMemory.update({
    where: { id: memoryId },
    data: { priority },
  });
}

// ---------------------------------------------------------------------------
// Memory Prompt Generation
// ---------------------------------------------------------------------------

export function formatMemoriesAsPrompt(memories: AgentMemoryEntry[]): string {
  if (memories.length === 0) return "";

  const grouped = new Map<string, AgentMemoryEntry[]>();
  for (const m of memories) {
    const group = grouped.get(m.category) || [];
    group.push(m);
    grouped.set(m.category, group);
  }

  const categoryLabels: Record<AgentMemoryCategory, string> = {
    preferences: "Preferences",
    hard_lessons: "Hard Lessons (NEVER repeat these)",
    rules: "Rules (ALWAYS follow)",
    patterns: "Successful Patterns",
    bad_patterns: "BAD Patterns (AVOID these)",
  };

  const sections: string[] = ["## Long-Term Memory"];

  for (const [category, entries] of grouped) {
    const label = categoryLabels[category as AgentMemoryCategory] || category;
    sections.push(`\n### ${label}`);
    for (const entry of entries) {
      sections.push(`- ${entry.content}`);
    }
  }

  return sections.join("\n");
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function toMemoryEntry(record: {
  id: string;
  category: string;
  content: string;
  priority: number;
  permanent: boolean;
  active: boolean;
  source: string | null;
  createdAt: Date;
  updatedAt: Date;
}): AgentMemoryEntry {
  return {
    id: record.id,
    category: record.category as AgentMemoryCategory,
    content: record.content,
    priority: record.priority,
    permanent: record.permanent,
    active: record.active,
    source: (record.source as AgentMemorySource) ?? "observation",
    createdAt: record.createdAt,
    updatedAt: record.updatedAt,
  };
}
