/**
 * CIM Team Coordinator — Fully Automated Agent Team
 *
 * Auto-registers a pre-built agent team on first use, then
 * routes incoming goals to the right specialist agents.
 * The coordinator decomposes complex goals into sub-tasks,
 * assigns them to agents in parallel where possible, collects
 * results, and synthesizes a unified response.
 *
 * Team roster (Mission Control):
 *   - Orchestrator: Coordinator, routes and synthesizes
 *   - Researcher: Memory + integrations + web (read-only)
 *   - Executor: Takes actions on integrations (write)
 *   - Monitor: Background heartbeat checks
 *   - Analyst: Cross-source analysis and insights
 *
 * The team is a singleton — initialized once, reused globally.
 */

import { generateObject } from "ai";
import { z } from "zod";

import { logger } from "~/services/logger.service";
import { getModel, getModelForTask } from "~/lib/model.server";

import type {
  AgentTeam,
  AgentDefinition,
  AgentRole,
  CIMEngineConfig,
  CIMResult,
  ExternalMemoryEntry,
  HeartbeatConfig,
  HeartbeatResult,
} from "./types";

import {
  createTeam,
  getTeam,
  registerAgent,
  listAgents,
  createAgentDefinition,
  createContextBundle,
  bundleToPrompt,
  sendMessage,
  getMessages,
  createEscalation,
} from "./multi-agent";

import { runCIMLoop, createGoal } from "./cim-engine";
import { executeAction } from "./action";
import {
  writeToExternalMemory,
  logDecision,
  logError,
  readExternalMemory,
} from "./memory-manager";
import {
  createDefaultHeartbeatConfig,
  runHeartbeatCycle,
  formatHeartbeatSummary,
} from "./heartbeat";

// ---------------------------------------------------------------------------
// Singleton Team
// ---------------------------------------------------------------------------

let defaultTeam: AgentTeam | null = null;
let heartbeatInterval: ReturnType<typeof setInterval> | null = null;

export function getOrCreateDefaultTeam(): AgentTeam {
  if (defaultTeam) return defaultTeam;

  logger.info("[CIM:TeamCoord] Initializing default agent team");

  defaultTeam = createTeam(
    "CORE Mission Control",
    ["orchestrator", "researcher", "executor", "monitor", "analyst"],
    "orchestrator",
  );

  logger.info(
    `[CIM:TeamCoord] Team ready: ${defaultTeam.agents.length} agents, ` +
      `coordinator=${defaultTeam.coordinatorId}`,
  );

  return defaultTeam;
}

// ---------------------------------------------------------------------------
// Task Router — Assigns goals to the right agent(s)
// ---------------------------------------------------------------------------

interface TaskAssignment {
  agentRole: AgentRole;
  subGoal: string;
  priority: number;
  dependsOn: string[];
}

const ROUTER_PROMPT = `You are a task router for an AI agent team. Given a user goal, break it into sub-tasks and assign each to the best agent.

AVAILABLE AGENTS:
- researcher: Gathers information from memory, integrations, web. Read-only. Use for lookups, searches, context gathering.
- executor: Takes actions on integrations. Creates, updates, sends things. Use for write operations.
- monitor: Checks integrations for status/updates. Use for monitoring and status checks.
- analyst: Analyzes data across sources, finds patterns, generates insights. Use for synthesis and reporting.

RULES:
1. Break the goal into 1-5 sub-tasks
2. Assign each to exactly ONE agent role
3. Mark dependencies (task B depends on task A)
4. Information gathering tasks (researcher) should come before action tasks (executor)
5. If the goal is simple, just one task is fine
6. Never assign orchestrator - that's the coordinator (you)`;

async function routeGoalToAgents(
  goal: string,
  config: CIMEngineConfig,
): Promise<TaskAssignment[]> {
  const startTime = Date.now();
  logger.info(`[CIM:TeamCoord] Routing goal: "${goal}"`);

  try {
    const modelName = getModelForTask("low");
    const model = getModel(modelName);

    const { object } = await generateObject({
      model,
      system: ROUTER_PROMPT,
      prompt: `User goal: "${goal}"\n\nBreak this into sub-tasks and assign to agents.`,
      schema: z.object({
        tasks: z.array(
          z.object({
            agentRole: z.enum([
              "researcher",
              "executor",
              "monitor",
              "analyst",
            ]),
            subGoal: z
              .string()
              .describe("The specific sub-task for this agent"),
            priority: z.number().min(1).max(5),
            dependsOn: z
              .array(z.string())
              .describe("Sub-goals this depends on (empty if independent)"),
          }),
        ),
      }),
      providerOptions: {
        openai: { strictJsonSchema: false },
      },
    });

    logger.info(
      `[CIM:TeamCoord] Routed to ${object.tasks.length} sub-tasks in ${Date.now() - startTime}ms`,
    );

    return object.tasks;
  } catch (error) {
    logger.error("[CIM:TeamCoord] Routing failed, using single researcher:", error);
    return [
      {
        agentRole: "researcher",
        subGoal: goal,
        priority: 1,
        dependsOn: [],
      },
    ];
  }
}

// ---------------------------------------------------------------------------
// Team Executor — Runs sub-tasks through assigned agents
// ---------------------------------------------------------------------------

interface SubTaskResult {
  assignment: TaskAssignment;
  result: CIMResult;
}

async function executeSubTask(
  assignment: TaskAssignment,
  config: CIMEngineConfig,
  team: AgentTeam,
  abortSignal?: AbortSignal,
): Promise<SubTaskResult> {
  const agent = team.agents.find((a) => a.role === assignment.agentRole);
  if (!agent) {
    logger.warn(
      `[CIM:TeamCoord] No agent for role ${assignment.agentRole}, using researcher`,
    );
  }

  const agentName = agent?.name || assignment.agentRole;
  logger.info(
    `[CIM:TeamCoord] Agent "${agentName}" executing: "${assignment.subGoal}"`,
  );

  // Build agent-specific config
  const agentConfig: CIMEngineConfig = {
    ...config,
    modelTier: agent?.modelTier || "high",
    maxLoopIterations: 5,
  };

  const result = await runCIMLoop(
    assignment.subGoal,
    agentConfig,
    abortSignal,
  );

  // Log agent completion
  sendMessage({
    fromAgentId: agent?.id || assignment.agentRole,
    toAgentId: team.coordinatorId,
    type: "result",
    payload: {
      subGoal: assignment.subGoal,
      success: result.success,
      summary: result.summary,
    },
    timestamp: new Date(),
  });

  return { assignment, result };
}

// ---------------------------------------------------------------------------
// Team Run — Full automated pipeline
// ---------------------------------------------------------------------------

export interface TeamRunResult {
  success: boolean;
  teamId: string;
  goal: string;
  subTasks: SubTaskResult[];
  synthesis: string;
  totalDurationMs: number;
}

export async function runTeam(
  goal: string,
  config: CIMEngineConfig,
  abortSignal?: AbortSignal,
): Promise<TeamRunResult> {
  const startTime = Date.now();
  const team = getOrCreateDefaultTeam();
  const coordinatorId = team.coordinatorId;

  logger.info(
    `[CIM:TeamCoord] === TEAM RUN START === Goal: "${goal}" ===`,
  );

  // Step 1: Route goal to agents
  logDecision(coordinatorId, "Routing goal to agent team", goal);
  const assignments = await routeGoalToAgents(goal, config);

  logger.info(
    `[CIM:TeamCoord] ${assignments.length} sub-tasks assigned: ` +
      assignments
        .map((a) => `${a.agentRole}("${a.subGoal.slice(0, 40)}...")`)
        .join(", "),
  );

  // Step 2: Execute sub-tasks respecting dependencies
  const results: SubTaskResult[] = [];
  const completedGoals = new Set<string>();

  // Group into dependency layers
  const layers: TaskAssignment[][] = [];
  const remaining = [...assignments];

  while (remaining.length > 0) {
    const layer = remaining.filter((task) =>
      task.dependsOn.every((dep) => completedGoals.has(dep)),
    );

    if (layer.length === 0) {
      // Circular dependency or unresolvable — force all remaining
      logger.warn("[CIM:TeamCoord] Unresolvable dependencies, forcing remaining tasks");
      layers.push([...remaining]);
      break;
    }

    layers.push(layer);
    for (const task of layer) {
      const idx = remaining.indexOf(task);
      if (idx !== -1) remaining.splice(idx, 1);
      completedGoals.add(task.subGoal);
    }
  }

  // Execute layer by layer (within a layer, run in parallel)
  for (const layer of layers) {
    if (abortSignal?.aborted) break;

    const layerResults = await Promise.all(
      layer.map((assignment) =>
        executeSubTask(assignment, config, team, abortSignal),
      ),
    );

    results.push(...layerResults);
  }

  // Step 3: Synthesize results
  const successCount = results.filter((r) => r.result.success).length;
  const failCount = results.length - successCount;

  const subSummaries = results
    .map(
      (r, i) =>
        `[${r.assignment.agentRole}] ${r.result.success ? "OK" : "FAIL"}: ${r.result.summary}`,
    )
    .join("\n\n");

  const synthesis = [
    `Team: ${team.name}`,
    `Goal: ${goal}`,
    `Sub-tasks: ${successCount}/${results.length} succeeded`,
    failCount > 0 ? `Failed: ${failCount}` : null,
    `Duration: ${Date.now() - startTime}ms`,
    `\n--- Agent Reports ---\n${subSummaries}`,
  ]
    .filter(Boolean)
    .join("\n");

  // Log to external memory
  writeToExternalMemory({
    id: `team-run-${Date.now()}`,
    type: "task_summary",
    content: synthesis,
    metadata: {
      teamId: team.id,
      goal,
      successCount,
      failCount,
      totalDurationMs: Date.now() - startTime,
    },
    createdAt: new Date(),
    agentId: coordinatorId,
  });

  logger.info(
    `[CIM:TeamCoord] === TEAM RUN COMPLETE === ` +
      `${successCount}/${results.length} OK, ${Date.now() - startTime}ms ===`,
  );

  return {
    success: failCount === 0,
    teamId: team.id,
    goal,
    subTasks: results,
    synthesis,
    totalDurationMs: Date.now() - startTime,
  };
}

// ---------------------------------------------------------------------------
// Heartbeat Auto-Runner
// ---------------------------------------------------------------------------

export function startHeartbeat(
  config: CIMEngineConfig,
  heartbeatConfig?: HeartbeatConfig,
): void {
  if (heartbeatInterval) {
    logger.info("[CIM:TeamCoord] Heartbeat already running, skipping");
    return;
  }

  const hbConfig = heartbeatConfig || createDefaultHeartbeatConfig(config.timezone);
  hbConfig.enabled = true;

  const executeQuery = async (
    integration: string,
    query: string,
  ): Promise<string> => {
    // Use a lightweight CIM run for each heartbeat check
    const result = await runCIMLoop(
      `[Heartbeat] ${query} (integration: ${integration})`,
      { ...config, maxLoopIterations: 3, modelTier: "low" },
    );
    return result.summary;
  };

  const runCycle = async () => {
    try {
      const results = await runHeartbeatCycle(hbConfig, executeQuery);
      if (results.length > 0) {
        const summary = formatHeartbeatSummary(results);
        logger.info(`[CIM:Heartbeat] Cycle summary:\n${summary}`);

        // Store findings in external memory
        writeToExternalMemory({
          id: `heartbeat-${Date.now()}`,
          type: "audit_trail",
          content: summary,
          metadata: {
            checkCount: results.length,
            findingCount: results.reduce(
              (sum, r) => sum + r.findings.length,
              0,
            ),
          },
          createdAt: new Date(),
          agentId: "heartbeat-monitor",
        });
      }
    } catch (error) {
      logger.error("[CIM:Heartbeat] Cycle failed:", error);
    }
  };

  // Run first cycle immediately, then on interval
  runCycle();
  heartbeatInterval = setInterval(runCycle, hbConfig.intervalMs);

  logger.info(
    `[CIM:TeamCoord] Heartbeat started, interval=${hbConfig.intervalMs}ms, ` +
      `checks=${hbConfig.checks.length}`,
  );
}

export function stopHeartbeat(): void {
  if (heartbeatInterval) {
    clearInterval(heartbeatInterval);
    heartbeatInterval = null;
    logger.info("[CIM:TeamCoord] Heartbeat stopped");
  }
}

export function isHeartbeatRunning(): boolean {
  return heartbeatInterval !== null;
}
