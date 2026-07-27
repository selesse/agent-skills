---
name: review-pr
description: Reviews a GitHub PR and writes feedback. Use when asked to review a PR, give PR feedback, or look at a pull request.
argument-hint: [pr-number-or-url]
---

# PR Review

Review the pull request and write actionable feedback.

## Steps

0. **Extract PR number**: Extract the numeric PR number from `$ARGUMENTS`. It may be a bare number, a GitHub URL (`https://github.com/shop/world/pull/479413`), or a Graphite URL (`https://app.graphite.dev/github/pr/shop/world/479413`). The PR number is always the last numeric segment of the path (ignoring query params). Use this number as `$PR_NUMBER` below. Always pass the **GitHub URL** form (`https://github.com/shop/world/pull/$PR_NUMBER`) to `gh` commands.
1. **Fetch PR metadata**: Use `gh pr view https://github.com/shop/world/pull/$PR_NUMBER --json title,body,files,additions,deletions` and `gh pr diff https://github.com/shop/world/pull/$PR_NUMBER`
2. **Read the PR description**: Understand the author's intent and motivation before looking at code
3. **Understand the net diff**: Many PRs move code around. Separate what actually changed from what was just relocated. When the PR is primarily a refactor, call out the net-new behavior changes explicitly
4. **Read surrounding code**: Don't review the diff in isolation. Read the files being changed to understand context — how callers use the code, what the types are, what the tests cover
5. **Identify feedback-worthy items**: Only flag things that are genuinely actionable (see guidelines below)
6. **Write the review** to `~/.claude/local-notes/pr-reviews/pr-$PR_NUMBER.md` (directory already exists — do NOT mkdir)
7. **Copy to clipboard**: `cat ~/.claude/local-notes/pr-reviews/pr-$PR_NUMBER.md | pbcopy`
8. Tell the user it's been copied and mention the file path

## Approach Check

Before diving into code-level feedback, evaluate the overall approach:

- **Does the PR description explain the problem?** If the "why" is missing or unclear, ask for it — you can't judge the approach without understanding the problem
- **Is this the right way to solve it?** Given what you know about the codebase, consider whether there's a simpler or more natural approach. Maybe the extracted code belongs somewhere else, maybe an existing abstraction already handles this, maybe the problem doesn't need solving at all
- **Does the scope make sense?** Is the PR doing too much, or splitting things in a way that makes the intermediate state worse?

If you have thoughts on the approach, put them at the top of the review under an `## Approach` heading before any code-level feedback. Only include this section if you have something genuinely useful to say — don't just summarize what the PR already says.

## Code-Level Feedback

Focus on issues that matter:

- **Type safety regressions**: Return types that got weaker, missing nil checks, Sorbet strictness downgrades
- **Behavioral changes hiding in refactors**: Logic that subtly changed during a "just moving code" PR
- **Test gaps**: Tests that don't actually exercise what they claim to, missing `subject` calls, `expect_any_instance_of` where a precise mock would work
- **Dead code or unused parameters**: Code that was copied but no longer needed in the new location
- **Missing error handling at boundaries**: Callers that assumed non-nil but the contract changed

## What NOT to flag

- Formatting, style, naming preferences (leave that to linters)
- Things that are already correct but you'd do differently
- Adding comments suggesting documentation
- Nitpicks on test structure unless something is actually broken
- Obvious things the author already knows (e.g., "this is a refactor" when the PR says so)

## Tone and Style

- Be friendly, collaborative, and curious — you're helping a teammate, not grading an assignment
- Frame feedback as questions or suggestions: "Can we...", "Could we...", "What do you think about..."
- Be genuinely curious when you don't understand a choice — ask rather than assume it's wrong
- Provide context for WHY something matters — don't just say "this is wrong"
- Be conversational and direct, not formal
- Keep each comment concise — a short paragraph, not an essay
- If the PR is good and there's nothing actionable, say so — don't manufacture feedback

## Output Format

Write each piece of feedback as a separate block with the file path, separated by `---`:

```markdown
`path/to/file.rb` — Short description of the concern.

Explanation with context for why it matters and a suggested alternative if applicable.

---

`path/to/other_file.rb` — Another concern.

Explanation.
```

If the PR looks good with no actionable feedback, just write that.
