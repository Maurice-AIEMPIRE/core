/**
 * Agent Session Loader (AGENTS.md boot sequence equivalent)
 *
 * Implements the session startup routine that runs before every
 * agent interaction. Loads all memory layers in the correct order:
 *
 *   1. Read SOUL.md — Agent identity and personality
 *   2. Read USER.md — User preferences and context
 *   3. Read MEMORY.md — Curated long-term memory
 *   4. Read daily logs (today + yesterday) — Recent session context
 *   5. Read shared-context/ — Cross-agent knowledge
 *   6. Read pending feedback — Corrections to apply
 *   7. Read specialist knowledge — Role-specific guides
 *
 * The result is a complete AgentSessionContext that gets injected
 * into the agent's system prompt.
 */

import { prisma } from "~/db.server";
import { logger } from "~/services/logger.service";

import type {
  AgentSessionContext,
  SessionBootConfig,
  SoulConfig,
  UserProfile,
} from "./types";
import {
  createDefaultSoulConfig,
  getSoulPrompt,
  estimateTokens,
} from "./memory-manager";
import {
  getMemoriesWithinBudget,
  formatMemoriesAsPrompt,
} from "./agent-memory";
import {
  getRecentDailyLogs,
  formatDailyLogsAsPrompt,
  archiveOldLogs,
} from "./daily-log";
import {
  getSharedContextWithinBudget,
  formatSharedContextAsPrompt,
} from "./shared-context";
import {
  getPendingFeedback,
  absorbAllPendingFeedback,
  formatFeedbackAsPrompt,
} from "./feedback-manager";

// ---------------------------------------------------------------------------
// Session Boot
// ---------------------------------------------------------------------------

const DEFAULT_DAILY_LOG_DAYS = 2;
const DEFAULT_MAX_MEMORY_ENTRIES = 50;
const DEFAULT_MAX_TOKEN_BUDGET = 32_000;

export async function bootAgentSession(
  config: SessionBootConfig,
): Promise<AgentSessionContext> {
  const startTime = Date.now();
  const {
    agentId,
    userId,
    workspaceId,
    loadDailyLogDays = DEFAULT_DAILY_LOG_DAYS,
    maxTokenBudget = DEFAULT_MAX_TOKEN_BUDGET,
  } = config;

  logger.info(`[CIM:SessionLoader] Booting session for agent ${agentId}`);

  // Step 1: Load Soul Config (SOUL.md)
  const soul = await prisma.agentSoul.findUnique({
    where: { agentId },
  });

  const soulConfig: SoulConfig = soul
    ? (soul.soulConfig as SoulConfig)
    : createDefaultSoulConfig();

  // Step 2: Load User Profile (USER.md)
  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: {
      name: true,
      displayName: true,
      memoryFilter: true,
      metadata: true,
    },
  });

  const userProfile: UserProfile = {
    name: user?.displayName || user?.name || undefined,
    timezone: config.timezone,
    preferences: {},
    context: [],
    constraints: [],
  };

  if (soul?.userPreferences) {
    const prefs = soul.userPreferences as Record<string, unknown>;
    if (prefs.preferences) {
      userProfile.preferences = prefs.preferences as Record<string, string>;
    }
    if (Array.isArray(prefs.context)) {
      userProfile.context = prefs.context as string[];
    }
    if (Array.isArray(prefs.constraints)) {
      userProfile.constraints = prefs.constraints as string[];
    }
  }

  if (user?.memoryFilter) {
    userProfile.constraints.push(user.memoryFilter);
  }

  // Budget allocation: split token budget across layers
  const memoryBudget = Math.floor(maxTokenBudget * 0.3);
  const dailyLogBudget = Math.floor(maxTokenBudget * 0.2);
  const sharedContextBudget = Math.floor(maxTokenBudget * 0.2);

  // Step 3: Load Long-Term Memory (MEMORY.md)
  const longTermMemory = await getMemoriesWithinBudget(agentId, memoryBudget);

  // Step 4: Load Recent Daily Logs
  const recentDailyLogs = await getRecentDailyLogs(
    agentId,
    workspaceId,
    loadDailyLogDays,
  );

  // Step 5: Load Shared Context
  const sharedContext = await getSharedContextWithinBudget(
    workspaceId,
    sharedContextBudget,
  );

  // Step 6: Load Pending Feedback
  const pendingFeedback = await getPendingFeedback(agentId, workspaceId);

  // Step 7: Load Specialist Knowledge
  const specialistKnowledge: Record<string, string> = soul?.specialistKnowledge
    ? (soul.specialistKnowledge as Record<string, string>)
    : {};

  // Maintenance: archive old logs in background
  archiveOldLogs(agentId, workspaceId).catch((err) => {
    logger.warn(`[CIM:SessionLoader] Failed to archive old logs: ${err}`);
  });

  const bootTimeMs = Date.now() - startTime;
  logger.info(
    `[CIM:SessionLoader] Session booted in ${bootTimeMs}ms. ` +
      `Memory: ${longTermMemory.length}, Logs: ${recentDailyLogs.length}, ` +
      `SharedCtx: ${sharedContext.length}, Feedback: ${pendingFeedback.length}`,
  );

  return {
    soulConfig,
    userProfile,
    longTermMemory,
    recentDailyLogs,
    sharedContext,
    pendingFeedback,
    specialistKnowledge,
  };
}

// ---------------------------------------------------------------------------
// Generate Full System Prompt from Session Context
// ---------------------------------------------------------------------------

export function buildSessionPrompt(context: AgentSessionContext): string {
  const sections: string[] = [];

  // 1. Soul Config (identity, personality, directives)
  sections.push(getSoulPrompt(context.soulConfig));

  // 2. User Profile
  if (context.userProfile.name || context.userProfile.timezone) {
    const userSection = ["## User Profile"];
    if (context.userProfile.name) {
      userSection.push(`Name: ${context.userProfile.name}`);
    }
    if (context.userProfile.timezone) {
      userSection.push(`Timezone: ${context.userProfile.timezone}`);
    }
    if (Object.keys(context.userProfile.preferences).length > 0) {
      userSection.push("\nPreferences:");
      for (const [key, value] of Object.entries(
        context.userProfile.preferences,
      )) {
        userSection.push(`- ${key}: ${value}`);
      }
    }
    if (context.userProfile.context.length > 0) {
      userSection.push("\nContext:");
      for (const item of context.userProfile.context) {
        userSection.push(`- ${item}`);
      }
    }
    sections.push(userSection.join("\n"));
  }

  // 3. Long-Term Memory
  const memoryPrompt = formatMemoriesAsPrompt(context.longTermMemory);
  if (memoryPrompt) {
    sections.push(memoryPrompt);
  }

  // 4. Shared Context
  const sharedPrompt = formatSharedContextAsPrompt(context.sharedContext);
  if (sharedPrompt) {
    sections.push(sharedPrompt);
  }

  // 5. Pending Feedback (highest urgency)
  const feedbackPrompt = formatFeedbackAsPrompt(context.pendingFeedback);
  if (feedbackPrompt) {
    sections.push(feedbackPrompt);
  }

  // 6. Recent Daily Logs
  const dailyLogPrompt = formatDailyLogsAsPrompt(context.recentDailyLogs);
  if (dailyLogPrompt) {
    sections.push(dailyLogPrompt);
  }

  // 7. Specialist Knowledge
  if (Object.keys(context.specialistKnowledge).length > 0) {
    const specialistSection = ["## Specialist Knowledge"];
    for (const [filename, content] of Object.entries(
      context.specialistKnowledge,
    )) {
      specialistSection.push(`\n### ${filename}`);
      specialistSection.push(content);
    }
    sections.push(specialistSection.join("\n"));
  }

  return sections.join("\n\n---\n\n");
}

// ---------------------------------------------------------------------------
// Post-Session: Absorb feedback and log results
// ---------------------------------------------------------------------------

export async function finalizeSession(
  agentId: string,
  userId: string,
  workspaceId: string,
): Promise<void> {
  // Absorb any pending feedback into long-term memory
  const absorbed = await absorbAllPendingFeedback(agentId, userId, workspaceId);

  if (absorbed > 0) {
    logger.info(
      `[CIM:SessionLoader] Finalized session: absorbed ${absorbed} feedback entries`,
    );
  }
}
