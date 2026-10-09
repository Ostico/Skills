# beta-tester credentials helper — source it, never execute it, never print what it reads.
#
#   . "<skill dir>/scripts/beta-env.sh" || exit 1
#
# Shell state does not survive between tool calls, so source it at the start of EVERY command that
# needs a credential. Works in bash and zsh. Sourcing it:
#
#   1. resolves the credentials file from the current directory; the first rule that applies wins,
#      and a file missing where it points is an error, never a fall-through to the next rule:
#        $BETA_TESTER_ENV                  when set
#        <git common dir>/beta-tester.env  inside a git repo (every worktree shares the main .git)
#        $HOME/.beta-tester.env            outside any git repo
#   2. refuses a file that is missing, or that grants any permission to group or others (the
#      symlink target's mode is what counts)
#   3. defines:
#        beta_personas   one line per usable persona: its name, then UI when _EMAIL and _PASSWORD
#                        are both set, API when _API_TOKEN is — e.g. "DEFAULT UI API"
#        beta_has KEY    silent: succeeds when KEY is set, prints nothing
#        beta_val KEY    the value of KEY, unquoted; fails when it is not set
#
# "Set" means not blank, not whitespace only, and not a placeholder left over from an older copy
# of the example file (change-me, an @example.com address).
#
# Nothing in the credentials file is ever executed: it is parsed, not sourced.

_beta_in_git=
if [ -n "${BETA_TESTER_ENV:-}" ]; then
  BETA_ENV_FILE=$BETA_TESTER_ENV
elif _beta_git=$(command git rev-parse --git-common-dir 2>/dev/null); then
  _beta_in_git=1
  # --git-common-dir may be relative to the current directory; make it absolute. CDPATH is
  # cleared so a relative ".git" can't resolve against it.
  BETA_ENV_FILE=$(CDPATH= cd -- "$_beta_git" 2>/dev/null && pwd -P)/beta-tester.env
else
  BETA_ENV_FILE=$HOME/.beta-tester.env
fi
unset _beta_git

if [ ! -f "$BETA_ENV_FILE" ]; then
  echo "beta-tester: credentials file not found: $BETA_ENV_FILE" >&2
  echo "beta-tester: create it from assets/credentials.env.example, chmod 0600" \
    "(see references/accounts-and-credentials.md)" >&2
  if [ -n "$_beta_in_git" ] && [ -f "$HOME/.beta-tester.env" ]; then
    echo "beta-tester: $HOME/.beta-tester.env is not read inside a git repo; move it here," \
      "or set BETA_TESTER_ENV to it" >&2
  fi
  unset _beta_in_git
  return 1 2>/dev/null || exit 1
fi

_beta_perm=$(stat -L -c '%a' "$BETA_ENV_FILE" 2>/dev/null || stat -L -f '%Lp' "$BETA_ENV_FILE")
if [ -z "$_beta_perm" ] || (( 8#$_beta_perm & 8#077 )); then
  echo "beta-tester: refusing $BETA_ENV_FILE (mode ${_beta_perm:-unknown}); run: chmod 0600 $BETA_ENV_FILE" >&2
  return 1 2>/dev/null || exit 1
fi
unset _beta_perm _beta_in_git

# Key/value lines only, `export ` and indentation stripped.
_beta_lines() {
  command grep -E '^[[:space:]]*(export[[:space:]]+)?BETA_TESTER_[A-Z0-9_]+=' "$BETA_ENV_FILE" \
    | command sed -E 's/^[[:space:]]*(export[[:space:]]+)?//'
}

# The value of KEY: the last line wins, trailing whitespace (a CRLF file's \r included) is
# dropped, then one pair of surrounding quotes. Empty when KEY is not set.
_beta_get() {
  _beta_v=$(_beta_lines | command grep -E "^$1=" | command tail -n 1 \
    | command sed -E "s/^[^=]*=//; s/[[:space:]]+\$//; s/^\"(.*)\"\$/\1/; s/^'(.*)'\$/\1/")
  case $_beta_v in
    *[![:space:]]*) ;;
    *) _beta_v= ;;
  esac
  case $_beta_v in
    change-me | *@example.com) _beta_v= ;;
  esac
}

beta_has() {
  _beta_get "$1"
  [ -n "$_beta_v" ]
  _beta_rc=$?
  unset _beta_v
  return $_beta_rc
}

beta_personas() {
  _beta_lines \
    | command sed -nE 's/^BETA_TESTER_([A-Z0-9_]+)_(EMAIL|PASSWORD|API_TOKEN)=.*/\1/p' \
    | command sort -u \
    | while IFS= read -r _beta_n; do
        _beta_c=
        if beta_has "BETA_TESTER_${_beta_n}_EMAIL" && beta_has "BETA_TESTER_${_beta_n}_PASSWORD"; then
          _beta_c=" UI"
        fi
        if beta_has "BETA_TESTER_${_beta_n}_API_TOKEN"; then
          _beta_c="$_beta_c API"
        fi
        if [ -n "$_beta_c" ]; then
          printf '%s%s\n' "$_beta_n" "$_beta_c"
        fi
      done
  unset _beta_n _beta_c
  return 0
}

beta_val() {
  _beta_get "$1"
  if [ -z "$_beta_v" ]; then
    echo "beta-tester: $1 is not set in $BETA_ENV_FILE" >&2
    unset _beta_v
    return 1
  fi
  printf '%s' "$_beta_v"
  unset _beta_v
}
