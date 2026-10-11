---
name: p3-status
description: "Show one read-only view of this project's live T3 state: what needs the user, what is running, wakes left armed for nothing, and linked PRs. Use for /p3-status, 'what needs me', 'status', 'what's running', or a check-in on a long run."
---

# p3 status

**You own one honest picture of what T3 is doing in this project right now, and what needs the user.** Read-only. Answer nothing, settle nothing, delete nothing, send nothing until the user says so. `/recall` rebuilds history. This skill reads live state.

## Collect

Issue the independent calls in one turn. Scope is the current project. Never read another project's threads.

1. `t3_thread_list` with `settled: false` and `statuses` `waiting`, `failed`, `interrupted`, `running`, `queued`, `starting`, `preparing`, `completed`. Follow `nextCursor` to the end. A settled thread is one the user already dismissed, so leave it out. Drop rows with `relationshipToParent: "subagent"` too. The status filter returns delegated children, and their parent thread owns them.
2. For each `waiting` thread, `t3_pending_request_list`, then `t3_pending_request_read` for each question. Approval prompts are not listed. A waiting thread with no listed question is most likely on a permission prompt. Say that, and don't guess the prompt.
3. `list_scheduled_tasks`. Keep each task's title, `enabled`, `nextRunAt`, `lastRunStatus`, and bound thread.
4. `list_thread_pull_requests` for each thread from step 1 that is not `completed`, plus this thread. Its `state` is T3's last-known copy and lags the forge, so confirm every PR it calls open with `gh pr view <url> --json state,mergeable,reviewDecision,statusCheckRollup`.
5. `read_pull_request_guide` for each PR that is still open. If guides are off, note it once and skip the rest.
6. If the project has an orchestrate store (`orchestrate/*/gates.md`), read its open gates.

## Classify

- **Needs you.** Pending questions, quoted. Waiting threads that are likely on a permission prompt. Failed or interrupted threads. Open PRs that are merge-ready and wait only on a human review or click. Open orchestrate gates.
- **Working.** Running, queued, starting, and preparing threads, with time since `updatedAt`. A running thread unchanged for over an hour is a suspected stall. Flag it, and don't diagnose it here.
- **Stale wakes.** Enabled ticks bound to a settled or completed thread, and watches on PRs the forge reports merged or closed. They wake threads for nothing.
- **Done, unsettled.** Completed threads still in the active list.

## Report

Render the four sections with `html_preview`, then `html_render`, in the order above. Give one row per item with its title, status, age, and a one-line reason. PR rows show the number, the forge state, checks, review decision, and guide state.

**Reply:** the Needs-you items only, each thread linked as `[title](t3-thread://v1/<threadId>)` with its exact `threadId` and each PR by URL. Then one line of counts for the other sections. Then offer the actions the user can approve with one word: settle the done threads (`t3_thread_organize`), delete or disable the stale ticks (`delete_scheduled_task`, `update_scheduled_task`), drop dead watches (`unwatch_pull_request`). Act only on a yes.
