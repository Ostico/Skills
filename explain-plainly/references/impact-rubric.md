# Impact Rubric

Read before writing the **Real impact** section. Purpose: stop a claimed impact from being reported as a real one.

## Contents

- [False-impact catalogue](#false-impact-catalogue) — ten patterns that read as important and are not
- [Magnitude grounding](#magnitude-grounding) — turning claims into the target's units
- [Reachability test](#reachability-test) — proving the change can touch the target
- [Severity scale](#severity-scale) — the words to use for the verdict
- [Per-subject playbooks](#per-subject-playbooks) — what to check per kind of subject

## False-impact catalogue

Check the subject against each. A hit does not mean zero impact — it means the impact is conditional, and the condition must be stated.

1. **Behind a flag / opt-in.** Ships disabled. Impact is zero until someone enables it. Verify the default in the code or config, not in the prose.
2. **Benchmark on a path the target does not run.** A 40% gain in a code path nobody calls is 0% end to end. Amdahl applies: gain is capped by that path's share of total time.
3. **Deprecation with no removal date.** A warning is not a break. Real impact = log noise now, work later. Find the removal version if one exists; if not, say so.
4. **Breaking change in an unused API.** Breaking is a property of the caller, not the release. No call site, no break.
5. **Version-number theater.** A major bump can be a license change or a dropped platform; a patch can contain a behavior change. Read the diff, not the semver.
6. **Impact conditional on scale the target lacks.** "Critical at 10k req/s" is irrelevant at 10 req/s. Check the actual numbers.
7. **Fix for a bug never hit.** Confirm the target's usage actually triggers the old bug before calling the fix valuable.
8. **"Up to X%".** Best case under ideal conditions. Typical case is usually far lower and often unstated. Never quote the ceiling as the expectation.
9. **Vulnerability that is not reachable.** A CVE in a code path the target never invokes, or requiring an attacker position they cannot reach (local access on a single-user box, a parser fed only trusted input), is severity-on-paper. Still worth patching cheaply; not worth an incident.
10. **Cost stated without the baseline.** "Saves $200/mo" matters at a $500 bill, disappears at a $500k one. Get the denominator.

Mirror trap — do not under-call these, they are genuinely real: silent default changes, behavior changes with no error raised, anything touching auth/authz or data durability, migrations that cannot be rolled back, changes to shared/global state, and anything that alters what gets written to disk or logs.

## Magnitude grounding

- Convert every relative number to an absolute in units the target feels: ms, req/s, MB, dollars/month, rows, files to edit, hours of work.
- Always report the base alongside the delta. `x% of y` with y unnamed is not information.
- Compare against the target's actual pain: if p99 latency is 900 ms and the change saves 3 ms, the honest word is "invisible."
- Frequency multiplies magnitude. A 5-minute manual step is trivial once a year and severe hourly.
- One-time cost vs recurring cost are different currencies. Label which.

## Reachability test

Prove the path, do not assume it:

- Grep for the affected symbol, endpoint, config key, or CLI flag in the target's code.
- Check the installed version actually contains the change (lockfile, `--version`, vendored source), not just the latest release notes.
- Check the flag/default in the shipped artifact.
- For a vulnerability: who must the attacker be, and can they be that here?

Report the evidence in one clause — `no call sites for parseUnsafe() in src/` — not as a bare assertion.

## Severity scale

Pick one, say why in the same breath:

| Word | Means |
| --- | --- |
| **Breaks you** | Will fail on upgrade or already failing. Action required now. |
| **Bites later** | Works today, fails at a named future point (removal version, scale threshold, expiry date). |
| **Marginal** | Real but small enough to ignore without consequence. Quantify it. |
| **Invisible** | Real in the artifact, unreachable or immeasurable here. |
| **No impact** | Does not apply to the target at all. State the reason. |

## Per-subject playbooks

**Code or diff** — What behavior differs before vs after, for which inputs? What was silently changed (defaults, error handling, ordering, types)? Who calls it? Does any test cover the new path? Is any observable contract (API shape, log format, on-disk data) altered?

**Error or stack trace** — The real failing line, not the top frame. What state produced it. Whether it is a symptom of an earlier fault. Whether it is fatal, retried, or swallowed. How often it fires — once, or every request.

**Dependency bump or CVE** — Diff the actual changelog between the two installed versions. Reachability of the fixed code path. Transitive impact and lockfile churn. Whether the fix forces other upgrades. For a CVE: attack prerequisites, not just the CVSS number.

**Release notes / announcement / RFC** — Separate what shipped from what is planned. Find the defaults. Find what is deprecated and its removal date. Identify which listed items touch anything the target uses — usually a small subset. Note what the announcement conspicuously omits (migration cost, pricing, limits).

**Config change** — Old value vs new value vs default. What reads this key at runtime, and does it reload or require restart? Blast radius across environments. Failure mode if the value is wrong — loud or silent?

**Benchmark output** — What was measured, on what hardware, with what warmup and how many runs. Variance, not just the mean. Whether the measured path matches production shape. Whether the comparison is like-for-like.

**Architecture proposal** — The problem it claims to solve, and whether the target actually has that problem now. What it makes harder (there is always something). Migration cost and rollback story. What the simplest alternative would be, and why it was rejected.

**Contract or policy text** — Obligations created, on whom, with what deadline. Termination, liability, and auto-renewal clauses. What changed from the prior version. What is silently absent. Flag that this is a reading, not legal advice, and name the clause worth a lawyer's time if any.
