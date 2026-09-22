---
name: create-skill
description: 'Create reusable Copilot skills from a proven workflow, playbook, or debugging checklist. Use when turning a repeatable process into a SKILL.md that includes triggers, decisions, steps, and validation criteria.'
argument-hint: 'Workflow name or process to convert into a skill'
user-invocable: true
disable-model-invocation: false
---

# Create a Reusable Skill

## When to Use
- The user has followed a clear multi-step workflow, review process, or debugging checklist.
- The process is repeatable enough to be reused in future work.
- The goal is to package that process into a `SKILL.md` for agents or users.

## Goal
Turn an observed workflow into a reusable skill that can help future work without re-deriving the process each time.

## Procedure

### 1. Extract the workflow
Review the conversation or context and identify:
- the step-by-step process being followed;
- decision points and branching logic;
- quality criteria, completion checks, or success conditions;
- repeated patterns or common failure modes.

### 2. Generalize the pattern
Convert case-specific details into reusable guidance:
- describe when the skill applies;
- explain what the skill produces;
- rewrite steps as a clear, repeatable procedure;
- keep instructions actionable and concise.

### 3. Decide the scope
Determine whether the skill is:
- workspace-scoped for a project or team; or
- personal for cross-project use.

If the workflow is project-specific, place it under `.github/skills/<skill-name>/`.
If it is personal, place it under a user-level customization folder.

### 4. Write the skill file
Create a `SKILL.md` with this structure:

```yaml
---
name: skill-name
description: 'What it does and when to use it.'
argument-hint: 'Optional hint shown when invoked'
user-invocable: true
disable-model-invocation: false
---
```

Then add a body with:
- `## When to Use`
- `## Goal`
- `## Procedure`
- `## Decision Points`
- `## Completion Checks`

### 5. Include decision logic
For any branch in the workflow, document:
- when to choose one path over another;
- what evidence should be gathered before deciding;
- what to do if the condition is not met.

### 6. Validate the skill
Before finishing, check that:
- the folder name matches the `name` field;
- the description is keyword-rich and discovery-friendly;
- the process is clear enough to follow without the original conversation;
- the skill includes explicit completion checks;
- the instructions remain focused and not too vague.

## Decision Points
- If the workflow is clear and repeatable, package it as a skill.
- If the task is a single, narrow action, prefer a prompt instead.
- If the process should always apply to a project, place it in a workspace-level skill folder.
- If it is personal or cross-workspace, use a user-level skill location.
- If the workflow is too large or too dependent on context, split it into multiple skills or instructions.

## Completion Checks
A skill is ready when:
- it can be invoked without the original conversation context;
- the required steps are clear and ordered;
- the user can tell when to use it and when not to use it;
- the skill produces a consistent, usable result;
- any branching logic is described explicitly.

## Example prompts
- "Turn this debugging workflow into a reusable skill."
- "Package our review checklist into a SKILL.md for future project work."
- "Create a skill for testing and validating a web app before release."
- "Generalize the workflow we just used into a reusable team skill."

## Related customizations
- File instructions for project-wide rules
- Prompt files for one-off tasks
- Custom agents for isolated multi-stage workflows
- Hooks for deterministic enforcement
