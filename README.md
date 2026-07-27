# Agent skills

Personal skills shared across coding agents.

## Setup

Clone the repository and run:

```sh
git clone https://github.com/selesse/agent-skills.git ~/git/agent-skills
cd ~/git/agent-skills
./setup
```

The setup script links each repository skill into `~/.claude/skills`, exposes that shared directory through both `~/.agent/skills` and the standard `~/.agents/skills` location, and installs the Claude status line from `integrations/claude`.

Existing unrelated skills are preserved. If a migrated skill already exists at one of the managed paths, use:

```sh
./setup --force
```

Conflicting paths are moved under `~/.agent-skills-backups` before they are replaced. Use `./setup --dry-run` to preview changes.

## Skills

- `commit-message`
- `pr-description`
- `prepare-for-review`
- `review-pr`
- `review-review`

## Integrations

- Claude Code status line
