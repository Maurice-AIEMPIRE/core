/**
 * Shared Context Manager (shared-context/ equivalent)
 *
 * Cross-agent knowledge layer. A single source of truth that every
 * agent reads at session start.
 *
 * Context types:
 *   - thesis: Current worldview / beliefs (THESIS.md)
 *   - feedback: Cross-agent corrections (FEEDBACK-LOG.md)
 *   - signals: Trends and articles being tracked (SIGNALS.md)
 *   - custom: User-defined shared context
 *
 * One-writer rule: Each shared context entry has an optional writerId.
 * Only the designated writer agent can update it.
 */

import { prisma } from "~/db.server";
import { logger } from "~/services/logger.service";

import type { SharedContextEntry, SharedContextType } from "./types";
import { estimateTokens } from "./memory-manager";

// ---------------------------------------------------------------------------
// Read Operations
// ---------------------------------------------------------------------------

export async function getSharedContext(
  workspaceId: string,
  contextType?: SharedContextType,
): Promise<SharedContextEntry[]> {
  const records = await prisma.sharedContext.findMany({
    where: {
      workspaceId,
      ...(contextType ? { contextType } : {}),
    },
    orderBy: { updatedAt: "desc" },
  });

  return records.map(toSharedContextEntry);
}

export async function getSharedContextWithinBudget(
  workspaceId: string,
  maxTokens: number,
): Promise<SharedContextEntry[]> {
  const allContext = await getSharedContext(workspaceId);

  const result: SharedContextEntry[] = [];
  let totalTokens = 0;

  for (const ctx of allContext) {
    const tokens = estimateTokens(ctx.content);
    if (totalTokens + tokens > maxTokens) break;
    result.push(ctx);
    totalTokens += tokens;
  }

  return result;
}

// ---------------------------------------------------------------------------
// Write Operations (respects one-writer rule)
// ---------------------------------------------------------------------------

export async function upsertSharedContext(
  userId: string,
  workspaceId: string,
  contextType: SharedContextType,
  content: string,
  options: {
    title?: string;
    writerId?: string;
  } = {},
): Promise<SharedContextEntry> {
  // Check one-writer rule
  if (options.writerId) {
    const existing = await prisma.sharedContext.findFirst({
      where: {
        workspaceId,
        contextType,
        title: options.title ?? undefined,
      },
    });

    if (
      existing &&
      existing.writerId &&
      existing.writerId !== options.writerId
    ) {
      throw new Error(
        `One-writer rule violation: context "${contextType}" is owned by agent ${existing.writerId}, ` +
          `but agent ${options.writerId} tried to write.`,
      );
    }
  }

  // Upsert: find existing by type+title or create new
  const existing = await prisma.sharedContext.findFirst({
    where: {
      workspaceId,
      contextType,
      ...(options.title ? { title: options.title } : {}),
    },
  });

  let record;
  if (existing) {
    record = await prisma.sharedContext.update({
      where: { id: existing.id },
      data: { content, writerId: options.writerId },
    });
  } else {
    record = await prisma.sharedContext.create({
      data: {
        userId,
        workspaceId,
        contextType,
        title: options.title,
        content,
        writerId: options.writerId,
      },
    });
  }

  logger.info(
    `[CIM:SharedContext] ${existing ? "Updated" : "Created"} shared context: ` +
      `type=${contextType}, title=${options.title || "(none)"}`,
  );

  return toSharedContextEntry(record);
}

export async function deleteSharedContext(
  contextId: string,
  requestingWriterId?: string,
): Promise<void> {
  if (requestingWriterId) {
    const existing = await prisma.sharedContext.findUnique({
      where: { id: contextId },
    });

    if (existing?.writerId && existing.writerId !== requestingWriterId) {
      throw new Error(
        `One-writer rule violation: cannot delete context owned by agent ${existing.writerId}`,
      );
    }
  }

  await prisma.sharedContext.delete({ where: { id: contextId } });
  logger.info(`[CIM:SharedContext] Deleted shared context ${contextId}`);
}

// ---------------------------------------------------------------------------
// Prompt Generation
// ---------------------------------------------------------------------------

export function formatSharedContextAsPrompt(
  contexts: SharedContextEntry[],
): string {
  if (contexts.length === 0) return "";

  const grouped = new Map<string, SharedContextEntry[]>();
  for (const ctx of contexts) {
    const group = grouped.get(ctx.contextType) || [];
    group.push(ctx);
    grouped.set(ctx.contextType, group);
  }

  const typeLabels: Record<SharedContextType, string> = {
    thesis: "Current Worldview (THESIS)",
    feedback: "Cross-Agent Corrections (FEEDBACK)",
    signals: "Tracked Signals",
    custom: "Shared Knowledge",
  };

  const sections: string[] = ["## Shared Context (All Agents)"];

  for (const [type, entries] of grouped) {
    const label = typeLabels[type as SharedContextType] || type;
    sections.push(`\n### ${label}`);
    for (const entry of entries) {
      if (entry.title) {
        sections.push(`**${entry.title}:**`);
      }
      sections.push(entry.content);
    }
  }

  return sections.join("\n");
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function toSharedContextEntry(record: {
  id: string;
  contextType: string;
  title: string | null;
  content: string;
  writerId: string | null;
  updatedAt: Date;
}): SharedContextEntry {
  return {
    id: record.id,
    contextType: record.contextType as SharedContextType,
    title: record.title ?? undefined,
    content: record.content,
    writerId: record.writerId ?? undefined,
    updatedAt: record.updatedAt,
  };
}
