---
name: Retrospective Task Documentation
description: Template for creating retrospective documentation of completed work
version: 1.0
---

# Retrospective Task Documentation

You are documenting a completed coding session or work effort. Your goal is to create proper task and plan files that match the structure and quality of live-session documentation.

## Purpose

Use this workflow when:
- Documenting work that was completed outside of tracked sessions
- Creating historical records of past implementations
- Backfilling documentation for work that wasn't tracked in real-time

## Required Information

Before starting, gather:

1. **Work Description**
   - What problem was solved?
   - What was the approach taken?
   - What were the key decisions made?

2. **Files Changed**
   - Files created
   - Files modified
   - Files deleted

3. **Timeline**
   - When work started (approximate)
   - When work completed
   - Duration/effort estimate

4. **Validation**
   - How was success measured?
   - What criteria determined completion?

5. **Context** (optional)
   - Relevant commits
   - Related issues/tasks
   - Design decisions

---

## Implementation Protocol

### Step 1: Generate Task ID

1. Generate a UUID for the task
2. Extract the first 8 characters (before first hyphen)
3. This becomes your **short task ID** used in filenames

**Example**:
```
UUID: db728bce-f775-43b8-9d21-42016f7efe80
Short ID: db728bce
```

### Step 2: Determine File Names

Create a slugified version of the task name:

**Format**: `{task-name-slug}-{short-task-id}`

**Example**:
```
Task name: "Fix auth error handling and add auth checks to commands"
Slug: fix-auth-error-handling-and-add-auth-checks-to-commands
Short ID: db728bce
Result: fix-auth-error-handling-and-add-auth-checks-to-commands-db728bce
```

**File paths**:
- Task file: `.bot/workspace/tasks/done/{result}.json`
- Plan file: `.bot/workspace/plans/{result}-plan.md`

### Step 3: Read Sample Templates

Load the sample files to understand structure:

1. Read `.bot/workspace/tasks/samples/sample-task-retrospective.json`
2. Read `.bot/workspace/tasks/samples/sample-plan-retrospective.md`

These templates include inline comments explaining each field.

### Step 4: Create Task JSON

Using the sample as a guide, create the task JSON file:

**Required fields**:
- `id`: Full UUID
- `name`: Human-readable task name
- `description`: Detailed description with problem, approach, decisions
- `category`: One of: feature, bugfix, refactor, infrastructure, documentation
- `status`: Always "done" for retrospectives
- `priority`: Default to 10
- `effort`: T-shirt size (XS, S, M, L, XL)
- `created_at`, `started_at`, `completed_at`: ISO 8601 UTC timestamps (format: `yyyy-MM-ddTHH:mm:ssZ`)
- `plan_path`: `.bot/workspace/plans/{task-name-slug}-{short-id}-plan.md`
- `steps`: Array of high-level steps taken
- `acceptance_criteria`: Array of success criteria
- `files_created`, `files_modified`, `files_deleted`: Arrays of file paths

**Optional fields** (include if available):
- `commits`: Array of commit objects with details
- `activity_log`: Timeline of actions (can omit for retrospectives)
- `dependencies`: Task IDs this work depended on
- `applicable_standards`: Paths to standards followed
- `applicable_agents`: Agent personas used

**Important notes**:
- Remove all `_comment`, `_note`, `_instructions` fields from the final JSON
- Use relative paths from repo root for file paths
- Ensure `plan_path` matches the plan file you'll create in Step 5

**Save to**: `.bot/workspace/tasks/done/{task-name-slug}-{short-id}.json`

### Step 5: Create Plan Markdown

Using the sample as a guide, create the plan markdown file:

**Required sections**:
1. **Problem Statement**: What was the issue?
2. **Current State**: What existed before the work?
3. **Proposed Solution**: The approach taken
4. **Implementation Steps**: Phases and steps executed
5. **Success Criteria**: How success was measured

**Optional sections** (include if relevant):
- **Files Modified/Created**: Key files and their purpose
- **Testing/Verification**: How work was validated
- **Notes/Learnings**: Insights and future considerations

**Important notes**:
- Remove template instructions and example text
- Keep section headers but fill with actual content
- Be concise but complete - focus on key information
- Use markdown formatting for readability

**Save to**: `.bot/workspace/plans/{task-name-slug}-{short-id}-plan.md`

---

## Validation Checklist

Before finalizing, verify:

- [ ] Task JSON is valid JSON (no syntax errors)
- [ ] Task JSON has `plan_path` field pointing to correct plan file
- [ ] Task JSON uses correct file paths (relative from repo root)
- [ ] Task JSON has all required fields filled
- [ ] Task JSON has no `_comment`/`_note` fields remaining
- [ ] Plan markdown has all required sections
- [ ] Plan markdown has no template instructions remaining
- [ ] File names match pattern: `{task-name-slug}-{short-id}[.json|-plan.md]`
- [ ] Both files use same task name slug and short ID
- [ ] Files are saved to correct locations:
  - Task: `.bot/workspace/tasks/done/`
  - Plan: `.bot/workspace/plans/`

---

## Example Output

**Task name**: "Fix auth error handling"
**UUID**: `a1b2c3d4-1234-5678-9abc-def012345678`
**Short ID**: `a1b2c3d4`
**Slug**: `fix-auth-error-handling`

**Files created**:
- `.bot/workspace/tasks/done/fix-auth-error-handling-a1b2c3d4.json`
- `.bot/workspace/plans/fix-auth-error-handling-a1b2c3d4-plan.md`

**Task JSON `plan_path` value**:
```json
"plan_path": ".bot/workspace/plans/fix-auth-error-handling-a1b2c3d4-plan.md"
```

---

## Quality Standards

Your documentation should:
- Match the structure and detail of live-session tasks
- Provide enough context for someone unfamiliar with the work to understand it
- Include concrete specifics (file names, design decisions, outcomes)
- Be accurate and factual (no speculation about work that wasn't done)
- Use proper JSON syntax and markdown formatting

Remember: This documentation becomes part of the project's permanent record. Take time to make it accurate and complete.

---

## Data Format Requirements

### Date/Time Format

**All timestamps MUST use ISO 8601 UTC format**: `yyyy-MM-ddTHH:mm:ssZ`

**Correct examples**:
- `2026-01-24T07:54:09Z`
- `2026-01-26T13:00:00Z`

**Incorrect examples** (do NOT use):
- `24/01/2026 07:54:09` (UK locale)
- `01/24/2026 07:54:09` (US locale)
- `2026-01-24 07:54:09` (missing T and Z)

This applies to all date fields: `created_at`, `started_at`, `completed_at`, `updated_at`, and any timestamps in `activity_log`.

### Privacy Requirements

**MUST** before committing any task or plan files:

1. **No local paths** - Never include full paths like `C:\Users\...`, `/home/...`, or `/Users/...`. Use relative paths from repo root or `~` for home directory.
2. **No secrets** - Never include API keys, tokens, passwords, or connection strings.
3. **Run privacy scan** - Execute `.bot/hooks/verify/00-privacy-scan.ps1` before commit.

The privacy scan runs automatically in verification but you should self-check activity logs and file references.
