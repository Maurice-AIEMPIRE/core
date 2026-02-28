/**
 * Agent Feedback Manager (FEEDBACK-LOG.md equivalent)
 *
 * Manages cross-agent corrections. When a user corrects one agent,
 * the feedback can be propagated to all agents (or specific ones).
 *
 * Feedback lifecycle:
 *   1. User gives feedback to an agent
 *   2. Feedback is recorded with scope (global or specific agents)
 *   3. On each agent's session boot, pending feedback is loaded
 *   4. Agent absorbs feedback into its long-term memory
 *   5. Feedback is marked as absorbed
 *
 * This prevents repeating the same correction to multiple agents.
 */

import { prisma } from "~/db.server";
import { logger } from "~/services/logger.service";

import type { AgentFeedbackEntry, FeedbackCategory } from "./types";
import { addMemory } from "./agent-memory";

// ---------------------------------------------------------------------------
// Record Feedback
// ---------------------------------------------------------------------------

export async function recordFeedback(
  userId: string,
  workspaceId: string,
  correction: string,
  options: {
    category?: FeedbackCategory;
    agentId?: string;
    appliesTo?: string[];
    global?: boolean;
  } = {},
): Promise<AgentFeedbackEntry> {
  const record = await prisma.agentFeedback.create({
    data: {
      userId,
      workspaceId,
      correction,
      category: options.category ?? "behavior",
      agentId: options.agentId,
      appliesTo: options.appliesTo ?? [],
      global: options.global ?? true,
    },
  });

  logger.info(
    `[CIM:Feedback] Recorded feedback: "${correction.slice(0, 50)}..." ` +
      `global=${options.global ?? true}, agents=${(options.appliesTo ?? []).join(",") || "all"}`,
  );

  return toFeedbackEntry(record);
}

// ---------------------------------------------------------------------------
// Retrieve Pending Feedback
// ---------------------------------------------------------------------------

export async function getPendingFeedback(
  agentId: string,
  workspaceId: string,
): Promise<AgentFeedbackEntry[]> {
  const records = await prisma.agentFeedback.findMany({
    where: {
      workspaceId,
      absorbed: false,
      OR: [{ global: true }, { appliesTo: { has: agentId } }, { agentId }],
    },
    orderBy: { createdAt: "asc" },
  });

  return records.map(toFeedbackEntry);
}

export async function getAllFeedback(
  workspaceId: string,
  options: {
    category?: FeedbackCategory;
    absorbed?: boolean;
    limit?: number;
  } = {},
): Promise<AgentFeedbackEntry[]> {
  const records = await prisma.agentFeedback.findMany({
    where: {
      workspaceId,
      ...(options.category ? { category: options.category } : {}),
      ...(options.absorbed !== undefined ? { absorbed: options.absorbed } : {}),
    },
    orderBy: { createdAt: "desc" },
    take: options.limit ?? 100,
  });

  return records.map(toFeedbackEntry);
}

// ---------------------------------------------------------------------------
// Absorb Feedback into Agent Memory
// ---------------------------------------------------------------------------

export async function absorbFeedback(
  agentId: string,
  userId: string,
  workspaceId: string,
  feedbackId: string,
): Promise<void> {
  const feedback = await prisma.agentFeedback.findUnique({
    where: { id: feedbackId },
  });

  if (!feedback) {
    logger.warn(`[CIM:Feedback] Feedback ${feedbackId} not found`);
    return;
  }

  // Add to agent's long-term memory
  const categoryToMemoryCategory: Record<string, string> = {
    style: "rules",
    content: "rules",
    behavior: "rules",
    accuracy: "hard_lessons",
    safety: "hard_lessons",
  };

  const memoryCategory = categoryToMemoryCategory[feedback.category] || "rules";

  await addMemory(agentId, userId, workspaceId, {
    category: memoryCategory as "rules" | "hard_lessons",
    content: feedback.correction,
    priority: feedback.category === "safety" ? 10 : 8,
    permanent: feedback.category === "safety",
    source: "cross_agent",
  });

  // Mark as absorbed
  await prisma.agentFeedback.update({
    where: { id: feedbackId },
    data: { absorbed: true },
  });

  logger.info(
    `[CIM:Feedback] Agent ${agentId} absorbed feedback ${feedbackId} as ${memoryCategory}`,
  );
}

export async function absorbAllPendingFeedback(
  agentId: string,
  userId: string,
  workspaceId: string,
): Promise<number> {
  const pending = await getPendingFeedback(agentId, workspaceId);

  for (const feedback of pending) {
    await absorbFeedback(agentId, userId, workspaceId, feedback.id);
  }

  if (pending.length > 0) {
    logger.info(
      `[CIM:Feedback] Agent ${agentId} absorbed ${pending.length} pending feedback entries`,
    );
  }

  return pending.length;
}

// ---------------------------------------------------------------------------
// Prompt Generation
// ---------------------------------------------------------------------------

export function formatFeedbackAsPrompt(feedback: AgentFeedbackEntry[]): string {
  if (feedback.length === 0) return "";

  const sections: string[] = [
    "## Pending Corrections (MUST apply immediately)",
  ];

  for (const entry of feedback) {
    sections.push(`- [${entry.category.toUpperCase()}] ${entry.correction}`);
  }

  return sections.join("\n");
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function toFeedbackEntry(record: {
  id: string;
  correction: string;
  category: string;
  appliesTo: string[];
  global: boolean;
  absorbed: boolean;
  agentId: string | null;
  createdAt: Date;
}): AgentFeedbackEntry {
  return {
    id: record.id,
    correction: record.correction,
    category: record.category as FeedbackCategory,
    appliesTo: record.appliesTo,
    global: record.global,
    absorbed: record.absorbed,
    agentId: record.agentId ?? undefined,
    createdAt: record.createdAt,
  };
}
