# HEARTBEAT

## Status
HEARTBEAT_OK

## Instructions
This file is read by the OpenClaw heartbeat session on every pulse.

- If this file says `HEARTBEAT_OK`, the agent should respond with `HEARTBEAT_OK` and idle.
- If there is an `## Urgent` section below, the agent should execute those tasks first.
- Always check for new instructions from Monica before reporting idle.

## Workspace
Agents are scoped to the `ai-empire` workspace.
Shared memory and context live in `~/.openclaw/workspace/ai-empire/`.

## Urgent
_No urgent tasks at this time._
