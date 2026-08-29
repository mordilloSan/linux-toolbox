# Codex and Claude tooling

This directory is a copyable snapshot of the reusable LLM tooling used with
LinuxIO.

- `project/LinuxIO/` contains the repository's `AGENTS.md` and `CLAUDE.md`.
- `home/.agents/` contains every shared installed skill.
- `home/.codex/` contains the global instructions, settings, rules, system
  skills, and all currently installed plugin payloads.
- `home/.claude/` contains the global settings, shared-skill links, plugin
  registry metadata, and all currently installed plugin payloads.

The `home/` layout mirrors files below `$HOME`. Copy only the pieces wanted on
the destination system; the saved Codex config and Claude plugin registry
contain source-machine absolute paths that may need adjustment.

Authentication files, credentials, histories, project memories, attachments,
logs, telemetry, databases, caches unrelated to installed plugins, locks,
session state, and stale plugin revisions are excluded. Log in separately on
the destination system.

Current plugin payloads:

- Codex: GitHub, OpenAI templates, plugin management, and Ponytail.
- Claude: Code Review, Context7, Frontend Design, Superpowers, and Ponytail.
