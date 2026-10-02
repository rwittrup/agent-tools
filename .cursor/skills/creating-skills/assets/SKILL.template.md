<!--
Copy to <skills root>/[group/]<name>/SKILL.md and delete these comments.
- name: lowercase letters, digits, single hyphens; <=64 chars; must equal the directory name
- description: <=1024 chars; say what it does AND when to use it (this is all that loads at startup)
- Groups are existing plain subdirectories only; the skill name is the last path segment
- Keep SKILL.md to what a script can't hold; put commands in scripts/, longer docs in references/, templates in assets/
-->
---
name: <skill-name>
description: <What it does>. Use when <trigger conditions>. <Scope limits, e.g. laptop only; for X see other-skill>.
---

# <Title>

<One or two lines: the goal, and the human steps (if any) the agent must not do itself.>

## Run it

```bash
scripts/<script>.sh [args]    # <what it does; exit codes that mean something>
```

## Things you would not guess

- <Non-obvious fact that cost you time, with the symptom it explains.>

## Gotchas that change the result

- **<Result you might misread>:** <what to trust instead>.
