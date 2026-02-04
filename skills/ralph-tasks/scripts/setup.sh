#!/bin/bash
# Ralph Tasks Setup Script - Creates task queue infrastructure
# Usage: ./setup.sh <project-path>

set -e

PROJECT_PATH="${1:-.}"

# Resolve absolute path
PROJECT_PATH=$(cd "$PROJECT_PATH" && pwd)
RALPH_TASKS_DIR="$PROJECT_PATH/.claude/ralph-tasks"

echo "🚀 Setting up Ralph Tasks in: $PROJECT_PATH"

# Create directory structure
mkdir -p "$RALPH_TASKS_DIR"

# Create tasks.json
cat > "$RALPH_TASKS_DIR/tasks.json" << 'TASKS_JSON'
{
  "tasks": [],
  "lastId": 0
}
TASKS_JSON

echo "✅ Created tasks.json"

# Create wake-up.sh (main loop script)
cat > "$RALPH_TASKS_DIR/wake-up.sh" << 'WAKEUP_SH'
#!/bin/bash
# Ralph Tasks - Continuous Execution Loop
# Usage: ./wake-up.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
TASKS_FILE="$SCRIPT_DIR/tasks.json"
PROMPT_FILE="$SCRIPT_DIR/prompt.md"
PROGRESS_FILE="$SCRIPT_DIR/progress.txt"
WAIT_SECONDS=60

echo "╔════════════════════════════════════════════════════════════╗"
echo "║                 🤖 RALPH TASKS STARTING                    ║"
echo "╠════════════════════════════════════════════════════════════╣"
echo "║ Project: $PROJECT_DIR"
echo "║ Tasks file: $TASKS_FILE"
echo "║ Wait interval: ${WAIT_SECONDS}s when no tasks"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Press Ctrl+C to stop"
echo ""

cd "$PROJECT_DIR"

ITERATION=0

while true; do
  ITERATION=$((ITERATION + 1))

  # Get pending tasks count
  PENDING=$(jq '[.tasks[] | select(.status == "pending")] | length' "$TASKS_FILE")
  IN_PROGRESS=$(jq '[.tasks[] | select(.status == "in_progress")] | length' "$TASKS_FILE")
  COMPLETED=$(jq '[.tasks[] | select(.status == "completed")] | length' "$TASKS_FILE")
  TOTAL=$(jq '.tasks | length' "$TASKS_FILE")

  echo ""
  echo "═══════════════════════════════════════════════════════════════"
  echo "📍 Iteration $ITERATION | Pending: $PENDING | In Progress: $IN_PROGRESS | Completed: $COMPLETED / $TOTAL"
  echo "═══════════════════════════════════════════════════════════════"

  if [ "$PENDING" -eq 0 ] && [ "$IN_PROGRESS" -eq 0 ]; then
    echo ""
    echo "💤 No pending tasks. Waiting ${WAIT_SECONDS} seconds..."
    echo "   (Add tasks with: /ralph-tasks add /"your task/")"
    sleep "$WAIT_SECONDS"
    continue
  fi

  # Run Claude with the prompt
  echo ""
  echo "🚀 Starting Claude agent..."
  echo ""

  OUTPUT=$(claude -p --dangerously-skip-permissions /
    "@$TASKS_FILE @$PROGRESS_FILE @$PROMPT_FILE" 2>&1 /
    | tee /dev/stderr) || true

  # Brief pause between iterations
  sleep 2
done
WAKEUP_SH

chmod +x "$RALPH_TASKS_DIR/wake-up.sh"
echo "✅ Created wake-up.sh"

# Create prompt.md (agent instructions)
cat > "$RALPH_TASKS_DIR/prompt.md" << 'PROMPT_MD'
# Ralph Tasks Agent Instructions

## Your Task

You are an autonomous AI coding agent. Each iteration, you implement ONE task from the task queue.

## Execution Sequence

1. **Read Task Queue**
   - Read tasks.json to see all tasks
   - Find the first task with `status: "pending"` (lowest ID first)
   - If a task has `status: "in_progress"`, continue that one instead
   - If no pending/in_progress tasks, output `<no-tasks>` and stop

2. **Mark Task In Progress**
   - Update tasks.json to set the task's status to `"in_progress"`
   - Use jq for atomic updates:
   ```bash
   jq --argjson id TASK_ID '.tasks = [.tasks[] | if .id == $id then .status = "in_progress" else . end]' tasks.json > tmp.json && mv tmp.json tasks.json
   ```

3. **Implement the Task**
   - Read progress.txt for patterns and learnings
   - Implement the task completely
   - Make minimal changes to achieve the goal

4. **Verify Quality**
   - Run typecheck: `pnpm tsc --noEmit` or `npm run typecheck`
   - Run tests: `pnpm test` or `npm test`
   - Run build: `pnpm build` or `npm run build`
   - Fix any issues before proceeding

5. **Commit Changes**
   - Stage changes: `git add .`
   - Commit with format: `feat: [Task ID] - [Description]`
   - Example: `feat: #1 - Add user authentication`

6. **Mark Task Completed**
   - Update tasks.json to set status to `"completed"` and add `completedAt`
   ```bash
   jq --argjson id TASK_ID --arg date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" /
     '.tasks = [.tasks[] | if .id == $id then .status = "completed" | .completedAt = $date else . end]' /
     tasks.json > tmp.json && mv tmp.json tasks.json
   ```

7. **Log Learnings**
   - Append to progress.txt:
   ```
   ## [Date] - Task #[ID]: [Description]
   - What was implemented
   - Files changed
   - **Learnings:**
     - Patterns discovered
     - Gotchas encountered
   ---
   ```

## Stop Condition

If no tasks have `status: "pending"` or `status: "in_progress"`, output:

<no-tasks>

This tells the loop to wait before checking again.

## Critical Rules

- 🛑 NEVER implement more than ONE task per iteration
- 🛑 NEVER skip verification (typecheck/tests/build)
- 🛑 NEVER commit if tests are failing
- ✅ ALWAYS mark task as in_progress before starting
- ✅ ALWAYS mark task as completed after finishing
- ✅ ALWAYS append learnings to progress.txt
- ✅ ALWAYS use jq for JSON updates (atomic operations)
PROMPT_MD

echo "✅ Created prompt.md"

# Create progress.txt template
cat > "$RALPH_TASKS_DIR/progress.txt" << PROGRESS_TXT
# Ralph Tasks Progress Log
Started: $(date +%Y-%m-%d)

## Codebase Patterns
(Add discovered patterns here - Ralph will read these each iteration)

---

PROGRESS_TXT

echo "✅ Created progress.txt"

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║              ✅ RALPH TASKS SETUP COMPLETE                 ║"
echo "╠════════════════════════════════════════════════════════════╣"
echo "║ Created: $RALPH_TASKS_DIR"
echo "╠════════════════════════════════════════════════════════════╣"
echo "║ Next steps:"
echo "║ 1. Add tasks: /ralph-tasks add /"your task description/""
echo "║ 2. List tasks: /ralph-tasks list"
echo "║ 3. Start loop: sh $RALPH_TASKS_DIR/wake-up.sh"
echo "╚════════════════════════════════════════════════════════════╝"
