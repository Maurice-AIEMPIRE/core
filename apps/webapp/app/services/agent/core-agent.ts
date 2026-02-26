import { type Tool, tool, readUIMessageStream } from "ai";
import { z } from "zod";

import { runOrchestrator } from "./orchestrator";
import { runCIM } from "~/services/cim";

import { logger } from "../logger.service";

export const createTools = (
  userId: string,
  workspaceId: string,
  timezone: string,
  source: string,
) => {
  const tools: Record<string, Tool> = {
    gather_context: tool({
      description: `Search memory, connected integrations, AND the web. This is how you access information.

      THREE DATA SOURCES:
      1. Memory: past conversations, decisions, user preferences
      2. Integrations: user's emails, calendar, issues, messages (their personal data)
      3. Web: news, current events, documentation, prices, weather, general knowledge, AND reading URLs

      WHEN TO USE:
      - Before saying "i don't know" - you might know it
      - When user asks about past conversations, decisions, preferences
      - When user asks about live data (emails, calendar, issues, etc.)
      - When user asks about news, current events, how-tos, or general questions
      - When user shares a URL and wants you to read/summarize it

      HOW TO FORM YOUR QUERY:
      Describe your INTENT clearly. Include any URLs the user shared.

      EXAMPLES:
      - "What meetings does user have this week" → integrations (calendar)
      - "What did we discuss about the deployment" → memory
      - "Latest tech news and AI updates" → web search
      - "What's the weather in SF" → web search
      - "Summarize this article: https://example.com/post" → web (fetches URL)
      - "User's unread emails from GitHub" → integrations (gmail)

      For URLs: include the full URL in your query.
      For GENERAL NEWS/INFO: the orchestrator will use web search.
      For USER-SPECIFIC data: it uses integrations.`,
      inputSchema: z.object({
        query: z
          .string()
          .describe(
            "Your intent - what you're looking for and why. Describe it like you're asking a colleague to find something.",
          ),
      }),
      execute: async function* ({ query }, { abortSignal }) {
        logger.info(`Core brain: Gathering context for: ${query}`);

        const { stream } = await runOrchestrator(
          userId,
          workspaceId,
          query,
          "read",
          timezone,
          source,
          abortSignal,
        );

        // Stream the orchestrator's work to the UI
        for await (const message of readUIMessageStream({
          stream: stream.toUIMessageStream(),
        })) {
          yield message;
        }
      },
    }),
    take_action: tool({
      description: `Execute actions on user's connected integrations.
      Use this to CREATE/SEND/UPDATE/DELETE: gmail filters/labels, calendar events, github issues, slack messages, notion pages.
      Examples: "post message to slack #team-updates saying deployment complete", "block friday 3pm on calendar for 1:1 with sarah", "create github issue in core repo titled fix auth timeout"
      When user confirms they want something done, use this tool to do it.`,
      inputSchema: z.object({
        action: z
          .string()
          .describe(
            "The action to perform. Be specific: include integration, what to create/send/update, and all details.",
          ),
      }),
      execute: async function* ({ action }, { abortSignal }) {
        logger.info(`Core brain: Taking action: ${action}`);

        const { stream } = await runOrchestrator(
          userId,
          workspaceId,
          action,
          "write",
          timezone,
          source,
          abortSignal,
        );

        // Stream the orchestrator's work to the UI
        for await (const message of readUIMessageStream({
          stream: stream.toUIMessageStream(),
        })) {
          yield message;
        }
      },
    }),
    cim_query: tool({
      description: `Goal-driven agent that plans and executes multi-step tasks using the CIM (Cognitive Intelligence Module) architecture.
      Use for COMPLEX tasks that need planning: multi-step workflows, tasks spanning multiple integrations, or goals requiring observation-decision-action cycles.

      The CIM engine will:
      1. PERCEIVE - observe state, gather context from memory and integrations
      2. DECIDE - classify intent, create a step-by-step plan
      3. ACT - execute each step with guardrails, retry on failure
      4. OBSERVE - verify results, log to audit trail

      WHEN TO USE:
      - Complex multi-step tasks: "migrate data from X to Y", "prepare a weekly summary from all sources"
      - Tasks requiring judgment: "check all channels for urgent items and prioritize them"
      - Cross-integration workflows: "find open issues, check related emails, draft a status update"

      WHEN NOT TO USE:
      - Simple lookups → use gather_context instead
      - Direct single actions → use take_action instead`,
      inputSchema: z.object({
        goal: z
          .string()
          .describe(
            "The goal to achieve. Be specific about what success looks like. The CIM engine will plan and execute steps to reach this goal.",
          ),
      }),
      execute: async ({ goal }) => {
        logger.info(`Core brain: CIM query for goal: ${goal}`);

        const result = await runCIM(goal, userId, workspaceId, {
          timezone,
          source,
        });

        return result.summary;
      },
    }),
  };

  return tools;
};
