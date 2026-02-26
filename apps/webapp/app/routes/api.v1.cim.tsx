import { z } from "zod";
import { json } from "@remix-run/node";
import { createActionApiRoute } from "~/services/routeBuilders/apiBuilder.server";
import { trackFeatureUsage } from "~/services/telemetry.server";
import { streamText, type LanguageModel } from "ai";
import { logger } from "~/services/logger.service";
import { getModel } from "~/lib/model.server";
import { runCIM } from "~/services/cim";

const CIMQuerySchema = z.object({
  goal: z.string().min(1, "Goal is required"),
  timezone: z.string().default("UTC"),
  stream: z.boolean().default(false),
  metadata: z
    .object({
      source: z.string().optional(),
    })
    .optional(),
});

const { action, loader } = createActionApiRoute(
  {
    body: CIMQuerySchema,
    method: "POST",
    allowJWT: true,
    authorization: {
      action: "conversation",
    },
    corsStrategy: "all",
  },
  async ({ body, authentication }) => {
    trackFeatureUsage("cim_query", authentication.userId).catch(
      console.error,
    );

    try {
      const result = await runCIM(
        body.goal,
        authentication.userId,
        authentication.workspaceId!,
        {
          timezone: body.timezone,
          source: body.metadata?.source || "api",
        },
      );

      if (body.stream) {
        // Synthesize the CIM result through an LLM for natural language response
        const streamResult = streamText({
          model: getModel() as LanguageModel,
          messages: [
            {
              role: "system",
              content: `You are a helpful assistant. Synthesize the CIM engine results into a clear, concise response. Only use information from the results provided.`,
            },
            {
              role: "user",
              content: `Goal: ${body.goal}\n\nCIM Result:\n${result.summary}`,
            },
          ],
        });

        return streamResult.toUIMessageStreamResponse({});
      }

      return json({
        success: result.success,
        goalMet: result.goalMet,
        summary: result.summary,
        status: result.finalState.status,
        steps: result.finalState.plan?.steps.map((s) => ({
          id: s.id,
          description: s.description,
          action: s.action,
          status: s.status,
        })),
        errors: result.finalState.errors,
        auditTrail: result.auditTrail.map((a) => ({
          type: a.type,
          content: a.content,
          createdAt: a.createdAt,
        })),
      });
    } catch (error: any) {
      logger.error(`CIM query error: ${error}`);
      return json({
        success: false,
        error: error.message,
      });
    }
  },
);

export { action, loader };
