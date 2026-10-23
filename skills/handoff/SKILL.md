---
name: handoff
description: Save, verify, and resume task handoffs. Use when the user asks to save progress, transfer work to a fresh chat, or resume from handoff material; also consider a handoff at a safe substantive phase change with clear remaining work. Reviewing or editing this skill does not initiate a handoff.
---

# Task handoff

Give the next chat verified state, effective decisions, permission boundaries, and a concrete first step. Use the user's language. This community skill works independently of a status bar and needs no scripts, counters, hooks, or model services.

## Choose the requested action

- **Save only:** A bare `$handoff`, “save progress,” or an ambiguous “handoff” request saves material; it does not authorize creating a chat.
- **Complete handoff:** An explicit request to save, create/open a new chat, and continue authorizes those steps together. Do not ask again at each step. Follow [the handoff workflow](references/handoff.md).
- **Resume:** Read the specified material, verify facts needed for the next step, and continue already authorized work. A request only to inspect material stays read-only.
- **Review/edit this skill:** Work on the skill without saving or transferring the current business task.

Use only tools actually available in the current host. Follow its current mode and permissions: Plan mode allows planning, not saving files or creating chats. Explain an actual limitation rather than claiming an unavailable action succeeded.

## Optional suggestion at a safe boundary

Consider a suggestion only when work is safely collected, the remaining task is clear, and a fresh chat has a specific benefit, such as separating completed research from implementation. Correct verified confusion about goals or versions first. Do not infer context percentages, count compressions from turns, inspect private history, or read a status bar's settings.

Put a warranted suggestion in a short first paragraph of the final answer, in the user's language. State the concrete benefit, the next step, and what confirmation would authorize. A suggestion does not authorize saving, creating a chat, or messaging another chat. Continue the existing task while awaiting a response.

Suggest once per substantive phase or corrected issue. Respect “not now,” “after X,” and “no more reminders”; repeated edits in the same phase do not justify another suggestion. Do not suggest for a completed task with no follow-up, ordinary questions, or skill maintenance. There is no guaranteed background reminder or delivery counter.

## Save a useful, minimal record

Use the user's specified location or the existing project state file; otherwise use `PROJECT_STATE.md` in the task's working directory. Re-read before updating and preserve concurrent changes. Do not initialize a repository or commit the record merely to save it. In a public source project, keep private local paths, chat IDs, and maintenance records outside the repository unless the user explicitly chooses otherwise.

Record the actual goal and completion criteria; working directory; authoritative files and versions; confirmed decisions and superseded decisions; constraints and permissions; completed work and verification evidence; unfinished changes; running work with identifiers and ownership; unknowns; and the first next action with its acceptance criteria. Distinguish agent checks from user acceptance. Do not copy the whole chat, secrets, or unrelated tasks. If there is no writable location, deliver the record in the reply and say that it is not saved to disk.

For a complete handoff include a unique handoff ID, available source/receiver chat IDs, authorized destination and scope, and accurate status. Use “materials verified,” “awaiting receiver verification,” “ready to continue,” “taken over,” or “blocked” as appropriate; creation alone is not takeover. Reuse the ID when recovering from an interrupted handoff.

Read back saved material and check that its references are accessible. Provide an opening prompt invoking `$handoff` with the record location, handoff ID, original working directory, authorized goal, constraints, and first step. Missing facts stay unknown.
