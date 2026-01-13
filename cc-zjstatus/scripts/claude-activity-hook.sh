#!/bin/bash
# Hook script to capture Claude Code current activity
# Aggregates status from all panes and sends to zjstatus pipe

STATE_DIR="/tmp/claude-zellij-status"
ZELLIJ_SESSION="${ZELLIJ_SESSION_NAME:-}"
ZELLIJ_PANE="${ZELLIJ_PANE_ID:-0}"

# Exit if not in Zellij
[ -z "$ZELLIJ_SESSION" ] && exit 0

STATE_FILE="${STATE_DIR}/${ZELLIJ_SESSION}.json"
mkdir -p "$STATE_DIR"

# Read JSON from stdin
INPUT=$(cat)

# Parse hook event and related fields
HOOK_EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // ""' 2>/dev/null || echo "")
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || echo "")
CWD=$(echo "$INPUT" | jq -r '.cwd // ""' 2>/dev/null || echo "")

# Exit if we couldn't parse the input
[ -z "$HOOK_EVENT" ] && exit 0

# Get repo/project name and truncate to 12 chars max
PROJECT_NAME=$(basename "$CWD" 2>/dev/null || echo "?")
if [ ${#PROJECT_NAME} -gt 12 ]; then
    PROJECT_NAME="${PROJECT_NAME:0:9}..."
fi

# =============================================================================
# COLOR SCHEME (clrs.cc)
# =============================================================================
C_GREEN="#2ecc40"
C_YELLOW="#ffdc00"
C_BLUE="#0074d9"
C_AQUA="#7fdbff"
C_RED="#ff4136"
C_ORANGE="#ff851b"
C_PURPLE="#b10dc9"
C_GRAY="#666666"

# =============================================================================
# Determine activity, color, and symbol based on hook event
# =============================================================================
case "$HOOK_EVENT" in
    PreToolUse)
        case "$TOOL_NAME" in
            WebSearch)       COLOR="$C_BLUE";   SYMBOL="◍" ;;
            WebFetch)        COLOR="$C_BLUE";   SYMBOL="↓" ;;
            Task)            COLOR="$C_PURPLE"; SYMBOL="▶" ;;
            Bash)            COLOR="$C_ORANGE"; SYMBOL="⚡" ;;
            Read)            COLOR="$C_BLUE";   SYMBOL="◔" ;;
            Write|Edit)      COLOR="$C_AQUA";   SYMBOL="✎" ;;
            Glob|Grep)       COLOR="$C_BLUE";   SYMBOL="◎" ;;
            Skill)           COLOR="$C_PURPLE"; SYMBOL="★" ;;
            TodoWrite)       COLOR="$C_YELLOW"; SYMBOL="◫" ;;
            AskUserQuestion) COLOR="$C_RED";    SYMBOL="?" ;;
            mcp__*)          COLOR="$C_PURPLE"; SYMBOL="◈" ;;
            *)               COLOR="$C_YELLOW"; SYMBOL="●" ;;
        esac
        ;;
    PostToolUse)
        COLOR="$C_GRAY"; SYMBOL="◐" ;;
    Notification)
        COLOR="$C_RED"; SYMBOL="!" ;;
    UserPromptSubmit)
        COLOR="$C_YELLOW"; SYMBOL="●" ;;
    PermissionRequest)
        COLOR="$C_RED"; SYMBOL="⚠" ;;
    Stop)
        COLOR="$C_GREEN"; SYMBOL="✓" ;;
    SubagentStop)
        COLOR="$C_GREEN"; SYMBOL="▷" ;;
    SessionStart)
        COLOR="$C_BLUE"; SYMBOL="◆" ;;
    SessionEnd)
        # Remove this pane from state
        if [ -f "$STATE_FILE" ]; then
            TMP_FILE=$(mktemp)
            jq --arg pane "$ZELLIJ_PANE" 'del(.[$pane])' "$STATE_FILE" > "$TMP_FILE" 2>/dev/null && mv "$TMP_FILE" "$STATE_FILE"
            rm -f "$TMP_FILE"
        fi
        # Update zjstatus with remaining sessions
        if [ -f "$STATE_FILE" ] && [ -s "$STATE_FILE" ]; then
            SESSIONS=$(jq -r 'to_entries | sort_by(.key)[] | "#[fg=\(.value.color)]\(.value.symbol) #[fg=#7fdbff]\(.value.project)"' "$STATE_FILE" 2>/dev/null | tr '\n' ' ' | sed 's/  */ /g')
            zellij -s "$ZELLIJ_SESSION" pipe "zjstatus::pipe::pipe_status::${SESSIONS}" 2>/dev/null || true
        else
            zellij -s "$ZELLIJ_SESSION" pipe "zjstatus::pipe::pipe_status::" 2>/dev/null || true
        fi
        exit 0
        ;;
    *)
        COLOR="$C_GRAY"; SYMBOL="○" ;;
esac

# Current timestamp for cleanup
TIMESTAMP=$(date +%s)

# Initialize state file if needed
if [ ! -f "$STATE_FILE" ] || [ ! -s "$STATE_FILE" ]; then
    echo "{}" > "$STATE_FILE"
fi

# Read and validate current state
CURRENT_STATE=$(cat "$STATE_FILE" 2>/dev/null || echo "{}")
if ! echo "$CURRENT_STATE" | jq empty 2>/dev/null; then
    CURRENT_STATE="{}"
    echo "{}" > "$STATE_FILE"
fi

# Update state with this pane's activity
TMP_FILE=$(mktemp)
echo "$CURRENT_STATE" | jq \
    --arg pane "$ZELLIJ_PANE" \
    --arg project "$PROJECT_NAME" \
    --arg color "$COLOR" \
    --arg symbol "$SYMBOL" \
    --arg ts "$TIMESTAMP" \
    '.[$pane] = {
        project: $project,
        color: $color,
        symbol: $symbol,
        timestamp: ($ts | tonumber)
    }' > "$TMP_FILE" 2>/dev/null

if [ -s "$TMP_FILE" ]; then
    mv "$TMP_FILE" "$STATE_FILE"
else
    rm -f "$TMP_FILE"
fi

# Clean up stale entries (older than 2 minutes)
TMP_FILE=$(mktemp)
jq --arg now "$TIMESTAMP" 'with_entries(select((.value.timestamp // 0) > ($now | tonumber) - 120))' "$STATE_FILE" > "$TMP_FILE" 2>/dev/null && mv "$TMP_FILE" "$STATE_FILE"
rm -f "$TMP_FILE"

# Build combined status: symbol project  symbol project
SESSIONS=$(jq -r 'to_entries | sort_by(.key)[] | "#[fg=\(.value.color)]\(.value.symbol) #[fg=#7fdbff]\(.value.project)"' "$STATE_FILE" 2>/dev/null | tr '\n' ' ' | sed 's/  */ /g')

# Send to zjstatus
if [ -n "$SESSIONS" ]; then
    zellij -s "$ZELLIJ_SESSION" pipe "zjstatus::pipe::pipe_status::${SESSIONS}" 2>/dev/null || true
fi

# Send notification for important events
case "$HOOK_EVENT" in
    Notification|Stop|SubagentStop|AskUserQuestion|PermissionRequest)
        zellij -s "$ZELLIJ_SESSION" pipe "zjstatus::notify::${PROJECT_NAME} ${SYMBOL}" 2>/dev/null || true
        ;;
esac
