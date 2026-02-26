/**
 * Prompt Builder
 *
 * Two-layer architecture:
 * - Core brain: personality + channel format (synthesis only)
 * - Orchestrator: no personality, gathers context
 *
 * CIM Integration:
 * - Soul config anchors (compaction-proof rules) injected into every prompt
 * - Ensures critical agent directives persist across context resets
 */

import { PERSONALITY } from "./personality";
import { CAPABILITIES } from "./capabilities";
import { CHANNEL_FORMATS, type ChannelType } from "./channel-formats";
import { createDefaultSoulConfig, getSoulPrompt } from "~/services/cim";

export interface UserInfo {
  name: string;
  email: string;
  timezone: string;
  phoneNumber?: string;
}

/**
 * Get Core brain's prompt for synthesizing responses.
 * Combines personality (who Core brain is) + capabilities (what Core brain can do) + channel format (how to communicate).
 * Includes CIM anchor rules that persist across context compaction.
 */
export function getCorePrompt(
  channel: ChannelType,
  userInfo?: UserInfo,
  userPersona?: string,
): string {
  const channelFormat = CHANNEL_FORMATS[channel] || CHANNEL_FORMATS.web;

  const timezone = userInfo?.timezone || "UTC";
  const localTime = new Date().toLocaleString("en-US", {
    timeZone: timezone,
    dateStyle: "full",
    timeStyle: "short",
  });
  const currentTime = `Current time: ${localTime} (${timezone})`;

  let userContext = "";
  if (userInfo) {
    userContext = `\n\n<user>
Name: ${userInfo.name}
Email: ${userInfo.email}
Timezone: ${userInfo.timezone}${userInfo.phoneNumber ? `\nPhone: ${userInfo.phoneNumber}` : ""}
</user>`;
  }

  let personaSection = "";
  if (userPersona) {
    personaSection = `\n\n<user-persona>
${userPersona}
</user-persona>`;
  }

  // CIM anchor rules - compaction-proof directives that always persist
  const soulConfig = createDefaultSoulConfig();
  const anchorRules = soulConfig.anchors
    .filter((a) => a.neverCompact)
    .map((a) => `- ${a.rule}`)
    .join("\n");
  const anchorSection = anchorRules
    ? `\n\n<anchor-rules>\n${anchorRules}\n</anchor-rules>`
    : "";

  return `${PERSONALITY(userInfo?.name ?? "User")}\n\n${CAPABILITIES}\n\n${channelFormat}\n\n${currentTime}${userContext}${personaSection}${anchorSection}`;
}

// Re-export for convenience
export { PERSONALITY } from "./personality";
export { CAPABILITIES } from "./capabilities";
export { CHANNEL_FORMATS } from "./channel-formats";
export type { ChannelType } from "./channel-formats";
