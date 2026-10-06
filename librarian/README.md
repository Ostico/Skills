# librarian

> **This is an agent, not a skill.** It has no `SKILL.md`, it does not go in `~/.claude/skills/`, and it is never invoked with `/librarian`. It is a Claude Code **sub-agent** definition: it is installed into `~/.claude/agents/`, and the main agent launches it through the Agent tool (or you ask for it by name: "use the librarian agent to…").

The one directory in this repo that ships a sub-agent definition instead of a skill. It researches external open-source code (libraries, frameworks, SDKs, CLIs) and answers with evidence: source read at a pinned commit, docs for the right version, and the issue and PR history behind a behaviour. Every code claim carries a GitHub permalink pinned to a commit SHA.

Adapted from the Librarian agent in [oh-my-openagent](https://github.com/code-yeongyu/oh-my-openagent) by [@code-yeongyu](https://github.com/code-yeongyu) (`packages/omo-opencode/src/agents/librarian.ts`).

## Why an agent and not a skill

The work is clone a repo, read files, fetch docs pages, page through issues: a lot of output that the caller never needs to see. As an agent it runs in its own context window and returns only the cited answer. It can also run in the background, and several can run in parallel, one per candidate library. A skill runs in the caller's context and can do neither.

## Install

Run from the root of this repository.

**1. Install the agent.** The definition is `agent.md`; symlink it into your agents directory as `librarian.md`:

```bash
mkdir -p ~/.claude/agents
ln -s "$PWD/librarian/agent.md" ~/.claude/agents/librarian.md
```

For a single project instead, link it into that project's `.claude/agents/librarian.md`.

**2. Install the two MCP dependencies** (see [Dependencies](#dependencies)). Both are remote HTTP servers, so there is nothing to run locally. `-s user` makes them available in every project:

```bash
claude mcp add -s user --transport http context7 https://mcp.context7.com/mcp
claude mcp add -s user --transport http grep https://mcp.grep.app
```

**3. Check `gh`**, which the agent uses to clone repositories and search issues and PRs:

```bash
gh auth status
```

**4. Restart Claude Code.** Agents and MCP servers are loaded at session start. Then check:

```bash
claude mcp list          # context7 and grep should show as connected
```

and run `/agents` inside Claude Code: `librarian` should be listed.

The file is called `agent.md`, not `AGENTS.md`, on purpose: Codex, OpenCode, and other harnesses auto-load any `AGENTS.md` they find as instructions, and on a case-insensitive filesystem (default macOS) `agents.md` matches too.

## When to use it

| Question | Use |
| --- | --- |
| How does library X implement Y? Show me the source. | **librarian** |
| Why did X change in v3? Is this a known bug? Which PR introduced it? | **librarian** |
| Is this candidate dependency safe to adopt? | **librarian**: code at the integration point, open issues, release history |
| What is the signature or option for this API call? | Read the official docs page directly: cheaper, docs are enough |
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

## Dependencies

### Required: `gh` and `git`

`gh` (authenticated) clones repositories, searches issues and PRs, and reads releases; `git` reads history and blame on the clone. Without them only the documentation paths work, and no answer can carry a permalink.

### Recommended: two MCP servers

The upstream prompt is built around two MCP servers. The agent still works without them, but falls back to slower and less precise paths.

| Server | What it gives the agent | Tools, as named in Claude Code | Fallback without it |
| --- | --- | --- | --- |
| **[Context7](https://context7.com)**: `https://mcp.context7.com/mcp` | Curated, up-to-date library documentation, indexed per library and per version, returned as focused snippets for a query | `mcp__context7__resolve-library-id` (library name → Context7 ID), `mcp__context7__query-docs` (ID + topic → doc snippets) | Find the docs site with `WebSearch` and read it page by page with `WebFetch`, or clone the repo and read the source and README. `WebFetch` returns a summary of each page rather than its raw text, so long pages and large sitemaps lose detail. |
| **[grep.app](https://grep.app)**: `https://mcp.grep.app` | Fast code search across public GitHub repositories, with regex and language filters. The agent uses it to find real-world usage of an API and to locate an implementation before cloning | `mcp__grep__searchGitHub` | `gh search code "<query>"`: GitHub's code search, with no regex, stricter rate limits, and less relevant ranking |

Both are remote servers over streamable HTTP: no local process, no install beyond `claude mcp add`. Context7 works without an account under a free rate limit; an API key from context7.com raises it, passed as a header:

```bash
claude mcp add -s user --transport http context7 https://mcp.context7.com/mcp \
  --header "CONTEXT7_API_KEY: <your-key>"
```

When Claude Code defers MCP tools behind tool search, the two servers do not appear in the agent's tool list at start. The prompt tells it to look them up with `ToolSearch` before falling back.

## Tools and model

- `model: sonnet`. Switch to `haiku` in the frontmatter for cheaper, shallower lookups.
- `Write`, `Edit`, `NotebookEdit`, and `Agent` are disallowed. It still needs `Bash` for `gh` and `git`, and Bash is not restricted, so "read-only" is a rule in its prompt, not an enforced guarantee: it clones into a fresh `mktemp -d` directory under `${TMPDIR:-/tmp}`. Your normal permission mode still applies to its Bash calls.

## Porting notes

`agent.md` is a near-verbatim port of the upstream prompt. Deviations:

- **Frontmatter** replaces the TypeScript wrapper. The upstream `description`, `keyTrigger`, `triggers`, and `useWhen` metadata are merged into `description`, plus a how-to-call line and one example. The "(Librarian - OhMyOpenCode)" branding suffix is dropped.
- **Tool restrictions** `write, edit, apply_patch, task, call_omo_agent` become `disallowedTools: Write, Edit, NotebookEdit, Agent`.
- **Model**: upstream receives it from the caller (tagged `cost: "CHEAP"`); here it is pinned to `sonnet`. `temperature: 0.1` has no Claude Code equivalent and is dropped.
- **Date awareness**: upstream interpolates the year at build time (`${new Date().getFullYear()}`). A static file cannot, so the lines say "current year" / "last year" and rely on the date in the environment context.
- **Tool names**: a mapping paragraph is added to TOOL REFERENCE (`websearch` → `WebSearch`, `webfetch` → `WebFetch`, `gh`/`git` → `Bash`). `websearch_web_search_exa(...)` in that list becomes `WebSearch(...)`. Context7 and grep.app calls are kept as written; the paragraph gives their Claude Code names (`mcp__<server>__<tool>`) and says to look for them with `ToolSearch` when they are deferred.
- **`gh` flag fixes**: `gh search prs ... --state merged` becomes `--merged`, and `gh search issues ... --state all` loses the flag (open and closed is already the default). `gh search` accepts only `open` or `closed` for `--state`, so both upstream commands fail.
- **Clone directory**: upstream clones to fixed paths (`${TMPDIR:-/tmp}/repo`, `${TMPDIR:-/tmp}/repo-name`), so parallel librarians on different libraries collided, and a stale clone from an earlier run could be read as the new one. The Temp Directory section now creates a fresh `mktemp -d` directory per run (`<run-dir>`).
- **Git working directory**: in Claude Code each Bash call starts in the caller's project, so upstream's bare `git log` / `git blame` after a clone would read the caller's repository. Every git command is now `cd <run-dir>/repo && git ...` in a single call.
- **Clone depth**: upstream used `--depth 1` and `--depth 50` with `git blame`, which attributes old lines to the shallow boundary commit. History work (TYPE C, and blame in TYPE B) now clones with `--filter=blob:none`.
- **ast-grep**: "grep or the ast-grep skill" becomes "Grep". No such skill exists in Claude Code.

Accepted limitation:

- Context7 and grep.app are not bundled. Without them, the FAILURE RECOVERY fallbacks apply.
