# RHDH Plugins Skills

Cursor skills for the RHDH Plugins team working in the [rhdh-plugins](https://github.com/redhat-developer/rhdh-plugins) monorepo. Each skill is a top-level directory in this repo. Cursor loads a skill from **either** a project install in an `rhdh-plugins` clone or a global install under `~/.cursor/skills/`.

Source: [github.com/imykhno/rhdh-plugins-skills](https://github.com/imykhno/rhdh-plugins-skills)

## Setup

### Project install

Share skills with the team by copying them into a local `rhdh-plugins` clone (create `.cursor/skills/` if it does not exist):

```bash
mkdir -p /path/to/rhdh-plugins/.cursor/skills
cp -R validate-changes rhdh-plugins-unit-tests /path/to/rhdh-plugins/.cursor/skills/
```

### Global install

Use skills across clones by installing them in your user skills directory:

```bash
git clone https://github.com/imykhno/rhdh-plugins-skills.git ~/.cursor/skills/rhdh-plugins-skills
# or copy a single skill:
mkdir -p ~/.cursor/skills
cp -R validate-changes ~/.cursor/skills/
cp -R rhdh-plugins-unit-tests ~/.cursor/skills/
```

| Scope | Path |
|-------|------|
| Project | `rhdh-plugins/.cursor/skills/<name>/` |
| Global | `~/.cursor/skills/<name>/` or `~/.cursor/skills/rhdh-plugins-skills/<name>/` |

## Skill catalog

| Skill | Description |
|-------|-------------|
| [`rhdh-plugins-unit-tests`](rhdh-plugins-unit-tests/SKILL.md) | Guides creating, updating, and reviewing Jest unit tests for Backstage frontend and backend plugins. Asserts behavior over implementation and mocks at boundaries only. Use when adding or improving unit tests; not for Playwright e2e or full workspace validation. |
