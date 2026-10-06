# librarian

A **Claude Code agent**, not a skill: the one directory in this repo that ships a sub-agent definition instead of a `SKILL.md`. It researches external open-source code (libraries, frameworks, SDKs, CLIs) and answers with evidence: source read at a pinned commit, docs for the right version, and the issue and PR history behind a behaviour. Every code claim carries a GitHub permalink pinned to a commit SHA.

Adapted from the Librarian agent in [oh-my-openagent](https://github.com/code-yeongyu/oh-my-openagent) by [@code-yeongyu](https://github.com/code-yeongyu) (`packages/omo-opencode/src/agents/librarian.ts`).

## Why an agent and not a skill

The work is clone a repo, read files, fetch docs pages, page through issues: a lot of output that the caller never needs to see. As an agent it runs in its own context window and returns only the cited answer. It can also run in the background, and several can run in parallel, one per candidate library. A skill runs in the caller's context and can do neither.

## Install

The agent definition is `agent.md`. Symlink it into your agents directory under the name the harness should see:

```bash
mkdir -p ~/.claude/agents
ln -s "$PWD/librarian/agent.md" ~/.claude/agents/librarian.md
```

For a single project instead, link it into that project's `.claude/agents/`. Restart Claude Code (or run `/agents`) so it picks the agent up.

The file is called `agent.md`, not `AGENTS.md`, on purpose: Codex, OpenCode, and other harnesses auto-load any `AGENTS.md` they find as instructions, and on a case-insensitive filesystem (default macOS) `agents.md` matches too.

## When to use it

| Question | Use |
| --- | --- |
| How does library X implement Y? Show me the source. | **librarian** |
| Why did X change in v3? Is this a known bug? Which PR introduced it? | **librarian** |
| Is this candidate dependency safe to adopt? | **librarian** (code health), alongside `document-specialist` (documented features and fit) |
| What is the signature or option for this API call? | `document-specialist`: cheaper, docs are enough |
| Which tools exist for job X? | Web search first; hand the shortlist to librarian |
| Where is X in *this* repository? | `Explore` |

## How to call it

Name the library (owner/repo if known), the version, and one concrete question, and ask for a verdict plus evidence. To compare candidates, launch one librarian per candidate in a single message so they run in parallel.

```text
Use the librarian agent: pg-boss (timgit/pg-boss), latest major.
Is it safe to depend on for production job queues? How is job locking
implemented (cite source)? Any open bugs about lost or duplicated jobs?
Releases in the last 12 months? Verdict + permalinks.
```

## Requirements

- **Required:** `gh` authenticated (`gh auth status`) and `git`. Without them only the docs paths work.
- **Optional:** a Context7 MCP server (curated, versioned docs) and a grep.app MCP server (code search across public GitHub). Without them the agent falls back to `WebSearch`/`WebFetch` and `gh search code`, which works but is slower and less precise for docs lookups.

## Tools and model

- `model: sonnet`. Switch to `haiku` in the frontmatter for cheaper, shallower lookups.
- `Write`, `Edit`, `NotebookEdit`, and `Agent` are disallowed. It still needs `Bash` for `gh` and `git`, and Bash is not restricted, so "read-only" is a rule in its prompt, not an enforced guarantee: it clones into `${TMPDIR:-/tmp}`. Your normal permission mode still applies to its Bash calls.

## Porting notes

`agent.md` is a near-verbatim port of the upstream prompt. Deviations:

- **Frontmatter** replaces the TypeScript wrapper. The upstream `description`, `keyTrigger`, `triggers`, and `useWhen` metadata are merged into `description`, plus a how-to-call line and one example.
- **Tool restrictions** `write, edit, apply_patch, task, call_omo_agent` become `disallowedTools: Write, Edit, NotebookEdit, Agent`.
- **Model**: upstream receives it from the caller (tagged `cost: "CHEAP"`); here it is pinned to `sonnet`. `temperature: 0.1` has no Claude Code equivalent and is dropped.
- **Date awareness**: upstream interpolates the year at build time (`${new Date().getFullYear()}`). A static file cannot, so the lines say "current year" / "last year" and rely on the date in the environment context.
- **Tool names**: a mapping paragraph is added to TOOL REFERENCE (`websearch` → `WebSearch`, `webfetch` → `WebFetch`, `gh`/`git` → `Bash`). `websearch_web_search_exa(...)` in that list becomes `WebSearch(...)`. Context7 and grep.app calls are kept as written and used only when those MCP servers are installed.
- **Bug fix**: `gh search prs ... --state merged` becomes `--merged`, because `gh search prs` accepts only `open` or `closed` for `--state`.

Accepted limitations, kept as upstream wrote them:

- Clones go to fixed paths like `${TMPDIR:-/tmp}/repo-name`. Two librarians researching the same repo at the same time can collide, and a stale clone from an earlier run may already exist at that path.
- Context7 and grep.app are not bundled. Without them, the FAILURE RECOVERY fallbacks apply.
