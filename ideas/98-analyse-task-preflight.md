# 98-Analyse-Task: Pre-flight Analysis Workflow

## Overview

A new workflow phase that runs **after task creation but before implementation**. It front-loads all research, context gathering, planning, and human interaction so that the execution phase (99-autonomous-task) has everything it needs to code without exploration overhead.

## Problem Statement

Current 99-autonomous-task workflow:
- Reads product context (~23k tokens for Lintilla) even when not needed
- Searches codebase to find patterns and relevant files
- May create a plan mid-execution
- Discovers missing information during implementation
- Can't ask questions (operates autonomously)
- May attempt tasks that are too complex and fail

**Result**: Wasted tokens, longer execution times, failed attempts, no human input opportunity.

## Proposed Solution

### New Task Flow

```
task-create/bulk → todo/ 
                     ↓
              [98-analyse-task]
                     ↓
         ┌──────────┴──────────┐
         ↓                     ↓
   analysed/             needs-input/
         ↓                (wait for human)
  [99-autonomous-task]         ↓
         ↓              (human responds)
   in-progress/                ↓
         ↓                 analysed/
       done/
```

### New Task Statuses

| Status | Directory | Description |
|--------|-----------|-------------|
| `todo` | `workspace/tasks/todo/` | Created, awaiting analysis |
| `analysing` | `workspace/tasks/analysing/` | Currently being analysed by 98 |
| `needs-input` | `workspace/tasks/needs-input/` | Analysis paused, waiting for human |
| `analysed` | `workspace/tasks/analysed/` | Ready for implementation |
| `in-progress` | `workspace/tasks/in-progress/` | Being implemented by 99 |
| `done` | `workspace/tasks/done/` | Complete |
| `skipped` | `workspace/tasks/skipped/` | Skipped with reason |
| `cancelled` | `workspace/tasks/cancelled/` | Cancelled |
| `split` | `workspace/tasks/split/` | Replaced by sub-tasks |

## 98-Analyse-Task Workflow

### Phase 1: Initial Assessment

```markdown
1. Move task from `todo/` to `analysing/`
2. Read task metadata (name, description, acceptance criteria)
3. Determine task type:
   - Simple (XS/S effort, clear acceptance criteria) → lightweight analysis
   - Complex (M/L/XL effort, vague criteria) → full analysis
4. Check if plan already exists (from human or prior analysis)
```

### Phase 2: Context Extraction

```markdown
1. **Entity Detection**
   - Parse task description for domain entities
   - Match against `.bot/workspace/product/entity-model.md`
   - Extract ONLY relevant entity definitions (~200-500 tokens vs 4k)

2. **File Discovery**
   - Use grep/semantic search to find relevant files
   - Identify:
     - Files to modify
     - Files with patterns to follow
     - Test files to update
   - Store file paths (not contents) in analysis

3. **Dependency Analysis**
   - Check task dependencies are met
   - Identify implicit dependencies (e.g., needs DB migration first)
   - Check for blocking issues (e.g., required API not available)

4. **Standards Mapping**
   - Auto-detect applicable standards from task category + entities
   - Extract only relevant sections from standards files
```

### Phase 3: Plan Generation

```markdown
If no plan exists:
1. Generate implementation plan
2. Estimate complexity (may revise effort)
3. Identify risks and unknowns

If task is too complex (effort XL or estimated >4 hours):
1. Propose split into sub-tasks
2. Move to `needs-input/` for human approval
3. Wait for confirmation before splitting
```

### Phase 3b: Task Splitting (when approved)

```markdown
When human approves a split:
1. Create sub-tasks via task-create-bulk → land in `todo/`
2. Sub-tasks have `parent_task_id` reference to original
3. Move original task to `split/` (archived, not deleted)
4. Sub-tasks go through normal flow: todo → analyse → analysed → implement
```

#### Split Task Schema

Original task in `split/`:
```json
{
  "id": "a1b2c3d4-...",
  "name": "Refactor notification system",
  "status": "split",
  "split_at": "2026-02-03T17:10:00Z",
  "split_reason": "Task too complex (XL effort, 4+ components)",
  "child_tasks": [
    "e5f6g7h8-...",
    "i9j0k1l2-...",
    "m3n4o5p6-...",
    "q7r8s9t0-..."
  ]
}
```

Child tasks in `todo/`:
```json
{
  "id": "e5f6g7h8-...",
  "name": "Extract notification interfaces",
  "parent_task_id": "a1b2c3d4-...",
  "status": "todo",
  "effort": "S",
  "dependencies": [],
  "created_from_split": true
}
```

#### Split Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│ 98-analyse detects task is too complex                      │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ Move to needs-input/ with split_proposal                    │
│ Human sees: "Split into 4 sub-tasks? [Approve] [Reject]"    │
└─────────────────────────────────────────────────────────────┘
                            ↓
              ┌─────────────┴─────────────┐
              ↓                           ↓
┌─────────────────────────┐   ┌─────────────────────────┐
│ Human rejects           │   │ Human approves          │
│ → back to analysing/    │   │ → execute split         │
│ → complete analysis     │   └─────────────────────────┘
│ → may fail during 99    │               ↓
└─────────────────────────┘   ┌─────────────────────────┐
                              │ 1. task-create-bulk     │
                              │    creates N sub-tasks  │
                              │    → land in todo/      │
                              │                         │
                              │ 2. Original task        │
                              │    → moved to split/    │
                              │    → keeps history      │
                              └─────────────────────────┘
                                          ↓
                              ┌─────────────────────────┐
                              │ Sub-tasks go through    │
                              │ normal flow:            │
                              │ todo → 98-analyse →     │
                              │ analysed → 99-impl      │
                              └─────────────────────────┘
```

#### Why keep split tasks?

- **Traceability**: Know where sub-tasks came from
- **Metrics**: Track how often tasks need splitting
- **Reunification**: Could mark parent "done" when all children done
- **History**: Original requirements preserved

### Phase 4: Question Generation

```markdown
Analyse for ambiguities:
1. Missing acceptance criteria
2. Unclear requirements
3. Multiple valid approaches
4. Security/privacy concerns
5. Breaking change potential

If questions exist:
1. Format as structured questions (see Question Schema below)
2. Move task to `needs-input/`
3. Notify human via:
   - UI notification
   - Telegram message (if configured)
```

#### Question Schema

Questions follow the AskUserQuestions pattern - each question has:
- Clear, specific question text
- 3-5 numbered options (A, B, C, D, E)
- Option A is always the **recommended** choice
- Options ordered by recommendation strength
- Optional context/rationale for the recommendation

```json
{
  "pending_question": {
    "id": "q1",
    "question": "Should the delta link reset when the email sync start date changes?",
    "context": "Graph API delta queries don't support date filtering directly. Changing the start date affects which emails should be in scope.",
    "options": [
      {
        "key": "A",
        "label": "Reset delta and re-sync from new date (recommended)",
        "rationale": "Ensures data consistency - all emails from new start date will be processed. May cause temporary re-processing of some emails."
      },
      {
        "key": "B",
        "label": "Keep delta, filter new emails only",
        "rationale": "Faster, no re-sync needed. But emails between old and new start date won't be included."
      },
      {
        "key": "C",
        "label": "Prompt user to choose at runtime",
        "rationale": "Most flexible but adds UX complexity."
      },
      {
        "key": "D",
        "label": "Make it configurable via profile.yaml",
        "rationale": "Power users can choose, but adds configuration surface."
      }
    ],
    "recommendation": "A",
    "asked_at": "2026-02-03T17:00:00Z"
  },
  "questions_resolved": []
}
```

When answered, the question moves to `questions_resolved` and `pending_question` is either null or the next question.

#### Question Guidelines for 98-Analyse

1. **One at a time** - Ask single question, wait for answer, then ask next
2. **Be specific** - "Should X do Y?" not "How should we handle X?"
3. **Always recommend** - Option A must be a concrete recommendation
4. **Limit options** - 3-5 options max, more causes decision fatigue
5. **Include rationale** - Brief explanation for each option
6. **Order by strength** - A is best, B is second best, etc.
7. **Allow freeform** - Human can always reply with custom answer

#### Single Question Flow

```
┌─────────────────────────────────────────────────┐
│ 98-analyse identifies 3 questions needed        │
└─────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────┐
│ Ask Question 1 → needs-input/                   │
│ Wait for human response                         │
└─────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────┐
│ Human answers → record in questions_resolved    │
│ Continue analysis                               │
└─────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────┐
│ Ask Question 2 → needs-input/                   │
│ Wait for human response                         │
└─────────────────────────────────────────────────┘
                      ↓
             ... and so on ...
                      ↓
┌─────────────────────────────────────────────────┐
│ All questions answered → analysed/              │
└─────────────────────────────────────────────────┘
```

**Why one at a time:**
- Answers to Q1 may change Q2
- Reduces cognitive load for human
- Faster response per question
- Analysis can incorporate each answer before asking next

#### Example Questions

**Good question:**
```
Q: How should the notification service handle rate limiting from external APIs?

A) Exponential backoff with max 3 retries (recommended)
   → Industry standard, handles transient failures gracefully
B) Fixed delay retry (5 seconds between attempts)
   → Simpler but may not adapt to varying load
C) Fail fast and report to user
   → User aware but poor UX for transient issues
D) Queue and retry in background job
   → Most robust but adds infrastructure complexity
```

**Bad question:**
```
Q: What should we do about rate limiting?
   → Too vague, no options, no recommendation
```

### Phase 5: Context Packaging

```markdown
Write enriched analysis to task JSON:

{
  "analysis": {
    "analysed_at": "2026-02-03T17:00:00Z",
    "analysed_by": "claude-opus-4-5-20251101",
    
    "entities": {
      "primary": ["Email", "Settings"],
      "related": ["ProfileConfig", "GraphEmailService"],
      "context_summary": "Email sync feature using Graph API delta queries..."
    },
    
    "files": {
      "to_modify": [
        "src/Features/Email/SyncEmails.cs",
        "src/Shared/Configuration/ProfileConfig.cs"
      ],
      "patterns_from": [
        "src/Features/Calendar/SyncCalendar.cs"
      ],
      "tests_to_update": [
        "src/Tests/Features/SyncEmailsHandlerTests.cs"
      ]
    },
    
    "dependencies": {
      "task_dependencies": [],
      "implicit_dependencies": ["Graph API configured"],
      "blocking_issues": []
    },
    
    "standards": {
      "applicable": [".bot/standards/backend/api.md"],
      "relevant_sections": {
        ".bot/standards/backend/api.md": ["Error Handling", "Logging"]
      }
    },
    
    "product_context": {
      "mission_summary": "Multi-tenant SaaS for org management",
      "entity_definitions": "... extracted relevant entities only ...",
      "tech_stack_relevant": "EF Core, Graph SDK"
    },
    
    "implementation": {
      "approach": "Add date filter to Graph sync, reset delta on config change",
      "key_patterns": "Follow SyncCalendar.cs delta pattern",
      "risks": ["Graph API date filtering limitations"],
      "estimated_tokens": 3200
    },
    
    "questions_resolved": [
      {
        "question": "Should delta link reset when start date changes?",
        "answer": "Yes, per user confirmation",
        "answered_at": "2026-02-03T17:05:00Z"
      }
    ]
  }
}
```

### Phase 6: Status Transition

```markdown
If analysis complete with no questions:
  → Move to `analysed/`
  
If questions need human input:
  → Move to `needs-input/`
  → Set `analysis.pending_questions`
  
If task too complex:
  → Move to `needs-input/` with split proposal
  → Set `analysis.split_proposal`
```

---

## Changes Required

### 1. New Directories

```
workspace/tasks/
├── todo/           # existing
├── analysing/      # NEW
├── needs-input/    # NEW
├── analysed/       # NEW
├── in-progress/    # existing
├── done/           # existing
├── skipped/        # existing
├── cancelled/      # existing
└── split/          # NEW
```

### 2. New MCP Tools

#### `task-analyse` (or run via 98 workflow)
```yaml
name: task_analyse
description: Run pre-flight analysis on a task
parameters:
  task_id:
    type: string
    required: true
```

#### `task-mark-analysed`
```yaml
name: task_mark_analysed
description: Mark task as analysed and ready for implementation
parameters:
  task_id:
    type: string
    required: true
```

#### `task-mark-needs-input`
```yaml
name: task_mark_needs_input
description: Pause analysis pending human input with a single structured question
parameters:
  task_id:
    type: string
    required: true
  question:
    type: object
    description: Single structured question (AskUserQuestions pattern). One at a time.
    required: [question, options]
    properties:
      question:
        type: string
        description: Clear, specific question text
      context:
        type: string
        description: Background info to help human decide
      options:
        type: array
        description: 3-5 options, A is always the recommendation
        minItems: 3
        maxItems: 5
        items:
          type: object
          required: [key, label]
          properties:
            key:
              type: string
              enum: [A, B, C, D, E]
            label:
              type: string
              description: Option text (A should include "recommended" tag)
            rationale:
              type: string
              description: Brief explanation of pros/cons
```

**Note**: Only one question at a time. When human answers, 98-analyse continues and may ask another question or complete analysis.

#### `task-answer-question`
```yaml
name: task_answer_question
description: Human answers a pending question
parameters:
  task_id:
    type: string
    required: true
  question_index:
    type: integer
    required: true
  answer:
    type: string
    required: true
```

#### `task-approve-split`
```yaml
name: task_approve_split
description: Approve splitting a complex task
parameters:
  task_id:
    type: string
    required: true
  approved:
    type: boolean
    required: true
```

#### `task-get-context`
```yaml
name: task_get_context
description: Get pre-analysed context for a task (used by 99)
parameters:
  task_id:
    type: string
    required: true
returns:
  analysis object with all pre-gathered context
```

### 3. Modified MCP Tools

#### `task-get-next`
Change to prefer `analysed/` over `todo/`:
```powershell
# Priority order:
# 1. analysed/ tasks (ready for implementation)
# 2. todo/ tasks (need analysis first)
```

#### `task-create` / `task-create-bulk`
Option to auto-trigger analysis:
```yaml
parameters:
  auto_analyse:
    type: boolean
    default: false
    description: Immediately queue for analysis after creation
```

### 4. New Workflow File

`prompts/workflows/98-analyse-task.md`:
```markdown
---
name: Task Analysis
description: Pre-flight analysis workflow
version: 1.0
---

# Task Analysis Workflow

You are analysing task {{TASK_ID}} to prepare it for implementation.

## Your Goals
1. Extract relevant context (entities, files, patterns)
2. Create or validate implementation plan
3. Identify and resolve ambiguities
4. Package everything for efficient execution

## Do NOT
- Write any implementation code
- Make changes to the codebase
- Mark the task as in-progress or done

[... detailed instructions ...]
```

### 5. Modified 99-Autonomous-Task

Major simplification:
```markdown
## Phase 1: Quick Start

1. Mark task in-progress
2. Load pre-analysed context:
   ```
   mcp__dotbot__task_get_context({ task_id: "{{TASK_ID}}" })
   ```
3. All context is ready - start implementing

## Removed Sections
- ❌ "Read ONLY what you need" (already done)
- ❌ "Start with targeted exploration" (files pre-identified)
- ❌ "Efficiency Guidelines" (no exploration needed)
- ❌ Plan creation (already exists)
```

New 99 workflow drops from ~480 lines to ~200 lines.

### 6. UI Changes

#### New Panel: "Needs Input"
```
┌─────────────────────────────────────────────────────────────────────┐
│ Tasks Needing Input                                            (2)  │
├─────────────────────────────────────────────────────────────────────┤
│ ▶ add-email-sync-filter [c2d58aaf]                    Question 1/1  │
│   ┌─────────────────────────────────────────────────────────────┐   │
│   │ Should the delta link reset when email sync start date      │   │
│   │ changes?                                                    │   │
│   │                                                             │   │
│   │ Context: Graph API delta queries don't support date         │   │
│   │ filtering directly.                                         │   │
│   │                                                             │   │
│   │ ● A) Reset delta and re-sync (recommended)                  │   │
│   │ ○ B) Keep delta, filter new emails only                     │   │
│   │ ○ C) Prompt user to choose at runtime                       │   │
│   │ ○ D) Make it configurable via profile.yaml                  │   │
│   │                                                             │   │
│   │ [A] [B] [C] [D] [Custom Answer...]                          │   │
│   └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
│ ▶ refactor-notification-system [a1b2c3d4]              Split Review │
│   ┌─────────────────────────────────────────────────────────────┐   │
│   │ Task is too complex (XL effort). Proposed split:            │   │
│   │                                                             │   │
│   │ 1. Extract notification interfaces (S)                     │   │
│   │ 2. Implement email notification provider (M)                │   │
│   │ 3. Implement push notification provider (M)                 │   │
│   │ 4. Add notification preferences to user settings (S)        │   │
│   │                                                             │   │
│   │ [Approve Split] [Reject & Keep Original]                    │   │
│   └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

### 9. Roadmap UI Redesign Options

The current roadmap shows a simple list. With the new flow, we need to visualize:
- Multiple stages (todo → analysing → analysed → in-progress → done)
- Tasks waiting for input
- Split relationships (parent → children)
- Progress through the pipeline

#### Option A: Kanban Board (Recommended)

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│ Task Pipeline                                                          [Filter] [Sort]  │
├───────────────┬───────────────┬───────────────┬───────────────┬───────────────┬────────┤
│ Todo (5)      │ Analysing (1) │ Analysed (3)  │ In Progress(1)│ Done (12)     │ Split  │
├───────────────┼───────────────┼───────────────┼───────────────┼───────────────┼────────┤
│ ┌───────────┐ │ ┌───────────┐ │ ┌───────────┐ │ ┌───────────┐ │ ┌───────────┐ │ ┌────┐ │
│ │ Add email │ │ │ ● Refactor│ │ │ ✓ Add cal │ │ │ ● Fix tz  │ │ │ ✓ Add    │ │ │ 2  │ │
│ │ archive   │ │ │   notifs  │ │ │   sync    │ │ │   bug     │ │ │   auth   │ │ │    │ │
│ │ [S]       │ │ │   [M]     │ │ │   [M]     │ │ │   [S]     │ │ │   [S]    │ │ └────┘ │
│ └───────────┘ │ └───────────┘ │ └───────────┘ │ └───────────┘ │ └───────────┘ │        │
│ ┌───────────┐ │               │ ┌───────────┐ │               │ ┌───────────┐ │        │
│ │ Update    │ │               │ │ Add push  │ │               │ │ ✓ Setup  │ │        │
│ │ graph SDK │ │               │ │ notifs    │ │               │ │   CI/CD  │ │        │
│ │ [M]       │ │               │ │ [S]       │ │               │ │   [M]    │ │        │
│ └───────────┘ │               └───────────────┴───────────────┴───────────────┴────────┤
│ ┌───────────┐ │                                                                        │
│ │ ⚠ Config  │ │  Legend: ● Active  ✓ Ready  ⚠ Needs Input  ◆ From Split              │
│ │ migration │ │                                                                        │
│ │ [S] ⚠     │ │                                                                        │
│ └───────────┘ │                                                                        │
└───────────────┴────────────────────────────────────────────────────────────────────────┘
```

**Pros**: Familiar pattern, clear stages, drag-drop possible, shows WIP limits
**Cons**: Horizontal space limited, doesn't show dependencies well

---

#### Option B: Pipeline Flow (Horizontal Swimlanes)

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│ Task Pipeline                                                                           │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                         │
│  TODO ──────────► ANALYSE ──────────► READY ──────────► IMPLEMENT ──────────► DONE     │
│                                                                                         │
│  ┌─────────┐      ┌─────────┐         ┌─────────┐       ┌─────────┐         ┌────────┐ │
│  │ Task A  │─────►│ Task B  │────────►│ Task C  │──────►│ Task D  │────────►│ Task E │ │
│  │ [S]     │      │ [M] ●   │         │ [M] ✓   │       │ [S] ●   │         │ [S] ✓  │ │
│  └─────────┘      └─────────┘         └─────────┘       └─────────┘         └────────┘ │
│                                                                                         │
│  ┌─────────┐                          ┌─────────┐                           ┌────────┐ │
│  │ Task F  │                          │ Task G  │                           │ Task H │ │
│  │ [M]     │                          │ [S] ✓   │                           │ [M] ✓  │ │
│  └─────────┘                          └─────────┘                           └────────┘ │
│                                                                                         │
│  ┌─────────┐      ⚠ NEEDS INPUT                                                        │
│  │ Task I  │      ┌─────────────────────────────────────┐                              │
│  │ [XL]    │─────►│ Task J - Waiting for answer (Q1/2)  │                              │
│  └─────────┘      │ [XL] "Should we split?" [Respond]   │                              │
│                   └─────────────────────────────────────┘                              │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

**Pros**: Shows flow direction, highlights blockers, good for tracking individual tasks
**Cons**: Doesn't scale well with many tasks, hard to see totals

---

#### Option C: Funnel View (Vertical Stages)

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│ Task Pipeline                                              Today: 3 analysed, 1 done    │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                         │
│  ╔═══════════════════════════════════════════════════════════════════════════════════╗  │
│  ║  TODO (5)                                                                         ║  │
│  ║  ┌────┐ ┌────┐ ┌────┐ ┌────┐ ┌────┐                                              ║  │
│  ║  │ A  │ │ B  │ │ C  │ │ D  │ │ E  │                                              ║  │
│  ║  └────┘ └────┘ └────┘ └────┘ └────┘                                              ║  │
│  ╚═══════════════════════════════════════════════════════════════════════════════════╝  │
│                                    ▼                                                    │
│  ╔═══════════════════════════════════════════════════════════════════════════════════╗  │
│  ║  ANALYSING (1)  ●                                                                 ║  │
│  ║  ┌──────────────────────────────────────┐                                         ║  │
│  ║  │ Refactor notification system [M]     │                                         ║  │
│  ║  │ Progress: Extracting entities...     │                                         ║  │
│  ║  └──────────────────────────────────────┘                                         ║  │
│  ╚═══════════════════════════════════════════════════════════════════════════════════╝  │
│                                    ▼                                                    │
│  ╔═══════════════════════════════════════════════════════════════════════════════════╗  │
│  ║  ⚠ NEEDS INPUT (1)                                                                ║  │
│  ║  ┌──────────────────────────────────────────────────────────────────────────────┐ ║  │
│  ║  │ Config migration [S]                                                         │ ║  │
│  ║  │ Q: Should old config format be supported?  [A] [B] [C] [Custom]              │ ║  │
│  ║  └──────────────────────────────────────────────────────────────────────────────┘ ║  │
│  ╚═══════════════════════════════════════════════════════════════════════════════════╝  │
│                                    ▼                                                    │
│  ╔═══════════════════════════════════════════════════════════════════════════════════╗  │
│  ║  ANALYSED (3) ✓ Ready for implementation                                          ║  │
│  ║  ┌────┐ ┌────┐ ┌────┐                                                            ║  │
│  ║  │ F  │ │ G  │ │ H  │  ← Next up for 99-autonomous                               ║  │
│  ║  └────┘ └────┘ └────┘                                                            ║  │
│  ╚═══════════════════════════════════════════════════════════════════════════════════╝  │
│                                    ▼                                                    │
│  ╔═══════════════════════════════════════════════════════════════════════════════════╗  │
│  ║  IN PROGRESS (1) ●                                                                ║  │
│  ║  ┌──────────────────────────────────────┐                                         ║  │
│  ║  │ Fix timezone bug [S]                 │  Implementing... (5 min)                ║  │
│  ║  └──────────────────────────────────────┘                                         ║  │
│  ╚═══════════════════════════════════════════════════════════════════════════════════╝  │
│                                    ▼                                                    │
│  ╔═══════════════════════════════════════════════════════════════════════════════════╗  │
│  ║  DONE (12) ✓                                                              [+12]   ║  │
│  ╚═══════════════════════════════════════════════════════════════════════════════════╝  │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

**Pros**: Clear progression, inline Q&A, shows bottlenecks, good mobile view
**Cons**: Takes vertical space, may need scrolling

---

#### Option D: Hybrid - Compact Stats + Expandable Detail

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│ Pipeline Overview                                                                       │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                         │
│  ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐               │
│  │  TODO   │───►│ANALYSING│───►│ANALYSED │───►│IN PROG  │───►│  DONE   │               │
│  │    5    │    │    1    │    │    3    │    │    1    │    │   12    │               │
│  │   ○○○   │    │    ●    │    │   ✓✓✓   │    │    ●    │    │  ████   │               │
│  └─────────┘    └─────────┘    └─────────┘    └─────────┘    └─────────┘               │
│                      │                                                                  │
│                      └──── ⚠ 1 task needs input                                        │
│                                                                                         │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│ ⚠ Action Required                                                             [1 item] │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│ Config migration [S]                                                                    │
│ Q: Should old config format be supported?                                               │
│                                                                                         │
│ ● A) Drop old format, require migration (recommended)                                   │
│ ○ B) Support both formats with adapter                                                  │
│ ○ C) Auto-migrate on first read                                                         │
│                                                                                         │
│ [Submit A] [Submit B] [Submit C] [Custom Answer...]                                     │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│ ▶ Todo (5)                                                                    [expand] │
│ ▶ Analysing (1)                                                               [expand] │
│ ▼ Analysed - Ready (3)                                                        [expand] │
│   ┌─────────────────────────────────────────────────────────────────────────────────┐  │
│   │ ◆ Extract notification interfaces [S] - from split                              │  │
│   │   Add calendar sync [M]                                                         │  │
│   │   Add push notifications [S]                                                    │  │
│   └─────────────────────────────────────────────────────────────────────────────────┘  │
│ ▶ In Progress (1)                                                             [expand] │
│ ▶ Done (12)                                                                   [expand] │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

**Pros**: Compact overview, inline Q&A prominent, expandable detail, works on all screens
**Cons**: More clicks to see details, split relationships less visible

---

#### Recommendation: Option D (Hybrid)

- **Top**: Compact pipeline with counts and visual indicators
- **Action Required**: Always visible, inline Q&A for immediate response
- **Expandable sections**: Detail on demand
- **Split indicator**: ◆ marks tasks from splits, expandable to show parent

---

### 10. Homepage Redesign

Current homepage shows session stats and basic task overview. With the new flow, it needs to surface:
- Pipeline health at a glance
- Tasks needing input (urgent)
- Current activity (analysing/implementing)
- Quick task creation

#### New Homepage Layout

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│ dotbot                                                    [+ New Task]  [⚙ Settings]   │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                         │
│  ┌─────────────────────────────────────┐  ┌─────────────────────────────────────────┐  │
│  │ Pipeline Status                     │  │ Session                                 │  │
│  │                                     │  │                                         │  │
│  │  TODO → ANALYSE → READY → IMPL → ✓  │  │  Started: 2h 15m ago                    │  │
│  │   5       1        3       1    12  │  │  Tasks completed: 4                     │  │
│  │                                     │  │  Model: claude-opus-4-5                 │  │
│  │  ⚠ 1 needs input                    │  │  Status: ● Implementing                 │  │
│  └─────────────────────────────────────┘  └─────────────────────────────────────────┘  │
│                                                                                         │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│ ⚠ Action Required                                                              [1 item] │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│ ┌─────────────────────────────────────────────────────────────────────────────────────┐ │
│ │ Config migration [S]                                                                │ │
│ │ Q: Should old config format be supported?                                           │ │
│ │                                                                                     │ │
│ │ ● A) Drop old format, require migration (recommended)                               │ │
│ │ ○ B) Support both formats with adapter                                              │ │
│ │ ○ C) Auto-migrate on first read                                                     │ │
│ │                                                                                     │ │
│ │ [A] [B] [C] [Custom...]                                                             │ │
│ └─────────────────────────────────────────────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│ Current Activity                                                                        │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│ ┌─────────────────────────────────────────────────────────────────────────────────────┐ │
│ │ ● IMPLEMENTING: Fix timezone bug [S]                                     5 min      │ │
│ │   Phase: Verification - running tests                                               │ │
│ │   Files: src/Services/TimeZoneService.cs, src/Tests/TimeZoneTests.cs                │ │
│ └─────────────────────────────────────────────────────────────────────────────────────┘ │
│ ┌─────────────────────────────────────────────────────────────────────────────────────┐ │
│ │ ○ ANALYSING: Refactor notification system [M]                            2 min      │ │
│ │   Phase: Context extraction - finding patterns                                      │ │
│ └─────────────────────────────────────────────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│ Quick Stats                                                                             │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│  Today: 4 done │ This week: 18 done │ Avg time: 12 min │ Success rate: 94%             │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

---

### 11. Task Creation from UI

Allow task creation from both Homepage and Roadmap tabs.

#### Quick Add (Top Bar)

Always visible "+ New Task" button opens a modal:

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│ Create Task                                                                      [×]    │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                         │
│  Name *                                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────────────┐   │
│  │ Add email archive feature                                                       │   │
│  └─────────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                         │
│  Description *                                                                          │
│  ┌─────────────────────────────────────────────────────────────────────────────────┐   │
│  │ Allow users to archive emails instead of deleting them.                         │   │
│  │ Archived emails should be searchable but not shown in main inbox.               │   │
│  │                                                                                 │   │
│  │                                                                                 │   │
│  └─────────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐                                  │
│  │ Category     │  │ Effort       │  │ Priority     │                                  │
│  │ [feature ▼]  │  │ [M ▼]        │  │ [50      ]   │                                  │
│  └──────────────┘  └──────────────┘  └──────────────┘                                  │
│                                                                                         │
│  ▶ Acceptance Criteria (optional)                                            [expand]  │
│  ▶ Implementation Steps (optional)                                           [expand]  │
│  ▶ Dependencies (optional)                                                   [expand]  │
│                                                                                         │
│  ☑ Auto-analyse after creation                                                         │
│                                                                                         │
│  ┌─────────────────────────────────────────────────────────────────────────────────┐   │
│  │                    [Cancel]                    [Create Task]                    │   │
│  └─────────────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

#### Bulk Add Mode

For roadmap planning, allow pasting multiple tasks:

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│ Bulk Create Tasks                                                                [×]    │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                         │
│  Paste task list (one per line, or JSON):                                              │
│  ┌─────────────────────────────────────────────────────────────────────────────────┐   │
│  │ Add email archive feature                                                       │   │
│  │ Implement email search                                                          │   │
│  │ Add email labels/tags                                                           │   │
│  │ Create email filters                                                            │   │
│  │                                                                                 │   │
│  └─────────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                         │
│  Default settings for all:                                                              │
│  ┌──────────────┐  ┌──────────────┐                                                    │
│  │ Category     │  │ Effort       │                                                    │
│  │ [feature ▼]  │  │ [M ▼]        │                                                    │
│  └──────────────┘  └──────────────┘                                                    │
│                                                                                         │
│  ☑ Auto-analyse all after creation                                                     │
│                                                                                         │
│  Preview: 4 tasks will be created                                                       │
│   1. Add email archive feature [feature, M]                                            │
│   2. Implement email search [feature, M]                                               │
│   3. Add email labels/tags [feature, M]                                                │
│   4. Create email filters [feature, M]                                                 │
│                                                                                         │
│  ┌─────────────────────────────────────────────────────────────────────────────────┐   │
│  │                    [Cancel]                    [Create 4 Tasks]                 │   │
│  └─────────────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

#### Inline Add on Roadmap

On the Roadmap tab, add "+ Add task" at bottom of Todo column:

```
┌───────────────┐
│ Todo (5)      │
├───────────────┤
│ ┌───────────┐ │
│ │ Task A    │ │
│ └───────────┘ │
│ ┌───────────┐ │
│ │ Task B    │ │
│ └───────────┘ │
│               │
│ ┌───────────┐ │
│ │ + Add     │ │  ← Click to expand inline form
│ │   task    │ │
│ └───────────┘ │
└───────────────┘
```

Clicking expands to quick inline form:

```
┌───────────────────────────────────────┐
│ + New Task                            │
│ ┌───────────────────────────────────┐ │
│ │ Task name...                      │ │
│ └───────────────────────────────────┘ │
│ ┌───────────────────────────────────┐ │
│ │ Brief description...              │ │
│ └───────────────────────────────────┘ │
│ [S] [M] [L]  [Cancel] [Add]           │
└───────────────────────────────────────┘
```

#### API Endpoint

UI task creation calls existing MCP tools via HTTP:

```
POST /api/task/create
{
  "name": "Add email archive feature",
  "description": "...",
  "category": "feature",
  "effort": "M",
  "auto_analyse": true
}

POST /api/task/create-bulk
{
  "tasks": [...],
  "auto_analyse": true
}
```

Server routes to `Invoke-TaskCreate` / `Invoke-TaskCreateBulk` MCP tools.

#### New Panel: "Analysis Queue"
```
┌─────────────────────────────────────────────────┐
│ Analysis Queue                             (5)  │
├─────────────────────────────────────────────────┤
│ ● analysing  add-calendar-sync [1/5]            │
│ ○ pending    add-notification-rules             │
│ ○ pending    add-email-archive                  │
│ ○ pending    fix-timezone-bug                   │
│ ○ pending    update-graph-sdk                   │
└─────────────────────────────────────────────────┘
```

### 7. Telegram Integration

For remote human input:

```
🔔 Task needs input: add-email-sync-filter

📋 Question 1 of 1:
Should the delta link reset when email sync start date changes?

💡 Context:
Graph API delta queries don't support date filtering directly. Changing the start date affects which emails should be in scope.

Options:
A) Reset delta and re-sync from new date ⭐ recommended
   → Ensures data consistency, may cause temporary re-processing

B) Keep delta, filter new emails only
   → Faster, but emails between old/new start date won't be included

C) Prompt user to choose at runtime
   → Most flexible but adds UX complexity

D) Make it configurable via profile.yaml
   → Power users can choose, adds configuration surface

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Reply: A, B, C, D or type custom answer
```

**Split proposal via Telegram:**
```
🔔 Task too complex: refactor-notification-system

📊 Analysis suggests splitting into 4 sub-tasks:

1️⃣ Extract notification interfaces (S)
2️⃣ Implement email notification provider (M)
3️⃣ Implement push notification provider (M)
4️⃣ Add notification preferences to user settings (S)

Total effort: 4 tasks vs 1 XL task

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Reply: APPROVE or REJECT
```

### 8. Run Loop Changes

New `analyse-loop.ps1`:
```powershell
# Separate loop for analysis phase
# Can run in parallel with implementation loop
# Or as pre-processing before implementation

param(
    [int]$MaxTasks = 0,
    [switch]$WaitForInput  # Pause when tasks need input
)

while ($true) {
    # Get next todo task
    $task = Get-NextTodoTask
    if (-not $task) { break }
    
    # Run 98-analyse-task workflow
    Invoke-ClaudeCLI -Prompt (Build-AnalysePrompt -Task $task)
    
    # Check result
    if ($task.status -eq 'needs-input' -and $WaitForInput) {
        Write-Host "Waiting for human input on $($task.id)..."
        Wait-ForInput -TaskId $task.id
    }
}
```

Modified `run-loop.ps1`:
```powershell
# Change task source from todo/ to analysed/
$task = Invoke-TaskGetNext  # Now prefers analysed/ tasks

if (-not $task) {
    # No analysed tasks - check if there are todo tasks
    $todoCount = Get-TodoTaskCount
    if ($todoCount -gt 0) {
        Write-Host "No analysed tasks. Run analyse-loop.ps1 first."
    }
}
```

---

## Token Impact Analysis

### Before (99 reads everything)

| Item | Tokens | When |
|------|--------|------|
| Workflow | ~2,000 | Always |
| Product mission | ~400 | Often |
| Entity model | ~4,000 | Often |
| PRD | ~14,000 | Sometimes |
| Tech stack | ~500 | Sometimes |
| Standards | ~2,000 | Always |
| Agent persona | ~500 | Always |
| Codebase exploration | ~5,000+ | Always |
| **Total per task** | **~25,000+** | |

### After (98 pre-analyses, 99 gets packaged context)

| Item | Tokens | When |
|------|--------|------|
| 98 Analysis (one-time) | ~15,000 | Once per task |
| 99 Workflow (simplified) | ~800 | Always |
| Pre-packaged context | ~2,000-3,000 | Always |
| **Total per task** | **~3,000-4,000** | |

**Savings**: ~85% token reduction on implementation phase.

---

## Migration Path

### Phase 1: Add Infrastructure
1. Create new directories
2. Add new MCP tools
3. Add new task statuses to existing tools

### Phase 2: Create 98 Workflow
1. Write `98-analyse-task.md`
2. Create `analyse-loop.ps1`
3. Test with manual invocation

### Phase 3: UI Integration
1. Add "Needs Input" panel
2. Add "Analysis Queue" panel
3. Add question/answer UI

### Phase 4: Telegram Integration
1. Add question notification
2. Add answer handling
3. Test remote workflow

### Phase 5: Simplify 99
1. Reduce 99-autonomous-task.md
2. Add `task_get_context` call
3. Remove exploration sections

### Phase 6: Integrate Loops
1. Option A: Run 98 then 99 sequentially
2. Option B: Run 98 and 99 in parallel (different task pools)
3. Option C: Single loop that analyses then implements

---

## Open Questions

1. **Should 98 and 99 use same model?**
   - 98 could use Sonnet (cheaper for research)
   - 99 could use Opus (better for implementation)

2. **How to handle analysis failures?**
   - Retry with more context?
   - Move to needs-input?
   - Skip and let 99 handle it?

3. **Should splitting require human approval?**
   - Always require approval (safer)
   - Auto-approve if confidence high
   - Configurable per project

4. **Question timeout handling?**
   - Skip task after N hours?
   - Notify again?
   - Make default assumption?

5. **Batch analysis vs individual?**
   - Analyse all todo tasks at once?
   - Analyse on-demand when 99 needs work?
   - Background analysis during idle?

---

## Success Metrics

| Metric | Before | Target |
|--------|--------|--------|
| Tokens per implementation | ~25,000 | ~4,000 |
| Failed first attempts | ~20% | ~5% |
| Human intervention needed | Post-failure | Pre-implementation |
| Task completion time | Variable | More predictable |
| Context accuracy | Best-effort | Pre-validated |
