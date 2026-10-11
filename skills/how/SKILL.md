---
name: how
description: "Use for \"how does X work\", code walkthroughs before changing something, and placement / ownership / layering questions (\"where should this live\", \"which package owns this\", \"is this the right layer\"). Explains subsystem architecture, runtime flow, onboarding mental models. Use why for motivation."
---

# How

Explore the codebase to answer "how does X work?" questions. Produce architectural explanations at the level of a senior engineer onboarding onto a subsystem, enough to build a working mental model, not so much that it reads like annotated source code.

Every spawn is a `delegate_task` with a self-contained brief; the child gets only the brief, never this conversation. Each brief says it is read-only: inspect only, no writes, no git commands. Spawn each with `interactionMode: "plan"` and `role: "research"`, so the child's harness enforces read-only too. Explorers use the `how explorer` line in `p3-models.md` (project root, else `~/.agents/p3-models.md`), and every explainer uses the `how explainer` line. Resolve each through `orchestrator_capabilities`. Never hardcode a slug. If the line is missing, use the parent's model and suggest the user run `/setup-p3`.

## 1. Assess complexity

If the scope is ambiguous, state your interpretation and explore. The user can redirect.

- **Simple** (a single module, a small utility, a narrow question such as "how does function X work"): no explorers. Spawn one explainer that explores and explains in one pass, built from `references/explainer-prompt.md` without the explorer-findings section. Go to step 4.
- **Complex** (a subsystem spanning multiple files or services, a cross-cutting feature, a full architectural overview): go to step 2.

When in doubt, take the simple path.

## 2. Explore (complex only)

Decompose the question into 2 to 4 angles, each a distinct slice of the subsystem. Spawn all explorers in a single message, `mode: "async"`, each with `references/explorer-prompt.md` and its angle filled in. End the turn and take each result from its completion wake.

## 3. Synthesize (complex only)

Once all explorers are in, spawn one explainer with `references/explainer-prompt.md` and every explorer's findings filled in.

## 4. Present

Present the explainer's output. Light edits for clarity or context from the conversation are fine. Do not substantially rewrite it.

## Output format

The explanation uses the sections defined in `references/explainer-prompt.md`, dropping any that do not apply: Overview, Key Concepts, How It Works, Where Things Live, Gotchas.
