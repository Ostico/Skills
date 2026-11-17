"""Run aider as `aider` would, with one change: a file the model names in its reply is never
added to the chat.

With --yes-always aider answers yes to "Add file to the chat?" for any repo file the reply
names (in its reasoning too), then returns before applying the reply's edits and sends a second
turn; the model answers that turn with a short "Ok" and the first reply's edits are lost
(aider 0.86, base_coder.send_message). Declining keeps the edits: aider remembers the file as
ignored and applies the reply. Every other question keeps its --yes-always answer.

Run with aider's own Python (the interpreter on the first line of the `aider` script):
    <aider python> aider_entry.py <aider arguments>
"""
import sys

from aider import io as aider_io

_confirm_ask = aider_io.InputOutput.confirm_ask


def confirm_ask(self, question, *args, **kwargs):
    if question.startswith("Add file to the chat?"):
        self.tool_output(f"ltw: not adding {kwargs.get('subject', '?')} to the chat (the reply "
                         "named it; adding it would drop the reply's edits)")
        return False
    return _confirm_ask(self, question, *args, **kwargs)


aider_io.InputOutput.confirm_ask = confirm_ask

from aider.main import main  # noqa: E402  (after the patch, so every coder sees it)

sys.exit(main())
