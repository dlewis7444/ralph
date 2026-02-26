# ralph
A bash based ralph loop for Claude Code

I tried existing loops. Maybe it was my bad prompting. But the official plugin from Anthropic crapped out after 2 iterations. Frank's quit after 1 iteration.

So I (and Claude) wrote my own. It's just a single shell script file.

---

Example prompt:
```
ralph -i 50 -p "Read the task list at <path>/<markdown-file>. Find the first item still marked [ ] (unchecked). Implement it fully per the spec in that file, write all specified tests, and commit on an appropriately named feature branch. Then edit the task file to check the box [x] and add a brief status note (date, branch name, test count, work desc.). Do NOT implement more than one item per iteration — only the first unchecked one. After checking the box, re-read the full task list. Only if no more unchecked boxes remain do you output the completion promise."
```

NOTE: Word it however you want but be sure to include an instruction on what criteria allows Claude to output the completion promise.

---

For your reference, the script appends your prompt:
```
PROMISE_TAG="RALPH_LOOP_COMPLETE"

FULL_PROMPT="${PROMPT}

--- LOOP CONTROLLER INSTRUCTIONS (injected automatically) ---
You are running inside an automated loop. Each iteration gives you a
fresh context window — you have no memory of prior iterations. Re-read
any task lists or state files from disk at the start of every iteration.

RULES:
1. Do ONE unit of work per iteration (one task, one item, one file —
   whatever granularity the prompt above defines).
2. Persist all progress to disk (commits, file edits, checked boxes)
   so the next iteration can see it.
3. After completing your one unit of work, evaluate whether ALL work
   described in the prompt is now finished.
4. If work remains, end your response with a short status summary.
   Do NOT output the completion tag.
5. If and ONLY if every task/item is genuinely complete with nothing
   remaining, output EXACTLY this completion tag as the very last
   thing in your response:
   <promise>${PROMISE_TAG}</promise>
--- END LOOP CONTROLLER INSTRUCTIONS ---"
```
