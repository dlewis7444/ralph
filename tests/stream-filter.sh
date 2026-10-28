#!/usr/bin/env bash
# Pipe a Claude-shaped assistant line and a Grok streaming-messages-json
# sample through the JQ_FILTER assignment extracted from ../ralph.
# The filter string is not copied, so it cannot drift from the script.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RALPH="$ROOT/ralph"

if [[ ! -f "$RALPH" ]]; then
  echo "ralph not found at $RALPH" >&2
  exit 1
fi

# Single-quoted JQ_FILTER=' ... ' with the closing quote alone on its line.
JQ_FILTER="$(
  awk '
    BEGIN { capture = 0 }
    !capture && /^JQ_FILTER='\''/ {
      capture = 1
      sub(/^JQ_FILTER='\''/, "")
      if (sub(/'\''$/, "")) { printf "%s", $0; exit }
      print
      next
    }
    capture {
      if (sub(/'\''$/, "")) { printf "%s", $0; exit }
      print
    }
    END { if (!capture) exit 2 }
  ' "$RALPH"
)" || {
  echo "failed to extract JQ_FILTER from $RALPH" >&2
  exit 1
}

if [[ -z "$JQ_FILTER" ]]; then
  echo "extracted JQ_FILTER is empty" >&2
  exit 1
fi

for needle in 'type == "assistant"' 'type == "tool_use"' 'type == "result"' 'type == "error"' 'iteration complete' 'is_error' 'error_'; do
  if [[ "$JQ_FILTER" != *"$needle"* ]]; then
    echo "extracted filter is missing: $needle" >&2
    exit 1
  fi
done

# Claude stream-json assistant line (text + tool_use), then the
# streaming-messages-json sample from the Grok headless docs
# (assistant text + tool_use, then a successful result). The docs write
# usage as {...}; those objects are filled in so the lines are valid JSON.
# Error cases are filtered one line at a time so a red result cannot hide
# behind the successful result's "iteration complete".
run_filter() {
  printf '%s\n' "$1" | jq --unbuffered -rj "$JQ_FILTER" 2>/dev/null || true
}

claude_assistant='{"type":"assistant","message":{"id":"msg_01","type":"message","role":"assistant","model":"claude-sonnet","content":[{"type":"text","text":"I will read the task list."},{"type":"tool_use","id":"toolu_01","name":"Read","input":{"file_path":"tasks.md"}}],"stop_reason":"tool_use"}}'
grok_assistant='{"type":"assistant","message":{"id":"msg_0","type":"message","role":"assistant","model":"grok-4.6","content":[{"type":"text","text":"Let me read the file."},{"type":"tool_use","id":"call_1","name":"read_file","input":{"path":"src/main.rs"}}],"stop_reason":"tool_use","stop_sequence":null,"usage":{"input_tokens":1,"output_tokens":1}},"parent_tool_use_id":null,"session_id":"abc123","uuid":"u2"}'
ok_result='{"type":"result","subtype":"success","is_error":false,"duration_ms":0,"duration_api_ms":0,"num_turns":7,"result":"Here is a summary.","stop_reason":"end_turn","total_cost_usd":0.0127,"usage":{"input_tokens":812,"output_tokens":210},"session_id":"abc123","uuid":"u3"}'
err_result='{"type":"result","subtype":"error_max_turns","is_error":true,"errors":["hit max turns"]}'
startup_error='{"type":"error","message":"Could not start session: backend down"}'
subtype_error='{"type":"error","subtype":"error_max_turns"}'
errors_string='{"type":"result","is_error":true,"errors":["hit max turns"]}'
errors_object='{"type":"result","is_error":true,"errors":[{"message":"disk full"}]}'

assistant_out="$(run_filter "$claude_assistant")"$'\n'"$(run_filter "$grok_assistant")"
ok_out="$(run_filter "$ok_result")"
err_out="$(run_filter "$err_result")"
startup_out="$(run_filter "$startup_error")"
subtype_out="$(run_filter "$subtype_error")"
errors_string_out="$(run_filter "$errors_string")"
errors_object_out="$(run_filter "$errors_object")"

fail=0
check_has() {
  local label="$1" hay="$2" needle="$3"
  if [[ "$hay" != *"$needle"* ]]; then
    echo "missing from ${label}: ${needle}" >&2
    fail=1
  fi
}
check_lacks() {
  local label="$1" hay="$2" needle="$3"
  if [[ "$hay" == *"$needle"* ]]; then
    echo "unexpected in ${label}: ${needle}" >&2
    fail=1
  fi
}

check_has "claude assistant" "$assistant_out" "I will read the task list."
check_has "claude assistant" "$assistant_out" "Read"
check_has "grok assistant" "$assistant_out" "Let me read the file."
check_has "grok assistant" "$assistant_out" "read_file"

# Successful result is the success signal. The error result must not be.
check_has "success result" "$ok_out" "iteration complete"
check_lacks "success result" "$ok_out" $'\033[31m'
check_has "error result" "$err_out" $'\033[31m'
check_has "error result" "$err_out" "error_max_turns"
check_lacks "error result" "$err_out" "iteration complete"

check_has "startup error" "$startup_out" "Could not start session: backend down"
check_has "startup error" "$startup_out" $'\033[31m'
check_has "subtype error" "$subtype_out" "error_max_turns"
check_has "errors string" "$errors_string_out" "hit max turns"
check_lacks "errors string" "$errors_string_out" "iteration complete"
check_has "errors object" "$errors_object_out" "disk full"
check_lacks "errors object" "$errors_object_out" "iteration complete"

if [[ "$fail" -ne 0 ]]; then
  echo "---- filter output ----" >&2
  printf 'assist:\n%s\n' "$assistant_out" >&2
  printf 'ok:\n%s\n' "$ok_out" >&2
  printf 'err:\n%s\n' "$err_out" >&2
  printf 'startup:\n%s\n' "$startup_out" >&2
  printf 'subtype:\n%s\n' "$subtype_out" >&2
  printf 'errors string:\n%s\n' "$errors_string_out" >&2
  printf 'errors object:\n%s\n' "$errors_object_out" >&2
  exit 1
fi

echo "stream-filter: ok"
