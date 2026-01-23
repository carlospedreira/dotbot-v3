---
name: New Tasks
description: Create change requests and generate tasks for new features, enhancements, or fixes
version: 2.0
---

# New Tasks Workflow

This workflow captures new requirements as a documented change request, then generates tasks using the same approach as the roadmap planning workflow.

## Goal
Capture new requirements, document them as a change request, and create well-scoped tasks via the `task_create_bulk` MCP tool.

## When to Use This
- Adding new features after initial roadmap
- Enhancement requests
- Bug fixes that need planning
- Technical debt or refactoring work
- Any new work not covered by the original PRD

## Process Overview

```
User Input → Document Change Request → Analyze & Break Down → Create Tasks via MCP
```

---

## Step 1: Gather Requirements

**Start with an open question:**

```
What would you like to add or change?

Please describe:
- What you want to accomplish
- Why it's needed
- Any specific requirements or constraints
- Expected behavior or outcomes

Paste your requirements below (can be detailed or brief - I'll ask clarifying questions if needed):
```

**Wait for user input before proceeding.**

---

## Step 2: Clarify Requirements (if needed)

If the input is unclear or incomplete, ask targeted questions:

**For Features:**
- What specific functionality do you want?
- What's the expected user experience?
- Are there edge cases to consider?
- How will you know it's working?

**For Enhancements:**
- What currently exists that you want to improve?
- What's the current limitation or pain point?
- What does "better" look like?

**For Fixes:**
- What's the current (buggy) behavior?
- What should happen instead?
- Can you reproduce it reliably?

**For Infrastructure/Chores:**
- What problem does this solve?
- Which components are affected?
- What are the success criteria?

---

## Step 3: Create Change Request Document

**Generate a change request file:**

Filename: `.bot/state/product/change-request-{yyyyMMdd_HHmmss}-{short-slug}.md`

Example: `change-request-20260123_131500-email-snooze.md`

**Template:**

```markdown
# Change Request: {Title}

**Created:** {Date/Time}
**Status:** Planning
**Type:** feature | enhancement | fix | infrastructure

## Summary
{One paragraph describing what this change accomplishes}

## Background
{Why this change is needed - context and motivation}

## Requirements

### Functional Requirements
- {Requirement 1}
- {Requirement 2}
- {Requirement 3}

### Non-Functional Requirements
- {Performance, security, or other constraints}

## Acceptance Criteria
- [ ] {Testable criterion 1}
- [ ] {Testable criterion 2}
- [ ] {Testable criterion 3}

## Technical Considerations
- {Affected components}
- {Dependencies on existing features}
- {Integration points}

## Out of Scope
- {What this change does NOT include}

## Related Documents
- `.bot/state/product/prd.md` - Original PRD
- `.bot/state/product/entity-model.md` - Entity model
```

**Save the change request before proceeding.**

---

## Step 4: Load Context

**Read existing product documents to understand current state:**

1. `.bot/state/product/mission.md` - Core principles
2. `.bot/state/product/tech-stack.md` - Technology choices
3. `.bot/state/product/entity-model.md` - Data model
4. `.bot/state/product/prd.md` - Original requirements

**Understand:**
- How this change fits with existing architecture
- Which existing components are affected
- What patterns to follow
- What dependencies exist

---

## Step 5: Break Down Into Tasks

**Apply the same breakdown approach as roadmap planning:**

1. Identify the functional area(s) affected
2. List specific capabilities needed
3. Break into implementation tasks
4. Ensure each task is:
   - Completable in 1-4 hours
   - Independently testable where possible
   - Small enough for a single context window

**Task sizing guide:**

| Effort | Duration | Examples |
|--------|----------|----------|
| XS | < 1 hour | Add field, simple config |
| S | 1-2 hours | Simple handler, basic query |
| M | 2-4 hours | Feature with tests |
| L | 4-8 hours | Complex feature |
| XL | 1-2 days | Major subsystem |

**Categories:**

| Category | Use For |
|----------|----------|
| `infrastructure` | Setup, database, config |
| `core` | Essential functionality |
| `feature` | User-facing capabilities |
| `enhancement` | Improvements to existing |
| `bugfix` | Corrections |

---

## Step 6: Present Task Breakdown

**Show the proposed tasks to user before creating:**

```markdown
## Proposed Tasks for: {Change Request Title}

I've broken this down into {N} tasks:

### Infrastructure ({count})
1. {Task name} - {brief description} `{effort}`

### Core/Feature ({count})
2. {Task name} - {brief description} `{effort}`
3. {Task name} - {brief description} `{effort}`

### Dependencies:
- Task 2 depends on Task 1
- Task 3 depends on Task 2

Total estimated effort: {sum}

**Proceed with creating these tasks?**
- A) Yes, create all tasks
- B) Review in more detail
- C) Adjust scope
```

**Wait for user confirmation before creating tasks.**

---

## Step 7: Create Tasks via MCP

**Use `task_create_bulk` to create all tasks:**

```javascript
task_create_bulk({
  tasks: [
    {
      name: "{Task name}",
      description: "{Detailed description referencing change request}",
      category: "{category}",
      priority: {calculated priority},
      effort: "{XS|S|M|L|XL}",
      dependencies: ["{dependency task IDs}"],
      acceptance_criteria: [
        "{Criterion 1}",
        "{Criterion 2}"
      ],
      steps: [
        "{Implementation step 1}",
        "{Implementation step 2}"
      ]
    }
    // ... all tasks
  ]
})
```

**Priority assignment:**
- Check existing tasks with `task_list` to find current max priority
- Assign new tasks with priorities after existing work
- Or interleave based on urgency if user specifies

---

## Step 8: Update Change Request Status

**After tasks are created, update the change request:**

```markdown
**Status:** Tasks Created
**Tasks Created:** {count}
**Task IDs:** {list of created task IDs}
```

---

## Step 9: Confirm Completion

**Report results to user:**

```
✓ Change request documented: .bot/state/product/change-request-{timestamp}-{slug}.md
✓ Created {N} tasks in .bot/state/tasks/todo/

Tasks created:
- {Task 1 name} ({effort}) - ID: {id}
- {Task 2 name} ({effort}) - ID: {id}
- {Task 3 name} ({effort}) - ID: {id}

Total estimated effort: {sum}

Use `task_get_next` to get the next available task.
```

---

## Task Schema Reference

Each task must include:

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Action-oriented title |
| `description` | Yes | What, where, why, how |
| `category` | Yes | infrastructure/core/feature/enhancement/bugfix |
| `priority` | Yes | 1-100 (1 = highest) |
| `effort` | Yes | XS/S/M/L/XL |
| `dependencies` | No | Task IDs this depends on |
| `acceptance_criteria` | Yes | Testable success conditions |
| `steps` | No | Implementation guidance |

---

## Guidelines

### Good Change Request Titles
- "Add email snooze functionality"
- "Improve sender enrichment performance"
- "Fix timezone handling in calendar"

### Good Task Names
- Action verb + specific component
- "Implement {X} command handler"
- "Add {X} entity and migration"
- "Create {X} background job"

### Good Acceptance Criteria
- Specific and testable
- Each starts with a verb
- Covers happy path and key edge cases

---

## Error Handling

- If MCP tools fail, report error and allow retry
- If partial success, report which tasks were created
- Change request document serves as recovery point
- User can re-run task creation from saved change request

---

## Success Criteria

✅ User requirements captured completely
✅ Change request documented in `.bot/state/product/`
✅ Existing product context considered
✅ Tasks broken down appropriately
✅ User approved task breakdown before creation
✅ Tasks created via `task_create_bulk` MCP tool
✅ Change request status updated
✅ User informed of results
