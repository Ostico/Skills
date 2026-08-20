# Skills

A personal collection of **agent skills** — reusable, prompt-level workflows that an AI coding agent loads on demand instead of improvising.

Each skill is a directory whose entry point is `SKILL.md`. There is no build step and no runtime: the agent reads that file and follows it. Most skills stop there. Where one needs more than fits in a single readable file it splits — `references/` for detail loaded only at the step that needs it, `assets/` for templates the agent copies, `scripts/` for the one job better done deterministically than by prompt. `manual-qa-plan` is currently the only skill here with that structure.

Most of them describe an *orchestration* — which sub-agents to spawn, what each one is told, how their output is schema-constrained, and how the results get merged into one verdict or one plan. These lean hard on **parallel, adversarial, multi-agent structure**: several independent reviewers instead of one, hostile framing instead of polite framing, structured output instead of prose. That is the thesis behind them — one agent reviewing its own work rationalizes; three blind agents attacking from orthogonal angles do not.

The rest are single-pass discipline: no sub-agents, just a tight instruction set that constrains how the agent answers.

Primary target harness is **Claude Code** (with [oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode) agent types available), but the format is portable — `SKILL.md` with YAML frontmatter is understood by OpenCode, Codex CLI, Gemini CLI, and GitHub Copilot CLI with minor path differences.

## Credits

Several of these skills are **direct ports of [oh-my-openagent](https://github.com/code-yeongyu/oh-my-openagent)** by [@code-yeongyu](https://github.com/code-yeongyu) — a genuinely great plugin on a genuinely great harness. The Prometheus planning persona, the Momus and Oracle reviewer roles, the delegation-category model, and the "hostile agents tear apart your plan" pattern all originate there. Full credit upstream; the work here is adaptation to Claude Code's tool surface, not invention.

Where a skill below is a port, it says so.

## Skills

| Skill | What it does | Origin |
| --- | --- | --- |
| [`parallel-planning/`](parallel-planning/SKILL.md) | **Prometheus** — strategic planning consultant. Socratic interview, codebase exploration, Critic gap analysis, optional Momus high-accuracy review. Produces a *decision-complete* work plan: zero judgment calls left for the implementer. Refuses to write code. | Port of oh-my-openagent's Prometheus / `/start-work` |
| [`review-plan/`](review-plan/SKILL.md) | **Momus** — the deliberately *lenient* plan gate. Checks only that a plan can be executed: referenced files exist and contain what is claimed, every task has somewhere to start, every task has QA scenarios naming a tool and an observable expected result. Explicit approval bias ("80% clear is good enough"), no design opinions, at most 3 blocking issues. Verdict is `[OKAY]` or `[REJECT]`. | Port of oh-my-openagent's Momus |
| [`plan-adversarial-review/`](plan-adversarial-review/SKILL.md) | Red-teams a plan before implementation. Three blind refuters (correctness, security, feasibility) attack it in parallel under a hostile prior — "looks fine" counts as a failed review — then one synthesis judge dedupes, ranks by blast radius × likelihood, and issues `GO` / `GO WITH CHANGES` / `NO-GO`. | Claude Code native, same spirit as oh-my-openagent's `hyperplan` |
| [`review-work/`](review-work/SKILL.md) | Reviews *completed* work with 5 parallel specialists: goal verification, hands-on QA execution, code quality, security audit, context mining (git history, GitHub issues/PRs, Slack/Notion). All 5 must PASS; one FAIL fails the review. | Port of oh-my-openagent |
| [`manual-qa-plan/`](manual-qa-plan/SKILL.md) | Turns `<BASE>..HEAD` into a manual test plan a person executes against the running application without reading source. Every changed file must be accounted for — a test case, an explicit "not user-visible" row with a reason, or an open question — and every changed behaviour records both the old and the new side. Ships `scripts/collect_changes.sh`, which pre-groups the diff into risk categories and flags what no heuristic matched. | Original |
| [`explain-plainly/`](explain-plainly/SKILL.md) | Unpacks something already on the table that was stated in two words or dense jargon — a terse finding, a review comment, an error label. Quote it, read what it points at, replace the jargon, then size the real impact. "Nothing breaks in practice, because…" is an allowed verdict. Single pass, no sub-agents. | Original |

Five of them compose into a pipeline:

```
                    ┌  review-plan             ┐
parallel-planning → ┤  can it be executed?     ├ → (implement) → review-work → manual-qa-plan
  make the plan     │  plan-adversarial-review │                 gate result    hand to a tester
                    └  should it be executed?  ┘
```

The two plan gates are not redundant, and they are tuned in deliberately opposite directions. `review-plan` asks *can a developer start on this* and approves by default — the failure it catches is a dead file reference or a task with no entry point. `plan-adversarial-review` asks *should this be built this way* and treats a clean result as a non-functioning review — the failure it catches is an approach that only falls over once the code exists. Reach for the lenient gate on cheap, reversible work and the hostile one when being wrong is expensive; run both when the plan is large enough that broken references and bad architecture are genuinely separate risks.

`explain-plainly` sits outside that flow — reach for it at any point where an output is too compressed to act on, including the findings the other skills produce.

## Design conventions

Recurring patterns in these files, worth keeping if you add more:

- **Frontmatter is the trigger surface.** The `description` decides whether the agent finds the skill at all, so write it as *when to use this*, not *what this is*, and fold the user's likely phrasings into it. Some skills here also carry a separate `triggers` list; `explain-plainly` and `manual-qa-plan` keep to `name` + `description` only, which is what Anthropic's own skill validator expects.
- **Match the reviewer's prior to the cost of being wrong.** A gate's default verdict is a design parameter, not an accident. `review-plan` approves unless blocked and caps itself at 3 issues, because over-rejecting a cheap plan costs more than it saves; `plan-adversarial-review` refuses to accept a clean result at all. Pick the prior from the blast radius, and have the skill state which prior it has chosen so it cannot quietly drift to the other one.
- **Independence before synthesis.** Reviewers never see each other's output until a separate synthesis pass. That blindness is the mechanism, not an implementation detail.
- **Schema-constrain sub-agent output.** JSON Schema with `minLength` guards on evidence fields. This defeats two real failure modes: placeholder submissions (`"evidence": "e"`) that terminate an agent while discarding its actual analysis, and suppressed low-confidence findings.
- **Distinguish "clean" from "did not run."** A reviewer returning zero findings *and* an empty "attacks I tried" list is non-functioning, not satisfied. Skills here check for that explicitly and withhold approval on unreviewed dimensions.
- **Record what survived.** Every adversarial skill requires a `triedButSound` / verified-OK list — the attacks actually attempted that the work withstood. Without it, a pass is unfalsifiable.
- **Account for everything, or say why not.** `manual-qa-plan` requires every changed file to appear in its output even when the entry is "not user-visible, because…". Silent omission is what makes a generated document untrustworthy: the reader cannot tell a considered skip from a miss.
- **Progressive disclosure over one long file.** Keep `SKILL.md` to the workflow and push detail into `references/` that the agent reads at the step needing it. A step that must be exact and repeatable belongs in `scripts/` rather than in prose — deterministic collection is cheaper and more reliable than asking the model to re-derive a set of `git` invocations each time.
- **Verify before delivering, and say what was verified.** Skills here end with an explicit checklist and require the agent to state which of those checks it actually ran when handing the work over.
- **Harness compatibility table at the top.** When a skill originates on another harness, map the tool names explicitly (`task` → `Agent`, `background_output` → auto-notification, `spawn_agent`/`team_*` → `Workflow`) and state that the table wins over any conflicting code block below.

## Installing

There is no installer. Skills are loaded from a directory the harness scans, so copy or symlink them:

```bash
# Claude Code — user scope (available in every project)
ln -s "$PWD/parallel-planning"        ~/.claude/skills/parallel-planning
ln -s "$PWD/review-plan"              ~/.claude/skills/review-plan
ln -s "$PWD/plan-adversarial-review"  ~/.claude/skills/plan-adversarial-review
ln -s "$PWD/review-work"              ~/.claude/skills/review-work
ln -s "$PWD/manual-qa-plan"           ~/.claude/skills/manual-qa-plan
ln -s "$PWD/explain-plainly"          ~/.claude/skills/explain-plainly

# Claude Code — project scope
ln -s "$PWD/review-work" /path/to/project/.claude/skills/review-work
```

Other harnesses use the same layout under a different root: `.opencode/skills/` for OpenCode, `skills/` inside an extension for Gemini CLI, `~/.copilot/installed-plugins/` for Copilot.

Symlinking (rather than copying) means editing a skill here updates it everywhere immediately.

Symlink the skill *directory*, never just its `SKILL.md` — `manual-qa-plan` resolves `references/`, `assets/`, and `scripts/` relative to its own directory, so a bare file symlink loses them.

A newly installed skill is **not** visible to sessions that are already running — the skill list is built at session start and there is no reload. To use one immediately, tell the running agent `Read <path>/SKILL.md and follow it for this: …`; sessions started afterwards pick it up on their own.

## Known gaps

- `review-work/SKILL.md` still carries upstream OpenCode/oh-my-openagent tool syntax — `task(subagent_type="oracle", category="unspecified-high", load_skills=[...])` and `background_output(task_id=...)`. On Claude Code the equivalents are `Agent(subagent_type=..., run_in_background=true)` and automatic completion notification. It also has no YAML frontmatter, so discovery depends on the installed directory name. Porting it the way `parallel-planning` was ported (compatibility table at the top, native tool names) is the outstanding work.
- `review-plan/SKILL.md` is the rawest file here and needs the same port treatment, plus three specific fixes. It has no YAML frontmatter, so the harness falls back to its first line (`Launch a specialized sub-agent, its name is Momus.`) as the description — which names the mechanism rather than when to reach for it, and so barely triggers. Its plan-path rule contradicts itself: the opening rule matches `.omc/plans/*.md` while the input-validation step matches `.omo/plans/*.md`, so a plan under whichever of the two is not being checked gets rejected as invalid input. It also still contains around 20 backslash-escaped backticks (`` \` ``), left over from being embedded in a template string, which render literally.
- `review-plan` hard-codes the plan location to a single directory pattern and rejects YAML plans outright. Plans kept anywhere else — `docs/plans/`, a PR body, a path handed over in conversation — fail input validation before any review happens.
- The upstream Oracle agent type does not exist on Claude Code. Substitute `oh-my-claudecode:architect` (read-only, Opus) or `oh-my-claudecode:code-reviewer` depending on the role.
- `manual-qa-plan/scripts/collect_changes.sh` has not been exercised beyond this repository. Its risk-flag heuristics are path-pattern based, so on an unfamiliar layout expect most files to land in **Uncategorised** and to need reading by hand.
