#!/bin/bash
# Hook script to capture Claude Code current activity
# Handles multiple hook events with clean, color-coded status output

STATE_DIR="/tmp/claude-zellij-status"
ZELLIJ_SESSION="${ZELLIJ_SESSION_NAME:-}"
ZELLIJ_PANE="${ZELLIJ_PANE_ID:-0}"

# Exit if not in Zellij
[ -z "$ZELLIJ_SESSION" ] && exit 0

STATE_FILE="${STATE_DIR}/${ZELLIJ_SESSION}.json"
mkdir -p "$STATE_DIR"

# Read JSON from stdin
INPUT=$(cat)

# Parse hook event and related fields (with error handling)
HOOK_EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // ""' 2>/dev/null || echo "")
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || echo "")
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || echo "unknown")
CWD=$(echo "$INPUT" | jq -r '.cwd // ""' 2>/dev/null || echo "")

# Exit if we couldn't parse the input
[ -z "$HOOK_EVENT" ] && exit 0

# Get short session ID (last 4 chars for compactness)
SHORT_SESSION="${SESSION_ID: -4}"

# Get repo/project name and truncate to 12 chars max
PROJECT_NAME=$(basename "$CWD" 2>/dev/null || echo "?")
if [ ${#PROJECT_NAME} -gt 12 ]; then
    PROJECT_NAME="${PROJECT_NAME:0:6}..."
fi

# =============================================================================
# COLOR SCHEME - ANSI named colors (adapts to terminal theme)
# Override via ~/.config/cc-zjstatus/colors.ini
# Supported formats: ANSI names (red, bright_blue), hex (#ff4136), ANSI 256 (0..255)
# =============================================================================
C_GREEN="green"           # Done/Complete
C_YELLOW="yellow"         # Active/Working
C_BLUE="blue"             # Reading/Searching
C_AQUA="cyan"             # Writing/Editing
C_RED="red"               # Needs attention
C_ORANGE="bright_red"     # Bash commands (closest ANSI to orange)
C_PURPLE="magenta"        # Agent/Skill/MCP
C_GRAY="bright_black"     # Thinking/Idle
C_PROJECT="cyan"          # Project name text

# Load user overrides from INI config (if it exists)
CONFIG_FILE="${HOME}/.config/cc-zjstatus/colors.ini"
if [ -f "$CONFIG_FILE" ]; then
    while IFS='=' read -r key value; do
        key="${key// /}"
        value="${value// /}"
        [[ -z "$key" || "$key" == \#* || "$key" == \;* ]] && continue
        case "$key" in
            green)   C_GREEN="$value"   ;;
            yellow)  C_YELLOW="$value"  ;;
            blue)    C_BLUE="$value"    ;;
            aqua)    C_AQUA="$value"    ;;
            red)     C_RED="$value"     ;;
            orange)  C_ORANGE="$value"  ;;
            purple)  C_PURPLE="$value"  ;;
            gray)    C_GRAY="$value"    ;;
            project) C_PROJECT="$value" ;;
        esac
    done < "$CONFIG_FILE"
fi

# =============================================================================
# SYMBOLS
# =============================================================================
# Determine activity, color, and symbol based on hook event
case "$HOOK_EVENT" in
    PreToolUse)
        case "$TOOL_NAME" in
            WebSearch)       ACTIVITY="search"; COLOR="$C_BLUE";   SYMBOL="◍" ;;
            WebFetch)        ACTIVITY="fetch";  COLOR="$C_BLUE";   SYMBOL="↓" ;;
            Task)            ACTIVITY="agent";  COLOR="$C_PURPLE"; SYMBOL="▶" ;;
            Bash)            ACTIVITY="bash";   COLOR="$C_ORANGE"; SYMBOL="⚡" ;;
            Read)            ACTIVITY="read";   COLOR="$C_BLUE";   SYMBOL="◔" ;;
            Write)           ACTIVITY="write";  COLOR="$C_AQUA";   SYMBOL="✎" ;;
            Edit)            ACTIVITY="edit";   COLOR="$C_AQUA";   SYMBOL="✎" ;;
            Glob|Grep)       ACTIVITY="find";   COLOR="$C_BLUE";   SYMBOL="◎" ;;
            Skill)           ACTIVITY="skill";  COLOR="$C_PURPLE"; SYMBOL="★" ;;
            TodoWrite)       ACTIVITY="plan";   COLOR="$C_YELLOW"; SYMBOL="◫" ;;
            AskUserQuestion) ACTIVITY="ask?";   COLOR="$C_RED";    SYMBOL="?" ;;
            mcp__*)          ACTIVITY="mcp";    COLOR="$C_PURPLE"; SYMBOL="◈" ;;
            *)               ACTIVITY="work";   COLOR="$C_YELLOW"; SYMBOL="●" ;;
        esac
        DONE=false
        ;;
    PostToolUse)
        ACTIVITY="think"; COLOR="$C_GRAY"; SYMBOL="◐"; DONE=false ;;
    Notification)
        # Check if session is already done - don't overwrite completion status
        if [ -f "$STATE_FILE" ]; then
            EXISTING_DONE=$(jq -r --arg pane "$ZELLIJ_PANE" '.[$pane].done // false' "$STATE_FILE" 2>/dev/null || echo "false")
            if [ "$EXISTING_DONE" = "true" ]; then
                # Still send zjstatus notification, but preserve done status
                PROJECT_NAME_NOTIFY=$(basename "$CWD" 2>/dev/null || echo "?")
                zellij -s "$ZELLIJ_SESSION" pipe "zjstatus::notify::${PROJECT_NAME_NOTIFY} ! notification" 2>/dev/null || true
                exit 0
            fi
        fi
        ACTIVITY="!"; COLOR="$C_RED"; SYMBOL="!"; DONE=false ;;
    UserPromptSubmit)
        ACTIVITY="start"; COLOR="$C_YELLOW"; SYMBOL="●"; DONE=false ;;
    PermissionRequest)
        ACTIVITY="perm?"; COLOR="$C_RED"; SYMBOL="⚠"; DONE=false ;;
    Stop)
        ACTIVITY="done"; COLOR="$C_GREEN"; SYMBOL="✓"; DONE=true ;;
    SubagentStop)
        ACTIVITY="agent✓"; COLOR="$C_GREEN"; SYMBOL="▷"; DONE=false ;;
    SessionStart)
        ACTIVITY="init"; COLOR="$C_BLUE"; SYMBOL="◆"; DONE=false ;;
    SessionEnd)
        # Session ended - remove from state
        if [ -f "$STATE_FILE" ]; then
            TMP_FILE=$(mktemp)
            jq --arg pane "$ZELLIJ_PANE" 'del(.[$pane])' "$STATE_FILE" > "$TMP_FILE" 2>/dev/null && mv "$TMP_FILE" "$STATE_FILE"
            rm -f "$TMP_FILE"
        fi
        # Update zjstatus with remaining sessions
        if [ -f "$STATE_FILE" ] && [ -s "$STATE_FILE" ]; then
            SESSIONS=""
            while IFS= read -r line; do
                [ -z "$line" ] && continue
                [ -n "$SESSIONS" ] && SESSIONS="${SESSIONS}  "
                SESSIONS="${SESSIONS}${line}"
            done < <(jq -r --arg proj_color "$C_PROJECT" '
                to_entries | sort_by(.key)[] |
                "#[fg=\(.value.color)]\(.value.symbol) #[fg=\($proj_color)]\(.value.project)" +
                (if .value.context_pct then " #[fg=\(.value.ctx_color // "green")]\(.value.context_pct)%" else "" end)
            ' "$STATE_FILE" 2>/dev/null)

            if [ -z "$SESSIONS" ]; then
                zellij -s "$ZELLIJ_SESSION" pipe "zjstatus::pipe::pipe_status::" 2>/dev/null || true
            else
                zellij -s "$ZELLIJ_SESSION" pipe "zjstatus::pipe::pipe_status::${SESSIONS}" 2>/dev/null || true
            fi
        fi
        exit 0
        ;;
    *)
        ACTIVITY="..."; COLOR="$C_GRAY"; SYMBOL="○"; DONE=false ;;
esac

# Current time
TIMESTAMP=$(date +%s)
TIME_FMT=$(date +%H:%M)

# Initialize state file if it doesn't exist or is empty
if [ ! -f "$STATE_FILE" ] || [ ! -s "$STATE_FILE" ]; then
    echo "{}" > "$STATE_FILE"
fi

# Read existing state
CURRENT_STATE=$(cat "$STATE_FILE" 2>/dev/null || echo "{}")

# Validate it's proper JSON
if ! echo "$CURRENT_STATE" | jq empty 2>/dev/null; then
    CURRENT_STATE="{}"
    echo "{}" > "$STATE_FILE"
fi

# Get existing values for this pane (preserve context data from status line script)
EXISTING=$(echo "$CURRENT_STATE" | jq -r --arg pane "$ZELLIJ_PANE" '.[$pane] // {}' 2>/dev/null)
EXISTING_CTX_PCT=$(echo "$EXISTING" | jq -r '.context_pct // null' 2>/dev/null)
EXISTING_CTX_COLOR=$(echo "$EXISTING" | jq -r '.ctx_color // null' 2>/dev/null)

# Update state with this pane's activity (preserving context from status line)
TMP_FILE=$(mktemp)
echo "$CURRENT_STATE" | jq \
    --arg pane "$ZELLIJ_PANE" \
    --arg project "$PROJECT_NAME" \
    --arg activity "$ACTIVITY" \
    --arg color "$COLOR" \
    --arg symbol "$SYMBOL" \
    --arg time "$TIME_FMT" \
    --arg ts "$TIMESTAMP" \
    --arg short_session "$SHORT_SESSION" \
    --arg session "$SESSION_ID" \
    --arg ctx_pct "$EXISTING_CTX_PCT" \
    --arg ctx_color "$EXISTING_CTX_COLOR" \
    --argjson done "$DONE" \
    '.[$pane] = {
        project: $project,
        activity: $activity,
        color: $color,
        symbol: $symbol,
        time: $time,
        timestamp: ($ts | tonumber),
        short_session: $short_session,
        session_id: $session,
        context_pct: (if $ctx_pct == "null" then null else $ctx_pct end),
        ctx_color: (if $ctx_color == "null" then null else $ctx_color end),
        done: $done
    }' > "$TMP_FILE" 2>/dev/null

if [ -s "$TMP_FILE" ]; then
    mv "$TMP_FILE" "$STATE_FILE"
else
    rm -f "$TMP_FILE"
fi

# Build combined status string
# Format: symbol project XX%  symbol project XX%
SESSIONS=""
while IFS= read -r line; do
    [ -z "$line" ] && continue
    [ -n "$SESSIONS" ] && SESSIONS="${SESSIONS}  "
    SESSIONS="${SESSIONS}${line}"
done < <(jq -r --arg proj_color "$C_PROJECT" '
    to_entries | sort_by(.key)[] |
    "#[fg=\(.value.color)]\(.value.symbol) #[fg=\($proj_color)]\(.value.project)" +
    (if .value.context_pct then " #[fg=\(.value.ctx_color // "green")]\(.value.context_pct)%" else "" end)
' "$STATE_FILE" 2>/dev/null)

# Build combined status
if [ -n "$SESSIONS" ]; then
    zellij -s "$ZELLIJ_SESSION" pipe "zjstatus::pipe::pipe_status::${SESSIONS}" 2>/dev/null || true
fi

# Send zjstatus notification for important events
case "$HOOK_EVENT" in
    Notification|Stop|SubagentStop|AskUserQuestion|PermissionRequest)
        zellij -s "$ZELLIJ_SESSION" pipe "zjstatus::notify::${PROJECT_NAME} ${SYMBOL} ${ACTIVITY}" 2>/dev/null || true
        ;;
esac
