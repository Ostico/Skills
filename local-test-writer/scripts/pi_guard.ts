// pi extension for run_aider_tests.sh --agent pi: the model may edit and write only the --write
// files (PI_WRITE, comma separated, relative to the repo root; the runner normalizes them), and
// the run stops at the first tool call after PI_MAX_TURNS turns, so the server gets up to
// PI_MAX_TURNS + 1 requests. A refused call goes back to the model with the reason, and one line
// to stderr ("pi-guard: ..."), which pi_run.py counts; pi_run.py knows the two reasons below, so
// keep them in step. The runner's own guard still undoes anything that gets past this one.
import * as path from "node:path";

export default function (pi: any) {
  const root = process.cwd();
  const allowed = new Set(
    (process.env.PI_WRITE ?? "").split(",").filter(Boolean).map((p) => path.resolve(root, p)),
  );
  const maxTurns = Number(process.env.PI_MAX_TURNS ?? "40");
  let turns = 0;

  pi.on("turn_end", async () => {
    turns += 1;
  });

  pi.on("tool_call", async (event: any) => {
    if (turns >= maxTurns) {
      console.error(`pi-guard: turn limit ${maxTurns} reached, stopping`);
      return { block: true, reason: `turn limit ${maxTurns} reached`, terminate: true };
    }
    if (event.toolName !== "edit" && event.toolName !== "write") return;
    const raw = String(event.input?.path ?? "").replace(/^@/, "");
    if (!allowed.has(path.resolve(root, raw))) {
      console.error(`pi-guard: blocked ${event.toolName} on ${raw}`);
      const names = [...allowed].map((p) => path.relative(root, p)).join(", ");
      return { block: true, reason: `only these files may be changed: ${names}` };
    }
  });
}
