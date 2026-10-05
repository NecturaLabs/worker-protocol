# Shared helpers for the protocol scripts. Sourced, not run.

# Print the run directory's layout paths for a label: sets worker, contract and answers.
# shellcheck disable=SC2034 # the variables are read by the calling script
paths() { # dir, label
  worker="$1/workers/$2.md"
  contract="$1/contracts/$2.md"
  answers="$1/answers/$2.md"
}

valid_label() { # label
  case $1 in
    "" | *[!a-z0-9-]*) echo "label must match [a-z0-9-]+: $1" >&2; return 1 ;;
  esac
}

valid_count() { # value, what (at most 9 digits, so every shell can compare it)
  case $1 in
    "" | *[!0-9]*) echo "$2 must be a whole number: $1" >&2; return 1 ;;
    ??????????*) echo "$2 is too large (at most 9 digits): $1" >&2; return 1 ;;
  esac
}

# Print a file without a last line that has no newline yet: a write still in progress.
complete_lines() { # file
  if [ -n "$(tail -c 1 "$1")" ]; then sed '$d' "$1"; else cat "$1"; fi
}

# One line of free text: newlines become spaces, so a field can never start a heading.
one_line() { # text
  printf '%s' "$1" | tr '\n' ' '
}

# Multi-line free text: a line starting with '#' is indented, so it can never start a heading.
no_headings() { # text
  printf '%s\n' "$1" | sed 's/^#/ #/'
}

# Print one line per question ("Q <n> <mode>") and per result ("R <status>") in a worker file.
# A status other than COMPLETE, PARTIAL or BLOCKED is reported as INVALID. A last line without its
# newline is still being written and is left for the next scan, unless the second argument is
# "all" (a checkpoint, where nothing is being written).
scan_worker() { # file, [all]
  if [ "${2:-}" = all ]; then cat "$1"; else complete_lines "$1"; fi | awk '
    function flush() { if (q != "") { print "Q", q, mode; q = "" } }
    /^## Q[0-9]+$/ { flush(); q = substr($0, 5); mode = "UNSPECIFIED"; next }
    q != "" && /^\*\*Mode:\*\*/ { m = $0; sub(/^\*\*Mode:\*\*[ \t]*/, "", m); mode = m; next }
    /^## / { flush() }
    /^## Result$/ { res = 1; next }
    res && /^\*\*Status:\*\*/ {
      s = $0; sub(/^\*\*Status:\*\*[ \t]*/, "", s); sub(/[ \t]+$/, "", s)
      if (s !~ /^(COMPLETE|PARTIAL|BLOCKED)$/) s = "INVALID"
      print "R", s; res = 0
    }
    END { flush() }
  '
}

# True when answers file $1 holds answer A<n>.
answered() { # answers-file, n
  [ -f "$1" ] && grep -qx "## A$2" "$1"
}

# Print a worker file's decisions (kind D) or deferred items (kind F): every line starting
# "<kind><n>:" anywhere in the file, plus the unnumbered non-empty lines under a "## Decisions" or
# "## Deferred" heading, which may repeat. A numbered line always counts as its own kind.
entries() { # file, D|F
  awk -v k="$2" '
    BEGIN { h = (k == "D") ? "## Decisions" : "## Deferred"; re = "^" k "[0-9]+:" }
    $0 == h { on = 1; next }
    /^## / { on = 0 }
    $0 ~ re || (on && NF && $0 !~ /^[DF][0-9]+:/) { print }
  ' "$1"
}

# Hold a lock directory while running a command and return its status. INT, TERM and HUP release
# the lock; only a process killed outright (SIGKILL, power loss) can leave it behind, and the next
# caller then stops after 30 seconds and names the dead holder. Never taken over automatically: two
# waiters could both take it.
with_lock() { # lockdir, command...
  lock=$1
  shift
  tries=0
  until mkdir "$lock" 2>/dev/null; do
    tries=$((tries + 1))
    if [ "$tries" -ge 30 ]; then
      holder=$(cat "$lock/pid" 2>/dev/null || true)
      if [ -n "$holder" ] && ! kill -0 "$holder" 2>/dev/null; then
        echo "$lock is held by process $holder, which is no longer running: remove the directory and retry" >&2
      else
        echo "could not take $lock within 30 seconds (held by ${holder:-an unknown process})" >&2
      fi
      return 1
    fi
    sleep 1
  done
  trap 'rm -f "$lock/pid"; rmdir "$lock" 2>/dev/null; exit 130' INT TERM HUP
  echo "$$" > "$lock/pid"
  rc=0
  "$@" || rc=$?
  rm -f "$lock/pid"
  rmdir "$lock"
  trap - INT TERM HUP
  return "$rc"
}
