#!/bin/bash
# Claude Code Status Line script for Zellij + zjstatus integration
# Combines activity status + context usage in single pipe output

STATE_DIR="/tmp/claude-zellij-status"
STALE_THRESHOLD=120  # seconds before removing stale entries

ZELLIJ_SESSION="${ZELLIJ_SESSION_NAME:-}"
ZELLIJ_PANE="${ZELLIJ_PANE_ID:-0}"

# Exit silently if not in Zellij
if [ -z "$ZELLIJ_SESSION" ]; then
    echo "Claude"
    exit 0
fi

STATE_FILE="${STATE_DIR}/${ZELLIJ_SESSION}.json"
mkdir -p "$STATE_DIR"

# Read JSON from stdin (Claude Code status data)
INPUT=$(cat)

# Parse relevant fields
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || echo "unknown")
MODEL=$(echo "$INPUT" | jq -r '.model.display_name // "Claude"' 2>/dev/null || echo "Claude")
CWD=$(echo "$INPUT" | jq -r '.cwd // ""' 2>/dev/null || echo "")

# Context window data
INPUT_TOKENS=$(echo "$INPUT" | jq -r '.context_window.current_usage.input_tokens // 0' 2>/dev/null || echo "0")
OUTPUT_TOKENS=$(echo "$INPUT" | jq -r '.context_window.current_usage.output_tokens // 0' 2>/dev/null || echo "0")
CONTEXT_SIZE=$(echo "$INPUT" | jq -r '.context_window.context_window_size // 200000' 2>/dev/null || echo "200000")

# Calculate context usage percentage
TOTAL_TOKENS=$((INPUT_TOKENS + OUTPUT_TOKENS))
if [ "$CONTEXT_SIZE" -gt 0 ]; then
    CONTEXT_PCT=$((TOTAL_TOKENS * 100 / CONTEXT_SIZE))
else
    CONTEXT_PCT=0
fi

# Get short session ID and project name
SHORT_SESSION="${SESSION_ID: -4}"
PROJECT_NAME=$(basename "$CWD" 2>/dev/null || echo "?")
if [ ${#PROJECT_NAME} -gt 10 ]; then
    PROJECT_NAME="${PROJECT_NAME:0:9}~"
fi

TIMESTAMP=$(date +%s)
TIME_FMT=$(date +%H:%M)

# Colors (clrs.cc)
C_GRAY="#777777"
C_TEXT="#7fdbff"
C_GREEN="#2ecc40"
C_YELLOW="#ffdc00"
C_RED="#ff4136"

# Initialize state file if needed
if [ ! -f "$STATE_FILE" ] || [ ! -s "$STATE_FILE" ]; then
    echo "{}" > "$STATE_FILE"
fi

# Read existing state
CURRENT_STATE=$(cat "$STATE_FILE" 2>/dev/null || echo "{}")

# Validate JSON
if ! echo "$CURRENT_STATE" | jq empty 2>/dev/null; then
    CURRENT_STATE="{}"
fi

# Get existing values for this pane (preserve activity hook data)
EXISTING=$(echo "$CURRENT_STATE" | jq -r --arg pane "$ZELLIJ_PANE" '.[$pane] // {}' 2>/dev/null)
EXISTING_ACTIVITY=$(echo "$EXISTING" | jq -r '.activity // "idle"' 2>/dev/null || echo "idle")
EXISTING_COLOR=$(echo "$EXISTING" | jq -r '.color // ""' 2>/dev/null || echo "")
EXISTING_SYMBOL=$(echo "$EXISTING" | jq -r '.symbol // "○"' 2>/dev/null || echo "○")
EXISTING_DONE=$(echo "$EXISTING" | jq -r '.done // false' 2>/dev/null || echo "false")

# Use defaults if not set
[ -z "$EXISTING_COLOR" ] || [ "$EXISTING_COLOR" = "null" ] && EXISTING_COLOR="$C_GRAY"
[ -z "$EXISTING_SYMBOL" ] || [ "$EXISTING_SYMBOL" = "null" ] && EXISTING_SYMBOL="○"
[ "$EXISTING_ACTIVITY" = "null" ] && EXISTING_ACTIVITY="idle"
[ "$EXISTING_DONE" = "null" ] && EXISTING_DONE="false"

# Determine context color based on usage
if [ "$CONTEXT_PCT" -ge 80 ]; then
    CTX_COLOR="$C_RED"
elif [ "$CONTEXT_PCT" -ge 50 ]; then
    CTX_COLOR="$C_YELLOW"
else
    CTX_COLOR="$C_GREEN"
fi

# Update state with activity + context data
TMP_FILE=$(mktemp)
echo "$CURRENT_STATE" | jq \
    --arg pane "$ZELLIJ_PANE" \
    --arg project "$PROJECT_NAME" \
    --arg activity "$EXISTING_ACTIVITY" \
    --arg color "$EXISTING_COLOR" \
    --arg symbol "$EXISTING_SYMBOL" \
    --arg ctx_color "$CTX_COLOR" \
    --arg time "$TIME_FMT" \
    --arg ts "$TIMESTAMP" \
    --arg short_session "$SHORT_SESSION" \
    --arg session "$SESSION_ID" \
    --arg ctx_pct "$CONTEXT_PCT" \
    --argjson done "$EXISTING_DONE" \
    '.[$pane] = {
        project: $project,
        activity: $activity,
        color: $color,
        symbol: $symbol,
        ctx_color: $ctx_color,
        time: $time,
        timestamp: ($ts | tonumber),
        short_session: $short_session,
        session_id: $session,
        context_pct: $ctx_pct,
        done: $done
    }' > "$TMP_FILE" 2>/dev/null

if [ -s "$TMP_FILE" ]; then
    # Remove stale entries
    CUTOFF=$((TIMESTAMP - STALE_THRESHOLD))
    jq --arg cutoff "$CUTOFF" \
        'to_entries | map(select(.value.timestamp > ($cutoff | tonumber))) | from_entries' \
        "$TMP_FILE" > "$STATE_FILE" 2>/dev/null
fi
rm -f "$TMP_FILE"

# Build combined status string
# Format: symbol project XX%  symbol project XX%
SESSIONS=""
while IFS= read -r line; do
    [ -z "$line" ] && continue
    [ -n "$SESSIONS" ] && SESSIONS="${SESSIONS}  "
    SESSIONS="${SESSIONS}${line}"
done < <(jq -r '
    to_entries | sort_by(.key)[] |
    "#[fg=\(.value.color)]\(.value.symbol) #[fg=#7fdbff]\(.value.project) #[fg=\(.value.ctx_color)]\(.value.context_pct)%"
' "$STATE_FILE" 2>/dev/null)

# Build combined status
if [ -n "$SESSIONS" ]; then
    COMBINED="${SESSIONS}"
    zellij -s "$ZELLIJ_SESSION" pipe "zjstatus::pipe::pipe_status::${COMBINED}" 2>/dev/null || true
fi

# Output status line for Claude Code terminal display
echo "${MODEL} ${CONTEXT_PCT}%"
