# chat/ — the handoff system between Claude sessions (scratch-2026-10-05-5a158f)

How Claude keeps state across compaction, resume, new sessions and machines, and how Somay sees
what changed. Scaffolded on 2026-10-05 from `~/.claude/chat-template/` by
`~/.claude/hooks/chat/init_chat.py`.

## Core files (mandatory wherever coding happens)

| File | Who writes it | What it is |
|---|---|---|
| `brief.md` | Claude, once, with Somay | The initial idea in five lines. Rubberstamps are judged against it. |
| `checkpoint.md` | Claude | Live state: target, prompts so far, decisions, open gaps, repo state, next action. |
| `resume_prompt.md` | Claude, from the checkpoint | What to do first after a resume or compaction. Under 20 lines. |
| `decisions.md` | Claude | Append-only decisions with why and status. |
| `gotcha.md` | Claude + Somay | Looked normal, cost real time: what you'd do → what happens → what to do instead. |
| `rubberstamp.md` | Claude | Each instruction from Somay that moved the project away from `brief.md`, with the cost. |
| `future.md` | Claude | Somay's deferrals, quoted, with triggers; Claude's own deferrals in a separate section. |
| `ledger_review.md` | Claude, enforced | One line per turn that needed a review. Checked by the Stop hook. |
| `prompts.md` | hook | Every prompt, secrets redacted. Gitignored: never committed. |

Optional (`init_chat.py --all`, or by name): `open_questions`, `plan`, `user_gate`, `exploit_log`,
`glossary`, `sources`. Only when the project has no equivalent. If a project already keeps a
checkpoint or decision log elsewhere, make the `chat/` file a symlink to it rather than a copy.

## The hooks (global, `~/.claude/hooks/chat/`, registered in `~/.claude/settings.json`)

| Event | Script | Effect |
|---|---|---|
| `SessionStart` | `session_resume.py` | Prints `resume_prompt.md` with a staleness header, then a context pack (brief, DO NOT BUILD ON gaps, Somay's open promises, latest gotchas, the enforced rules); records the code state; reports turns that ended SKIPPED since the last session. |
| `UserPromptSubmit` | `log_prompt.py` | Appends the prompt (secrets redacted) to `prompts.md`; before `chat/` exists it buffers in `~/.claude/state/chat/` so read-only visits leave no folder. |
| `UserPromptSubmit` | `prompt_signals.py` | Marks the turn start and baselines the code state (per turn, so parallel sessions and Somay's own edits aren't blamed on this turn). If the prompt reads like a deferral ("later", "for now", "after the demo") or a redirect ("instead", "from scratch", "revert"), injects a reminder quoting it, right then. |
| `PostToolUse` Edit/Write | `nudge_scaffold.py` | First edit in a project without `chat/` → tells Claude to scaffold it. |
| `Stop` | `checkpoint_guard.py` | Transcript grew > 150 KB since the checkpoint, or the resume prompt is older than it → update before stopping. |
| `Stop` | `ledger_guard.py` | Review due if this turn changed code (git status of the project and nested repos, .gitignore respected, a commit counts; no git → filtered mtime scan), or the prompt was flagged, or ≥ 2 tool calls failed. Then the last line of `ledger_review.md` must be fresh, name all three ledgers, not claim an entry whose file didn't change, and give a reason for "none" on a flagged ledger. If code changed and nothing was run against it afterwards (tests, typecheck, lint, build, curl, browser/simulator), the line also needs `· verify: none — why`. After 3 blocks: SKIPPED line, turn ends. Never runs in `~`, `/`, or a folder that only holds several projects. |
| `PreCompact` | `precompact_guard.py` | Manual `/compact` while the handoff is stale (checkpoint behind, resume older than checkpoint, unreviewed code change) → blocked with the reason; `/compact` again within 3 min forces it. Auto-compaction never blocked, recorded as stale. Stamps the checkpoint either way (without resetting its staleness baseline). |
| `Stop` (after compaction) | `checkpoint_guard.py` | If the last compaction happened while stale, the next turn can't end until checkpoint and resume prompt are re-verified and rewritten (3 reminders max). |
| `PreToolUse` Bash | `commit_guard.py` | Denies `git commit` / `git push` / `gh pr create|merge` unless this turn's prompt asked for it; denies any Claude co-author / generated-by line (inline or `-F` file). Only matches git in command position, not in quoted text. |
| `SessionEnd` | `session_end_stamp.py` | Stamps the checkpoint with how the session ended. |

State lives in `~/.claude/state/chat/<project>/sessions/<session>.json`, never in the project.

## For Somay

- `cat chat/ledger_review.md` shows what each turn added; `SKIPPED` means a turn ended without it.
- `git diff chat/` shows what changed between sessions (prompts.md is never committed).
- `CHECKPOINT_THRESHOLD_KB=300` in the environment if the checkpoint guard nags too often.
- Disable everywhere: remove the `hooks/chat/` entries from `~/.claude/settings.json`
  (backups: `settings.json.bak-ledgers*`).
