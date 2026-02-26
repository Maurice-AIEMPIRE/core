import { z } from "zod";
import { json } from "@remix-run/node";
import { createActionApiRoute } from "~/services/routeBuilders/apiBuilder.server";
import { trackFeatureUsage } from "~/services/telemetry.server";
import { streamText, type LanguageModel } from "ai";
import { logger } from "~/services/logger.service";
import { getModel } from "~/lib/model.server";
import { runTeam, startHeartbeat, stopHeartbeat, isHeartbeatRunning, type CIMEngineConfig } from "~/services/cim";

const TeamQuerySchema = z.object({
  goal: z.string().min(1, "Goal is required"),
  timezone: z.string().default("UTC"),
  stream: z.boolean().default(false),
  heartbeat: z
    .object({
      enable: z.boolean().optional(),
      disable: z.boolean().optional(),
    })
    .optional(),
  metadata: z
    .object({
      source: z.string().optional(),
    })
    .optional(),
});

const { action, loader } = createActionApiRoute(
  {
    body: TeamQuerySchema,
    method: "POST",
    allowJWT: true,
    authorization: {
      action: "conversation",
    },
    corsStrategy: "all",
  },
  async ({ body, authentication }) => {
    trackFeatureUsage("team_execute", authentication.userId).catch(
      console.error,
    );

    const config: CIMEngineConfig = {
      userId: authentication.userId,
      workspaceId: authentication.workspaceId!,
      timezone: body.timezone,
      source: body.metadata?.source || "api",
      maxLoopIterations: 10,
      modelTier: "high",
    };

    // Handle heartbeat control
    if (body.heartbeat?.enable) {
      startHeartbeat(config);
      if (!body.goal || body.goal === "heartbeat") {
        return json({
          success: true,
          heartbeat: "started",
          running: isHeartbeatRunning(),
        });
      }
    }

    if (body.heartbeat?.disable) {
      stopHeartbeat();
      if (!body.goal || body.goal === "heartbeat") {
        return json({
          success: true,
          heartbeat: "stopped",
          running: isHeartbeatRunning(),
        });
      }
    }

    try {
      const result = await runTeam(body.goal, config);

      if (body.stream) {
        const streamResult = streamText({
          model: getModel() as LanguageModel,
          messages: [
            {
              role: "system",
              content: `You are a helpful assistant. Synthesize the agent team results into a clear, concise response. Only use information from the results provided.`,
            },
            {
              role: "user",
              content: `Goal: ${body.goal}\n\nTeam Report:\n${result.synthesis}`,
            },
          ],
        });

        return streamResult.toUIMessageStreamResponse({});
      }

      return json({
        success: result.success,
        teamId: result.teamId,
        goal: result.goal,
        totalDurationMs: result.totalDurationMs,
        synthesis: result.synthesis,
        subTasks: result.subTasks.map((st) => ({
          agent: st.assignment.agentRole,
          subGoal: st.assignment.subGoal,
          priority: st.assignment.priority,
          success: st.result.success,
          status: st.result.finalState.status,
          steps: st.result.finalState.plan?.steps.map((s) => ({
            id: s.id,
            description: s.description,
            action: s.action,
            status: s.status,
          })),
        })),
        heartbeat: {
          running: isHeartbeatRunning(),
        },
      });
    } catch (error: any) {
      logger.error(`Team execute error: ${error}`);
      return json({
        success: false,
        error: error.message,
      });
    }
  },
);

export { action, loader };
