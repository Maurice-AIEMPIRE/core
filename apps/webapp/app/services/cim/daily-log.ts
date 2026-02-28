/**
 * Agent Daily Log (memory/YYYY-MM-DD.md equivalent)
 *
 * Raw session notes organized by day. Two key rules:
 *   1. Only load today + yesterday (keep context small)
 *   2. Archive old logs to prevent context bloat
 *
 * Daily logs are the raw material. Long-term memory (MEMORY.md)
 * is the refined product distilled from these logs.
 */

import { prisma } from "~/db.server";
import { logger } from "~/services/logger.service";

import type { DailyLogEntry, AgentDailyLogData } from "./types";
import { estimateTokens } from "./memory-manager";

// ---------------------------------------------------------------------------
// Write Operations
// ---------------------------------------------------------------------------

export async function appendDailyLog(
  agentId: string,
  workspaceId: string,
  entry: Omit<DailyLogEntry, "timestamp">,
): Promise<AgentDailyLogData> {
  const today = getDateOnly(new Date());

  const logEntry: DailyLogEntry = {
    ...entry,
    timestamp: new Date(),
  };

  // Find or create today's log
  const existing = await prisma.agentDailyLog.findUnique({
    where: {
      agentId_date_workspaceId: { agentId, date: today, workspaceId },
    },
  });

  let record;
  if (existing) {
    const entries = (existing.entries as DailyLogEntry[]) || [];
    entries.push(logEntry);
    const tokenCount = estimateTokens(JSON.stringify(entries));

    record = await prisma.agentDailyLog.update({
      where: { id: existing.id },
      data: { entries, tokenCount },
    });
  } else {
    const entries = [logEntry];
    const tokenCount = estimateTokens(JSON.stringify(entries));

    record = await prisma.agentDailyLog.create({
      data: {
        agentId,
        workspaceId,
        date: today,
        entries,
        tokenCount,
      },
    });
  }

  return toDailyLogData(record);
}

export async function logAction(
  agentId: string,
  workspaceId: string,
  content: string,
  metadata?: Record<string, unknown>,
): Promise<AgentDailyLogData> {
  return appendDailyLog(agentId, workspaceId, {
    type: "action",
    content,
    metadata,
  });
}

export async function logFeedback(
  agentId: string,
  workspaceId: string,
  content: string,
): Promise<AgentDailyLogData> {
  return appendDailyLog(agentId, workspaceId, {
    type: "feedback",
    content,
  });
}

export async function logObservation(
  agentId: string,
  workspaceId: string,
  content: string,
): Promise<AgentDailyLogData> {
  return appendDailyLog(agentId, workspaceId, {
    type: "observation",
    content,
  });
}

// ---------------------------------------------------------------------------
// Read Operations
// ---------------------------------------------------------------------------

export async function getRecentDailyLogs(
  agentId: string,
  workspaceId: string,
  days: number = 2,
): Promise<AgentDailyLogData[]> {
  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - days);
  const cutoffDate = getDateOnly(cutoff);

  const records = await prisma.agentDailyLog.findMany({
    where: {
      agentId,
      workspaceId,
      date: { gte: cutoffDate },
      archived: false,
    },
    orderBy: { date: "desc" },
  });

  return records.map(toDailyLogData);
}

export async function getDailyLog(
  agentId: string,
  workspaceId: string,
  date: Date,
): Promise<AgentDailyLogData | null> {
  const dateOnly = getDateOnly(date);

  const record = await prisma.agentDailyLog.findUnique({
    where: {
      agentId_date_workspaceId: {
        agentId,
        date: dateOnly,
        workspaceId,
      },
    },
  });

  return record ? toDailyLogData(record) : null;
}

// ---------------------------------------------------------------------------
// Maintenance
// ---------------------------------------------------------------------------

export async function archiveOldLogs(
  agentId: string,
  workspaceId: string,
  olderThanDays: number = 14,
): Promise<number> {
  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - olderThanDays);
  const cutoffDate = getDateOnly(cutoff);

  const result = await prisma.agentDailyLog.updateMany({
    where: {
      agentId,
      workspaceId,
      date: { lt: cutoffDate },
      archived: false,
    },
    data: { archived: true },
  });

  if (result.count > 0) {
    logger.info(
      `[CIM:DailyLog] Archived ${result.count} old logs for agent ${agentId}`,
    );
  }

  return result.count;
}

export async function getTotalTokenCount(
  agentId: string,
  workspaceId: string,
): Promise<number> {
  const logs = await prisma.agentDailyLog.findMany({
    where: { agentId, workspaceId, archived: false },
    select: { tokenCount: true },
  });

  return logs.reduce((sum, log) => sum + log.tokenCount, 0);
}

// ---------------------------------------------------------------------------
// Prompt Generation
// ---------------------------------------------------------------------------

export function formatDailyLogsAsPrompt(logs: AgentDailyLogData[]): string {
  if (logs.length === 0) return "";

  const sections: string[] = ["## Recent Session Logs"];

  for (const log of logs) {
    const dateStr = log.date.toISOString().split("T")[0];
    sections.push(`\n### ${dateStr}`);

    for (const entry of log.entries) {
      const time = new Date(entry.timestamp).toLocaleTimeString("en-US", {
        hour: "2-digit",
        minute: "2-digit",
      });
      sections.push(`- [${time}] [${entry.type}] ${entry.content}`);
    }
  }

  return sections.join("\n");
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function getDateOnly(date: Date): Date {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

function toDailyLogData(record: {
  id: string;
  agentId: string;
  date: Date;
  entries: unknown;
  tokenCount: number;
  archived: boolean;
}): AgentDailyLogData {
  return {
    id: record.id,
    agentId: record.agentId,
    date: record.date,
    entries: (record.entries as DailyLogEntry[]) || [],
    tokenCount: record.tokenCount,
    archived: record.archived,
  };
}
