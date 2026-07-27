---
name: review-review
description: Reviews the review comments on a PR and helps address them. Use when asked to review a review, respond to PR feedback, or address review comments.
argument-hint: [pr-url-or-number]
allowedTools:
  - Bash(ruby ~/.claude/skills/review-review/fetch_review.rb *)
  - Bash(ruby ~/.claude/skills/review-review/respond_to_thread.rb *)
  - Bash(mkdir -p ~/.claude/local-notes/review-reviews)
  - Bash(cat ~/.claude/local-notes/review-reviews/* | pbcopy)
---

# Review the Review

Fetch all review comments from a PR, understand them, and help the author respond.

## Steps

0. **Extract PR info**: Extract the PR number and repo from `$ARGUMENTS`. Supports:
   - Bare number: `491550`
   - GitHub URL: `https://github.com/shop/world/pull/491550`
   - Graphite URL: `https://app.graphite.com/github/pr/shop/world/491550`

1. **Fetch review data**: Run `ruby ~/.claude/skills/review-review/fetch_review.rb $ARGUMENTS` to get all comments in one shot. Resolved threads are collapsed to a one-line summary by default — re-run with `--include-resolved` only if you actually need to read the resolved history (e.g. "what did the author already promise?").

2. **Read the review output**: Understand every piece of feedback — both human and bot (marked `[BOT]`). Threads tagged `[OUTDATED]` are anchored to code that has since changed; weight them less and verify against the current file before suggesting any action.

3. **Read the actual code**: For each inline comment, read the referenced file to understand the full context. Don't evaluate feedback based only on the diff hunk — understand the surrounding code

4. **Evaluate each comment**: For each piece of feedback, determine:
   - **Valid and actionable**: The reviewer found a real issue. Suggest a fix
   - **Already addressed**: The concern is handled elsewhere in the code. Explain where
   - **Intentional tradeoff**: The author made a deliberate choice. Draft a reply explaining the reasoning
   - **Not applicable**: The feedback is based on a misunderstanding. Draft a polite clarification
   - **Bot noise**: Low-signal automated comment that doesn't need a response

5. **Write the analysis** to `~/.claude/local-notes/review-reviews/pr-$PR_NUMBER.md`. For each comment, include the **comment databaseId** (the `discussion_r<id>` number from the comment URL) so the responder script can find the thread later.

6. **Copy to clipboard**: `cat ~/.claude/local-notes/review-reviews/pr-$PR_NUMBER.md | pbcopy`

7. Tell the user it's been copied and mention the file path. **Wait for the user to approve** before posting anything to GitHub.

8. **Once the user approves the drafts, post them — but only for bot comments**. Human comments stay in the clipboard for the user to handle manually; people often want a threaded back-and-forth, not a one-shot reply, and reactions/auto-resolve on a human is awkward.

   For each **bot** thread the user approved, run:

   ```bash
   ruby ~/.claude/skills/review-review/respond_to_thread.rb <pr> <comment-id> \
     --reply "<approved reply text>" \
     --reaction +1   # or -1
     --resolve
   ```

   The script handles the three identifiers GitHub uses (comment databaseId, comment node ID, thread node ID) so you only need to pass the comment ID. Comment ID can be the bare number (`3190948932`) or the full URL (`https://github.com/shop/world/pull/682891#discussion_r3190948932`).

   For long replies, pipe via stdin: `echo "..." | ruby respond_to_thread.rb <pr> <id> --reply -`.

   Run one thread at a time — don't try to multi-line a giant for-loop in bash, it's how you end up with one thread's reply showing up on another thread.

## Output Format

For each comment, write a block like:

```markdown
---

### `path/to/file.rb:42` — @reviewer_login

**Comment ID**: 3190948932 — https://github.com/shop/world/pull/682891#discussion_r3190948932

> Original comment text (abbreviated if long)

**Assessment**: Valid / Already addressed / Intentional / Not applicable
**Reaction** (bot only): 👍 (useful feedback) / 👎 (low-signal or wrong)

Explanation of your assessment and suggested action (fix, reply, or ignore).

If suggesting a fix, include the code change.
If suggesting a reply, draft the reply text.
```

The Comment ID lets step 8 find the thread without a separate lookup. The Reaction field only applies to bot comments — omit it for humans.

## Guidelines

### Human reviewers
- Be honest — if the reviewer is right, say so and suggest a fix
- If the reviewer is wrong, draft a reply that's respectful and explains the reasoning
- Don't be defensive on behalf of the author — be objective
- Group related comments if they're about the same underlying concern
- **Don't auto-post or auto-resolve human threads.** Drop drafts in the clipboard and stop. Humans expect a real conversation, not an agent firing off canned replies and clicking resolve.

### Bot reviewers (Binks)
Binks is an AI code reviewer. Its comments are marked `[BOT]` in the output. Evaluate them with healthy skepticism:

- **Is this actually going to happen?** Binks often flags theoretical issues (e.g., "what if job_class is invalid?") that are unrealistic in practice. Consider whether the scenario is plausible given how the code is actually used — check callers, validations, and constraints
- **Is the fix worth the complexity?** Even if the issue is real, the cure might be worse than the disease. A try/rescue around every constantize call adds noise; if the data is validated on write, it's fine
- **Does it understand the broader system?** Binks only sees the diff and immediate context. It often misses that concerns like idempotency or locking are handled at a different layer (e.g., job framework, database constraints, scheduling guarantees)
- **Ask the user when uncertain**: If you can't determine whether a Binks concern is valid from the code alone (e.g., "is this job scheduled with concurrency controls?"), ask rather than guess. Frame it as: "Binks flagged X — is this a concern given how Y works?"

**Always draft a reply** for every Binks comment. Binks uses feedback to improve, so it needs to hear why you're actioning or dismissing its suggestion. Keep it short — one or two sentences explaining the reasoning (e.g., "job_class is validated on write so this can't happen" or "good catch, adding error handling").

Bottom line: welcome the questioning, but be realistic. Don't recommend changes just because a bot raised a concern — only if the concern survives scrutiny.
