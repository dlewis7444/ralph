# ralph

A single-file bash loop for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) or the Grok CLI. Fresh context window every iteration. State lives on disk, not in the conversation. Claude is the default, so existing `ralph -p …` invocations do not change. `ralph --harness grok` uses `grok`.

## Why

I tried existing loops. The official plugin from Anthropic crapped out after 2 iterations. Frank's quit after 1. So I (and Claude) wrote my own.

## How It Works

Ralph runs the agent in non-interactive mode (`claude -p` or `grok -p`), one iteration at a time, inside a tmux session. Each iteration gets a clean context window — no accumulated baggage from prior passes. The agent reads its task state from disk (a markdown checklist, a config file, whatever you point it at), does one unit of work, persists progress, and exits. Ralph checks for a completion tag in the output and either loops again or declares victory.

The bottom pane is a live status bar: session name, harness, model, iteration count, wall time, and failure tracking. No separate monitoring tool needed.

```
▶ ralph-a1b2 │ claude │ sonnet │ iter 7/50 │ ✔ 6 done │ ⏱ 12m34s │ this iter: 1m22s, 8/30t
Ctrl-b d detach │ Ctrl-b ↑↓ switch pane │ Ctrl-b [ scroll │ ralph --attach / --list / --kill
```

With `ralph --harness grok` and no `--model`, the model field is `default` (Grok's own default). A passed `--model` is shown as given.

## Requirements

- `claude` ([Claude Code](https://docs.anthropic.com/en/docs/claude-code)) or `grok` (Grok CLI) — whichever harness you select. Default is `claude`.
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
| `-m`, `--max-turns` | `100` | Max turns (tool calls) per iteration. |
| `--harness` | `claude` | `claude` or `grok`. `RALPH_HARNESS` is the default when the flag is absent. |
| `--model` | see below | Work-loop model. Claude passes `sonnet` when this is omitted. Grok omits `--model` unless you pass one. |
| `--chk-model` | see below | Model for preflight, dry-run, and the no-prompt advice. Claude passes `haiku` when this is omitted. Grok omits `--model` unless you pass one. |
| `--permission-mode` | | Forwarded to the selected binary on the work loop only. For Grok, this replaces `--always-approve`. |
| `--no-always-approve` | | Grok only. Work loop does not pass `--always-approve`. Refusals still exit 0, so the breaker will not fire. |
| `-s`, `--session` | `ralph-XXXX` | tmux session name. Auto-generated if omitted. |
| `-l`, `--log-dir` | *(none)* | Directory for per-iteration log files. |
| `-v`, `--verbose` | on for claude | Accepted for both harnesses. Passes `--verbose` to `claude` only. Not an error on Grok; `grok` does not receive it (`-v` is `--version` there). |
| `--dry-run` | | Analyze the prompt with the check model and exit — no loop is started. |
| `--no-preflight` | | Skip the preflight prompt check (not recommended). |

### Harness contract

Analyst calls are the no-prompt advice, `--dry-run`, preflight, and suggestion prompts. The work loop is the iteration that does the task.

| | Claude (default) | Grok (`--harness grok`) |
|---|---|---|
| Binary | `claude` | `grok` |
| Work prompt | `-p` | `-p` |
| Work stream | `--output-format stream-json --verbose` | `--output-format streaming-messages-json` |
| Analyst output | `--output-format text` | `--output-format plain` |
| Model flag | `--model sonnet` unless `--model` was passed | omit `--model` unless `--model` was passed |
| Check model | `haiku` unless `--chk-model` was passed | omit `--model` unless `--chk-model` was passed |
| Permissions on the work loop | unchanged: no extra flag | `--always-approve`, unless `--permission-mode` or `--no-always-approve` |
| Permissions on analyst calls | unchanged | no `--always-approve` (reads run; edits and shell are refused) |

Ralph does not pass Grok's native `streaming-json`, `--include-partial-messages`, or `--verbose`. Work-loop stdout is scanned for the completion tag. Stderr is printed on the pane and is not scanned. A startup `type: error` object is printed in red. A `type: result` with `is_error` or an `error_*` subtype (max turns, execution errors) is printed in red and not as iteration complete.

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

### Run the same loop on Grok

```bash
ralph --harness grok -i 50 -p "Read the task list at ./tasks.md. Find the first item still
marked [ ]. Implement it, check the box, and stop. Done = all boxes checked."
```

Omit `--model` to use Grok's own default. `--model grok-4.6` (or another installed id) pins one. `sonnet` and `haiku` are Claude model names; they are not passed to Grok unless you set them yourself.

### Run with logging

```bash
ralph -p "Refactor the auth module" -l ./logs --model haiku
```

### Dry run

Preview what ralph will do before committing to a full loop. Sends the complete prompt — including the injected loop controller instructions — to the check model for a quick coherency review (Claude: haiku, unless `--chk-model`; Grok: its own default, unless `--chk-model`):

```bash
ralph -p "Read tasks.md, implement first unchecked item, check box. Done = all boxes checked." --dry-run

ralph --harness grok -p "Read tasks.md. Done = all boxes checked." --dry-run
```

The check model reports on: whether the completion criteria are clear and disk-verifiable, what the agent will likely do each iteration, and whether the prompt fits the one-task-per-iteration mechanic. No tmux session is created; ralph exits after the analysis.

Ralph also runs a preflight check on every normal launch — you'll see a brief "Checking prompt…" progress line. If the check flags a critical issue (missing or unverifiable completion criteria), it surfaces the finding, offers to suggest improvements, and asks `[y/N]` before starting the loop. The progress line clears and a short ok is printed only when the analyst outputs PREFLIGHT_PASS. Any other outcome says the check did not run and asks `[y/N]` before continuing. `--no-preflight` skips the check and says so (it does not claim the prompt looks okay).

### Session management

```bash
ralph --list                # see what's running
ralph --attach              # reattach to latest session
ralph --attach ralph-a1b2   # reattach to specific session
ralph --kill                # kill latest session
ralph --kill ralph-a1b2     # kill specific session
```

## Completion Protocol

Ralph appends loop controller instructions to your prompt automatically. You don't need to worry about the mechanics — just define **what "done" means** in your prompt. Ralph tells the agent to output a specific XML tag (`<promise>RALPH_LOOP_COMPLETE</promise>`) when your criteria are met.

The injected instructions tell the agent to:

1. Do **one unit of work** per iteration.
2. **Persist all progress to disk** (commits, file edits, checked boxes).
3. Evaluate whether all work is finished after each unit.
4. Output the completion tag **only** when everything is genuinely done.

If the agent outputs the tag on stdout, ralph stops and shows a summary. Stderr is not scanned, so a warning cannot satisfy the check. If the tag is absent, ralph loops.

### Circuit Breaker

Three consecutive non-zero exit codes from `claude` or `grok` and ralph trips the circuit breaker — stops the loop and drops you into a shell so you can investigate. The message names the harness. This prevents burning iterations on a broken environment.

Grok tool refusals still exit 0. The work loop passes `--always-approve` so an iteration can actually edit and run commands. `--no-always-approve` (or `--permission-mode`) leaves those refusals exiting 0, and the breaker will not fire on them.

## Tips

- **Fresh context is the point.** Each iteration starts clean. Design your prompts so the agent reads state from disk, not from memory.
- **One task per iteration.** Don't ask the agent to do five things. Ask it to find the *next* thing and do that.
- **Be explicit about completion.** "All boxes checked" is unambiguous. "Everything looks good" is not.
- **Logs are cheap.** Use `--log-dir` so you can audit what happened if something goes sideways.
- **Detach, don't stare.** `Ctrl-b d` to detach. Go do something else. Reattach with `ralph --attach`.
- **Avoid nested tmux.** Launching ralph from inside an existing tmux session creates nested tmux — `Ctrl-b` is captured by the outer session and you'll need `Ctrl-b b` to reach ralph's inner session. Ralph will warn you and ask for confirmation if it detects this. Run ralph from a plain terminal to avoid the hassle.

## License

MIT
