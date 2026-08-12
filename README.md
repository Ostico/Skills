# Skills

A personal collection of **agent skills** — reusable, prompt-level workflows that an AI coding agent loads on demand instead of improvising.

Each skill is a directory containing a single `SKILL.md`. That file is the whole artifact: no code, no build step, no runtime. The agent reads it and follows it.

Most of them describe an *orchestration* — which sub-agents to spawn, what each one is told, how their output is schema-constrained, and how the results get merged into one verdict or one plan. These lean hard on **parallel, adversarial, multi-agent structure**: several independent reviewers instead of one, hostile framing instead of polite framing, structured output instead of prose. That is the thesis behind them — one agent reviewing its own work rationalizes; three blind agents attacking from orthogonal angles do not.

The rest are single-pass discipline: no sub-agents, just a tight instruction set that constrains how the agent answers.

Primary target harness is **Claude Code** (with [oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode) agent types available), but the format is portable — `SKILL.md` with YAML frontmatter is understood by OpenCode, Codex CLI, Gemini CLI, and GitHub Copilot CLI with minor path differences.

## Credits

Several of these skills are **direct ports of [oh-my-openagent](https://github.com/code-yeongyu/oh-my-openagent)** by [@code-yeongyu](https://github.com/code-yeongyu) — a genuinely great plugin on a genuinely great harness. The Prometheus planning persona, the Oracle reviewer role, the delegation-category model, and the "hostile agents tear apart your plan" pattern all originate there. Full credit upstream; the work here is adaptation to Claude Code's tool surface, not invention.

Where a skill below is a port, it says so.

## Skills

| Skill | What it does | Origin |
| --- | --- | --- |
| [`parallel-planning/`](parallel-planning/SKILL.md) | **Prometheus** — strategic planning consultant. Socratic interview, codebase exploration, Critic gap analysis, optional Momus high-accuracy review. Produces a *decision-complete* work plan: zero judgment calls left for the implementer. Refuses to write code. | Port of oh-my-openagent's Prometheus / `/start-work` |
| [`plan-adversarial-review/`](plan-adversarial-review/SKILL.md) | Red-teams a plan before implementation. Three blind refuters (correctness, security, feasibility) attack it in parallel under a hostile prior — "looks fine" counts as a failed review — then one synthesis judge dedupes, ranks by blast radius × likelihood, and issues `GO` / `GO WITH CHANGES` / `NO-GO`. | Claude Code native, same spirit as oh-my-openagent's `hyperplan` |
| [`review-work/`](review-work/SKILL.md) | Reviews *completed* work with 5 parallel specialists: goal verification, hands-on QA execution, code quality, security audit, context mining (git history, GitHub issues/PRs, Slack/Notion). All 5 must PASS; one FAIL fails the review. | Port of oh-my-openagent |
| [`explain-plainly/`](explain-plainly/SKILL.md) | Unpacks something already on the table that was stated in two words or dense jargon — a terse finding, a review comment, an error label. Quote it, read what it points at, replace the jargon, then size the real impact. "Nothing breaks in practice, because…" is an allowed verdict. Single pass, no sub-agents. | Original |

Three of them compose into a pipeline:

```
parallel-planning  →  plan-adversarial-review  →  (implement)  →  review-work
   make the plan        gate it before code                        gate the result
```

`explain-plainly` sits outside that flow — reach for it at any point where an output is too compressed to act on, including the findings the other three produce.

## Design conventions

Recurring patterns in these files, worth keeping if you add more:

- **Frontmatter is the trigger surface.** The `description` decides whether the agent finds the skill at all, so write it as *when to use this*, not *what this is*, and fold the user's likely phrasings into it. Some skills here also carry a separate `triggers` list; `explain-plainly` keeps to `name` + `description` only, which is what Anthropic's own skill validator expects.
- **Independence before synthesis.** Reviewers never see each other's output until a separate synthesis pass. That blindness is the mechanism, not an implementation detail.
- **Schema-constrain sub-agent output.** JSON Schema with `minLength` guards on evidence fields. This defeats two real failure modes: placeholder submissions (`"evidence": "e"`) that terminate an agent while discarding its actual analysis, and suppressed low-confidence findings.
- **Distinguish "clean" from "did not run."** A reviewer returning zero findings *and* an empty "attacks I tried" list is non-functioning, not satisfied. Skills here check for that explicitly and withhold approval on unreviewed dimensions.
- **Record what survived.** Every adversarial skill requires a `triedButSound` / verified-OK list — the attacks actually attempted that the work withstood. Without it, a pass is unfalsifiable.
- **Harness compatibility table at the top.** When a skill originates on another harness, map the tool names explicitly (`task` → `Agent`, `background_output` → auto-notification, `spawn_agent`/`team_*` → `Workflow`) and state that the table wins over any conflicting code block below.

## Installing

There is no installer. Skills are loaded from a directory the harness scans, so copy or symlink them:

```bash
# Claude Code — user scope (available in every project)
ln -s "$PWD/parallel-planning"        ~/.claude/skills/parallel-planning
ln -s "$PWD/plan-adversarial-review"  ~/.claude/skills/plan-adversarial-review
ln -s "$PWD/review-work"              ~/.claude/skills/review-work
ln -s "$PWD/explain-plainly"          ~/.claude/skills/explain-plainly

# Claude Code — project scope
ln -s "$PWD/review-work" /path/to/project/.claude/skills/review-work
```

Other harnesses use the same layout under a different root: `.opencode/skills/` for OpenCode, `skills/` inside an extension for Gemini CLI, `~/.copilot/installed-plugins/` for Copilot.

Symlinking (rather than copying) means editing a skill here updates it everywhere immediately.

A newly installed skill is **not** visible to sessions that are already running — the skill list is built at session start and there is no reload. To use one immediately, tell the running agent `Read <path>/SKILL.md and follow it for this: …`; sessions started afterwards pick it up on their own.

## Known gaps

- `review-work/SKILL.md` still carries upstream OpenCode/oh-my-openagent tool syntax — `task(subagent_type="oracle", category="unspecified-high", load_skills=[...])` and `background_output(task_id=...)`. On Claude Code the equivalents are `Agent(subagent_type=..., run_in_background=true)` and automatic completion notification. It also has no YAML frontmatter, so discovery depends on the installed directory name. Porting it the way `parallel-planning` was ported (compatibility table at the top, native tool names) is the outstanding work.
- The upstream Oracle agent type does not exist on Claude Code. Substitute `oh-my-claudecode:architect` (read-only, Opus) or `oh-my-claudecode:code-reviewer` depending on the role.
