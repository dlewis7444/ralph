# ralph

A single-file bash loop for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Fresh context window every iteration. State lives on disk, not in the conversation.

## Why

I tried existing loops. The official plugin from Anthropic crapped out after 2 iterations. Frank's quit after 1. So I (and Claude) wrote my own.

## How It Works

Ralph runs Claude Code in non-interactive mode (`claude -p`), one iteration at a time, inside a tmux session. Each iteration gets a clean context window — no accumulated baggage from prior passes. Claude reads its task state from disk (a markdown checklist, a config file, whatever you point it at), does one unit of work, persists progress, and exits. Ralph checks for a completion tag in the output and either loops again or declares victory.

The bottom pane is a live status bar: session name, model, iteration count, wall time, and failure tracking. No separate monitoring tool needed.

```
▶ ralph-a1b2 │ sonnet │ iter 7/50 │ ✔ 6 done │ ⏱ 12m34s │ this iter: 1m22s, 8/30t
Ctrl-b d detach │ Ctrl-b ↑↓ switch pane │ Ctrl-b [ scroll │ ralph --attach / --list / --kill
```

## Requirements

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) (`claude`)
- `tmux`
- `jq`
- `xxd` (usually bundled with `vim`; used for session name generation)

```bash
# apt
sudo apt install tmux jq xxd

# dnf (xxd ships in vim-common)
sudo dnf install tmux jq vim-common
```

## Install

```bash
# Clone and symlink (or just drop the script on your PATH)
git clone https://github.com/dlewis7444/ralph.git
ln -s "$(pwd)/ralph/ralph" ~/.local/bin/ralph
chmod +x ~/.local/bin/ralph
```

Or just copy the `ralph` file anywhere on your `$PATH`. It's one file.

## Usage

```
ralph -p PROMPT [OPTIONS]
ralph --attach [SESSION]
ralph --list
ralph --kill [SESSION]
```

### Required

| Flag | Description |
|------|-------------|
| `-p`, `--prompt` | The task prompt. Include your own completion criteria — ralph appends loop controller instructions automatically. |

### Options

| Flag | Default | Description |
|------|---------|-------------|
| `-i`, `--max-iterations` | `50` | Max loop iterations before ralph gives up. |
| `-m`, `--max-turns` | `50` | Max turns (tool calls) per iteration. |
| `--model` | `sonnet` | Claude model to use (passed to `claude --model`). |
| `-s`, `--session` | `ralph-XXXX` | tmux session name. Auto-generated if omitted. |
| `-l`, `--log-dir` | *(none)* | Directory for per-iteration log files. |
| `-v`, `--verbose` | on | Pass `--verbose` to claude. |
| `--dry-run` | | Analyze the prompt with haiku and exit — no loop is started. |

### Session Management

| Flag | Description |
|------|-------------|
| `-a`, `--attach` | Reattach to a running session. Targets the latest if no name given. |
| `--list` | List all active ralph sessions. |
| `--kill` | Kill a session. Targets the latest if no name given. |

## Examples

### Grind a task list

The bread and butter. Point ralph at a markdown checklist and let it work through items one at a time:

```bash
ralph -i 50 -p "Read the task list at ./tasks.md. Find the first item still
marked [ ] (unchecked). Implement it fully per the spec in that file, write
all specified tests, and commit on an appropriately named feature branch.
Then edit the task file to check the box [x] and add a brief status note
(date, branch name, test count, work desc.). Do NOT implement more than one
item per iteration — only the first unchecked one. After checking the box,
re-read the full task list. Only if no more unchecked boxes remain do you
output the completion promise."
```

### Use a specific model

```bash
ralph -p "Fix all type errors in src/" --model opus -i 20
```

### Run with logging

```bash
ralph -p "Refactor the auth module" -l ./logs --model haiku
```

### Dry run

Preview what ralph will do before committing to a full loop. Sends the complete prompt — including the injected loop controller instructions — to haiku for a quick coherency review:

```bash
ralph -p "Read tasks.md, implement first unchecked item, check box. Done = all boxes checked." --dry-run
```

Haiku reports on: whether the completion criteria are clear and disk-verifiable, what the agent will likely do each iteration, and whether the prompt fits the one-task-per-iteration mechanic. No tmux session is created; ralph exits after the analysis.

Ralph also runs a silent preflight check on every normal launch. If haiku flags a critical issue (missing or unverifiable completion criteria), it surfaces the finding and asks `[y/N]` before starting the loop. If nothing is wrong, it stays silent.

### Session management

```bash
ralph --list                # see what's running
ralph --attach              # reattach to latest session
ralph --attach ralph-a1b2   # reattach to specific session
ralph --kill                # kill latest session
ralph --kill ralph-a1b2     # kill specific session
```

## Completion Protocol

Ralph appends loop controller instructions to your prompt automatically. You don't need to worry about the mechanics — just define **what "done" means** in your prompt. Ralph tells Claude to output a specific XML tag (`<promise>RALPH_LOOP_COMPLETE</promise>`) when your criteria are met.

The injected instructions tell Claude to:

1. Do **one unit of work** per iteration.
2. **Persist all progress to disk** (commits, file edits, checked boxes).
3. Evaluate whether all work is finished after each unit.
4. Output the completion tag **only** when everything is genuinely done.

If Claude outputs the tag, ralph stops and shows a summary. If not, it loops.

### Circuit Breaker

Three consecutive non-zero exit codes from Claude and ralph trips the circuit breaker — stops the loop and drops you into a shell so you can investigate. This prevents burning iterations on a broken environment.

## Tips

- **Fresh context is the point.** Each iteration starts clean. Design your prompts so Claude reads state from disk, not from memory.
- **One task per iteration.** Don't ask Claude to do five things. Ask it to find the *next* thing and do that.
- **Be explicit about completion.** "All boxes checked" is unambiguous. "Everything looks good" is not.
- **Logs are cheap.** Use `--log-dir` so you can audit what happened if something goes sideways.
- **Detach, don't stare.** `Ctrl-b d` to detach. Go do something else. Reattach with `ralph --attach`.
- **Avoid nested tmux.** Launching ralph from inside an existing tmux session creates nested tmux — `Ctrl-b` is captured by the outer session and you'll need `Ctrl-b b` to reach ralph's inner session. Ralph will warn you and ask for confirmation if it detects this. Run ralph from a plain terminal to avoid the hassle.

## License

MIT
