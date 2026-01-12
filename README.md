# Claude Code Zellij Status

Monitor Claude Code activity across multiple Zellij panes in real-time via zjstatus.

## Preview

![Claude Code Zellij Status Demo](claude_status.gif)

## Installation

### Requirements

- [Zellij](https://zellij.dev/documentation/installation.html) terminal multiplexer
- [zjstatus](https://github.com/dj95/zjstatus/wiki/1-%E2%80%90-Installation) plugin
- [Claude Code](https://claude.ai/code) CLI

### Step 1: Install the Plugin

```bash
claude add marketplace https://github.com/thoo/claude-code-zellij-status.git
claude install plugin
```

### Step 2: Configure Zellij Layout

Copy the `default.kdl` file to your Zellij layouts directory:

```bash
cp default.kdl $HOME/.config/zellij/layouts/default.kdl
```

For more information on zjstatus configuration, see the [zjstatus Installation Guide](https://github.com/dj95/zjstatus/wiki/1-%E2%80%90-Installation).

### Step 3: Restart Zellij

Restart your Zellij session or open a new tab to apply the layout changes.

## Features

- Real-time activity monitoring across all Claude Code sessions in a Zellij session
- Color-coded symbols for instant recognition
- Automatic cleanup when sessions end
- zjstatus notifications for important events (done, asking, permission needed)

## Symbol Reference

| Symbol | Color | Hex | Meaning |
|--------|-------|-----|---------|
| `●` | Yellow | `#ffdc00` | Working/Active |
| `◐` | Gray | `#666666` | Thinking |
| `◍` | Blue | `#0074d9` | Web searching |
| `↓` | Blue | `#0074d9` | Web fetching |
| `◔` | Blue | `#0074d9` | Reading file |
| `◎` | Blue | `#0074d9` | Finding (glob/grep) |
| `✎` | Aqua | `#4166F5` | Writing/Editing |
| `⚡` | Orange | `#ff851b` | Running bash |
| `▶` | Purple | `#b10dc9` | Agent running |
| `▷` | Green | `#2ecc40` | Agent done |
| `★` | Purple | `#b10dc9` | Skill |
| `◈` | Purple | `#b10dc9` | MCP tool |
| `◫` | Yellow | `#ffdc00` | Planning (todo) |
| `?` | Red | `#ff4136` | Asking user |
| `⚠` | Red | `#ff4136` | Permission needed |
| `!` | Red | `#ff4136` | Notification |
| `✓` | Green | `#2ecc40` | Done |
| `◆` | Blue | `#0074d9` | Session started |
| `○` | Gray | `#666666` | Idle |

## Color Scheme (clrs.cc)

| Color | Hex | Usage |
|-------|-----|-------|
| Green | `#2ecc40` | Complete/Done |
| Yellow | `#ffdc00` | Active/Working |
| Blue | `#0074d9` | Reading/Searching |
| Aqua | `#4166F5` | Project name text, Writing |
| Red | `#ff4136` | Needs attention |
| Orange | `#ff851b` | Bash commands |
| Purple | `#b10dc9` | Agent/Skill/MCP |
| Gray | `#666666` | Thinking/Idle |



## How It Works

```mermaid
<<<<<<< HEAD
flowchart TB
    subgraph "Claude Code"
        CC[Claude Code CLI]
        HookEvents[Hook Events<br/>PreToolUse, PostToolUse,<br/>Stop, Notification, etc.]
    end

    subgraph "Hook Script"
        ActivityHook[claude-activity-hook.sh<br/>Maps events → activity/color/symbol]
    end

    subgraph "Shared State"
        StateFile["/tmp/claude-zellij-status/<br/>{session}.json"]
    end

    subgraph "Zellij + zjstatus"
        ZellijPipe[zellij pipe]
        StatusBar[Status Bar Display<br/>symbol project]
    end

    CC -->|"stdin JSON"| HookEvents
    HookEvents -->|"hook_event_name<br/>tool_name"| ActivityHook
    ActivityHook -->|"Write state"| StateFile
    ActivityHook -->|"pipe command"| ZellijPipe
    ZellijPipe --> StatusBar
=======
flowchart LR
    subgraph panes [Claude Code Panes]
        CC1[◔ api-server]
        CC2[✓ frontend]
        CC3[? pipeline]
    end

    subgraph hooks [Hook Events]
        direction TB
        E1[PreToolUse]
        E2[PostToolUse]
        E3[Stop]
        E4[Notification]
        E5[PermissionRequest]
    end

    subgraph processing [Processing]
        AH[[claude-activity-hook.sh]]
        SF[(session.json)]
    end

    subgraph output [Status Bar]
        ZJ[zjstatus<br/>◔ api-server  ✓ frontend  ? pipeline]
    end

    CC1 & CC2 & CC3 --> hooks
    hooks --> AH
    AH <--> SF
    AH -->|zellij pipe| ZJ

    style CC1 fill:#0074d9,color:#fff
    style CC2 fill:#2ecc40,color:#fff
    style CC3 fill:#ff4136,color:#fff
    style ZJ fill:#1a1a2e,color:#4166F5
    style AH fill:#333,color:#fff
    style SF fill:#333,color:#ffdc00
>>>>>>> origin/main
```

### Data Flow

1. **Claude Code** emits hook events (PreToolUse, PostToolUse, Stop, etc.) as JSON via stdin
2. **Hook script** parses the event and maps it to an activity, color, and symbol
3. **State file** stores status for all Claude Code panes in the Zellij session
4. **zjstatus** receives pipe message and displays combined status in the status bar

## Files

- `claude-activity-hook.sh` - Hook script that captures Claude Code events and updates zjstatus
- State files stored in `/tmp/claude-zellij-status/`

## License

MIT
