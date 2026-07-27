---
name: prepare-for-review
description: Prepares a branch for review — commits, runs checks, pushes with Git, and writes or updates a PR description. Use when asked to "prepare for review", "submit for review", or "get this ready for review".
---

# Prepare for Review

End-to-end workflow: commit changes, run checks, push with Git, and write or update a PR description.

Has the commit/PR changed and diverged from the original strategy? If so, let's prepare it for review by updating it.

## Step 1: Commit

For each logical commit the user wants (default: one commit for all staged + unstaged changes):

1. Stage the relevant files
2. Run `/commit-message` to draft the message
3. **AI Attribution**: Ensure the commit message ends with:
   ```
   Co-Authored-By: Claude <model> <noreply@anthropic.com>
   ```
   If the generated message is missing this trailer, append it before committing.
4. Commit with plain `git commit`.
   - For subject-only messages, `git commit -m "<message>"` is fine.
   - For multi-line messages, write the message to `.git/COMMIT_MSG` and use `git commit -F .git/COMMIT_MSG`.

If the user requests multiple commits, repeat steps 1-4 for each. Every commit must have the AI attribution trailer.

## Step 2: Run checks

Only run checks that were used earlier in the conversation. Look through the conversation history for:

- **rubocop**: If rubocop was run on any files, run `shadowenv exec -- bundle exec rubocop -a` on the modified files
- **TypeScript**: If `tsc` or type checking was run, run it again
- **Tests**: If specific test files were run, re-run them

If none of these were run during the conversation, skip this step entirely.

If any check fails, fix the issue and amend the relevant commit before proceeding.

## Step 3: Push

Use plain Git.

1. Push the branch with `git push`/`git push -u origin <branch>` as appropriate.
2. Do not create the PR until Step 4, after `/pr-description` has generated the body.

## Step 4: PR metadata

1. Run `/pr-description` to generate the description.
2. If no PR exists, create one with `gh pr create --body-file <description-file>`.
3. Verify the current PR title still matches the final scope of the branch/commits. If it drifted, update it with `gh pr edit <pr-number> --title "<title>"`.
4. Ensure the PR body does not duplicate the title as a first line or heading. The body should start with context/why, not a repeated title.
5. For an existing PR, use `gh pr edit <pr-number> --body "<description>"` (or `--body-file`) to update the PR body on GitHub.
