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

# Print one line per question ("Q <n> <mode>") and per result ("R <status>") in a worker file.
scan_worker() { # file
  awk '
    function flush() { if (q != "") { print "Q", q, mode; q = "" } }
    /^## Q[0-9]+$/ { flush(); q = substr($0, 5); mode = "UNSPECIFIED"; next }
    q != "" && /^\*\*Mode:\*\*/ { m = $0; sub(/^\*\*Mode:\*\*[ \t]*/, "", m); mode = m; next }
    /^## / { flush() }
    /^## Result$/ { res = 1; next }
    res && /^\*\*Status:\*\*/ { s = $0; sub(/^\*\*Status:\*\*[ \t]*/, "", s); print "R", s; res = 0 }
    END { flush() }
  ' "$1"
}

# True when answers file $1 holds answer A<n>.
answered() { # answers-file, n
  [ -f "$1" ] && grep -qx "## A$2" "$1"
}

# Print the non-empty lines of every section with heading $2 in file $1.
section() { # file, heading
  awk -v h="$2" '$0 == h { on = 1; next } /^## / { on = 0 } on && NF { print }' "$1"
}
