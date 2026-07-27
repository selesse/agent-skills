---
name: pr-description
description: Prepares a pull request description. Use when asked to write or draft a PR description.
---

# PR Description Style

Write PR descriptions following these conventions:

## Title

- Imperative mood: "Add feature" not "Added feature"
- Capitalize the first letter
- Be descriptive; longer than commit subjects is fine

## Body Structure

Use the lightest structure that answers the reviewer's likely questions. Most small and medium PRs only need a short paragraph or two. Add headings or bullets when they improve scanning, such as rollout steps, alternatives considered, risks, or explicit reviewer questions.

Include only the parts that matter for this PR:

1. **Issue link** (if applicable): Start or end with `Part of <url>` or `Fixes <url>`
2. **Why**: Explain WHY this change is needed - the problem, context, or motivation
3. **Assumptions**: Call out any assumptions made or decisions that reviewers should know about
4. **Code references**: Link to existing code when relevant (see below)

## Signal-to-noise

Reviewers are busy. Every sentence should earn its place. A sentence earns its place if it does at least one of:

- Establishes the problem the reviewer needs to understand to evaluate the change
- Explains a non-obvious decision (the "why this, not that")
- Pre-empts a question the reviewer is likely to ask
- Discloses an assumption, risk, or dependency that affects approval

If a sentence doesn't do one of those, cut it. Trust reviewers to read the diff for *what* changed.

### Patterns to cut

- **Restating the problem in different words.** Once is enough.
- **Unexplained "matches existing pattern" arguments.** If the pattern reduces risk or preserves an interface, say that directly.
- **Sections that require no reader action.** ("Identity unchanged", "Canary follows the same pattern.") If there's no decision or follow-up, the diff is enough.
- **Defending uncontroversial choices.** If reviewers won't push back, don't pre-empt.
- **Show-your-work narration.** ("After investigating, I determined that...") The conclusion is the value, not the journey.
- **Filler transitions.** ("It's worth noting", "Of note", "Importantly".)
- **Listing what you did in bullet form** ("- Updated X", "- Added Y"). The diff already shows this.

### Mandatory deletion pass

After drafting any non-trivial description, do an explicit deletion pass before writing the file:

1. Read each sentence and ask: "If I cut this, would a reviewer be confused, ask a question I haven't answered, or make a worse decision?"
2. If no, delete it.
3. For drafts longer than a few sentences, aim to cut 30-50% on this pass. If you cut less than 20%, look harder — the first draft is rarely that tight.

Do not skip this step for substantive PRs. The first draft is rarely the right level of density; the second pass is where signal-to-noise actually improves.

### Bullets vs prose

Bullets are good for **sequences and parallel options** — rollout steps, alternatives considered, multi-step plans. Bullets are bad for **"things I did"** — that's diff territory and should be cut entirely.

### Tightening example

❌ Verbose:

> This PR is the first of two. It adds a new ingress called `web-internal` that mirrors the existing `web-api` pattern in this directory. The new ingress is annotated with a separate SFE environment so that admin traffic can be weighted independently from merchant traffic. Note that this is a noop because both ingresses claim the same host, and the duplicate-host conflict in `SyncIngress` causes the new mapping to be silently rejected.

✅ Tight:

> Adds a `web-internal` ingress with its own SFE env so admin can be weighted independently from merchant traffic. Noop on its own — both ingresses claim `banking.shopify.io`, and `SyncIngress` silently rejects the duplicate.

Same load-bearing content, half the words, denser per token. Note what was cut: "first of two" (not load-bearing for *this* PR's review), "mirrors the existing pattern" (not load-bearing for the decision), "is annotated with" (mechanism the reader can infer from the diff), "Note that" (filler).

## Code References

Only link to code that is **outside** the PR (existing code for context). Never link to lines being changed by the PR itself — the SHA may change if the branch is rebased/amended, and reviewers already see those changes in the diff.

When linking to existing code, use permanent links with the commit SHA, not `main`:

Good: `https://github.com/shop/world/blob/845bb9d9e90c30668470d808593389397f4e89bd/path/to/file.rb#L691-L695`

Bad: `https://github.com/shop/world/blob/main/path/to/file.rb#L691-L695`

## Optional Sections

- `## Questions for reviewers` - When you need input on specific decisions
- `### Before / ### After` - For visual changes, include screenshots
- `<details><summary>...</summary>...</details>` - For verbose info like stacktraces or long code samples
- Links to related PRs when relevant

## Example

```markdown
Part of https://github.com/shop/issues-team/issues/123

When identity isn't running in development, `userLimits` returned `Field 'userLimits' doesn't exist` because the mock context had USER_ACCESS scopes but `user_access: false`.

`UserLimits` visibility depends on a `sub` claim, so development tokens now include one. I assumed this only needs to work in development mode; if tests need the same behavior, we'd need to extend `TestContextOverrides` too.

## Questions for reviewers

Should test contexts get the same `sub` claim behavior?
```

## Output

1. Run `ruby ~/.claude/skills/pr-description/context.rb` to get branch name, main SHA, commits, and diff stats
2. If the diff stats aren't enough context, run the full diff command printed at the end of the script output
3. Write the PR description to `~/.claude/local-notes/pr-descriptions/pr-<branch_name>.md` using GitHub flavored markdown
4. Copy to clipboard: `cat ~/.claude/local-notes/pr-descriptions/pr-<branch_name>.md | pbcopy`
5. Tell the user it's been copied and mention the file path in case they need to retrieve it later
