# shellcheck shell=bash
# The text of a shell command that the shell would run, cut into segments.
# Sourced by the catalog hook that judges a command by what it runs rather than
# by what it spells: block-worktree-refresh. Pure Bash, no external command,
# and sourcing it defines functions and constants only.
#
# `command_segments TEXT` leaves SEGMENTS holding one segment per line. A
# segment is the text between two of `;`, `&`, `|`, `(`, `)`, `` ` `` and a
# line end, with a backslash-newline continuing it, and without the comment a
# `#` beginning a word starts. What the shell would not run as a command is
# masked out before the cut: the whitespace, the `<` and the separators inside
# a quoted span become \001, so no word inside a span reaches a caller's
# pattern and no character inside one starts or ends a segment, and a heredoc
# body its command reads as data is dropped. A span or a body that a
# shell, `eval`, `source` or `.` word runs is kept as the command text it is,
# and a command substitution is kept wherever it stands. A quote or a
# substitution that cannot be paired makes the command unmodeled.
# COMMAND_MODEL is modeled only when every segment fits the reader below.
# An unmodeled command leaves its whole text unmasked for the caller's old
# whole-text judgement. Unknown programs may launch their arguments.
#
# `command_text SEGMENT` leaves COMMAND_TEXTS holding the segment from its
# executable word, after control words, assignments and launching prefixes.
# Arguments of modeled data commands do not become commands. An unmodeled
# result leaves the segment whole for the caller's text check.
#
# The helpers below leave their answers in BARE, UPTO, SUBS, OUTSIDE, MASKED
# and COMMAND_TEXTS, so a caller does not use those names for its own state.

NL=$'\n'
MASK=$'\001'
# A `#` begins a comment wherever it begins a word, which is the start of the
# line, the point after a blank, and the point after an unquoted `&`, `;`, `|`,
# a parenthesis or a backtick, since each of those ends the word before it. The
# blank and the metacharacters stand in one bracket expression so the cut lands
# on the earliest of them, not on whichever pattern a case statement reaches
# first. The result lands in BARE rather than on stdout: a command substitution
# under errexit would end the script on its own status before the caller could
# test the result.
uncommented() { # LINE -> BARE, the line without its comment
  case "$1" in
    \#*) BARE="" ;;
    *[[:blank:]\&\;\|\(\)\`]\#*) BARE=${1%%[[:blank:]\&\;\|\(\)\`]\#*} ;;
    *) BARE=$1 ;;
  esac
}
# GitHub and Linear script arguments are data even when the script name
# ends in `sh`. Only an interpreter in executable position runs shell text.
SHELL_RE='^(sh|bash|dash|ash|zsh|ksh|fish)$'
# A word standing immediately after a redirection operator is a file the shell
# opens, never the command it runs, so `cat > script.sh` names no shell. The
# operator takes an optional file descriptor digit in front of it.
REDIRECT_RE='[0-9]?(>>|>|<)[[:blank:]]*[^[:space:]]+'
# Keep quotes until executable selection: a quoted control word is a command
# name. Strip them from the selected name so `"/bin/bash"` still names a shell.
# Redirection targets never name an interpreter.
runs_shell_text() { # TEXT [stdin] -> 0 when its executable runs shell text
  local bare=$1 word raw rest mode=${2:-span} operand="" options=1 stdin=""
  case "$bare" in *\<\<\<*) mode=stdin ;; esac
  while [[ $bare =~ $REDIRECT_RE ]]; do
    bare=${bare/"${BASH_REMATCH[0]}"/ }
  done
  command_text "$bare" shell
  word=${COMMAND_TEXTS%%[[:space:]]*}
  rest=${COMMAND_TEXTS#"$word"}
  word=${word//[\'\"]/}
  word=${word##*/}
  case "$word" in eval | source | .) return 0 ;; esac
  [[ $word =~ $SHELL_RE ]] || return 1
  while :; do
    rest=${rest#"${rest%%[![:space:]]*}"}
    [ -n "$rest" ] || { [ "$mode" = stdin ]; return; }
    raw=${rest%%[[:space:]]*}
    rest=${rest#"$raw"}
    raw=${raw//[\'\"]/}
    if [ -n "$operand" ]; then
      operand=""
      continue
    fi
    case "$raw" in
      --*) ;;
      -*s*) stdin=1 ;;
      +*s*) stdin="" ;;
    esac
    case "$raw" in
      -- | -) options="" ;;
      --rcfile | --init-file) operand=1 ;;
      --*) ;;
      -*c*)
        # Options after -c can precede its command operand. This reader only
        # models a command operand immediately after that option.
        [ -z "${rest//[[:space:]]/}" ] || COMMAND_MODEL=unmodeled
        [ -z "${rest//[[:space:]]/}" ]; return ;;
      [-+]*[oO]) operand=1 ;;
      [-+]*) ;;
      *) [ -n "$stdin" ] && [ "$mode" = stdin ]; return ;;
    esac
    if [ -z "$options" ]; then
      if [ -n "$stdin" ]; then
        [ "$mode" = stdin ]
      else
        [ "$mode" = stdin ] && [ -z "${rest//[[:space:]]/}" ]
      fi
      return
    fi
  done
}
# A `<<` or `<<-` with only blanks after it takes the next span as its heredoc
# delimiter, a word the shell does not run. `<<<` is a here-string, and the
# word after it is one the shell does run.
DELIM_TAIL_RE='(^|[^<])<<-?[[:space:]]*$'
# The first character of CHARS that the shell reads as a boundary rather than
# as itself: one carrying an odd number of backslashes in front of it is a
# literal character the shell hands on as an argument, so it opens and closes
# nothing. Two of those pairing with each other is what would hide the command
# between them. UPTO holds the text before the boundary; a status of 1 says the
# text holds no boundary at all.
upto_unescaped() { # TEXT CHARS -> 0 with UPTO set, 1 when every one is escaped
  local rest=$1 chars=$2 piece slashes
  UPTO=""
  while :; do
    case "$rest" in
      *[$chars]*) ;;
      *) return 1 ;;
    esac
    piece=${rest%%[$chars]*}
    rest=${rest#"$piece"}
    slashes=${piece##*[!\\]}
    if [ $((${#slashes} % 2)) -eq 0 ]; then
      UPTO=$UPTO$piece
      return 0
    fi
    UPTO=$UPTO$piece${rest:0:1}
    rest=${rest:1}
  done
}
# A command substitution is command text wherever it stands: the shell expands
# and runs it before the command around it reads anything, so one inside a
# double-quoted argument or inside a heredoc body the shell expands runs just
# the same. SUBS holds each one's text, opened as its own command position with
# its whitespace intact; OUTSIDE holds what is left for the caller to mask or
# to drop. A substitution that does not close is text the reader could not
# read, and the caller is told, as it is for a quote that does not pair.
lift_substitutions() { # TEXT -> 0 with SUBS and OUTSIDE set, 1 when one does not close
  local rest=$1 head open body depth piece
  SUBS=""
  OUTSIDE=""
  while :; do
    upto_unescaped "$rest" '$`' || { OUTSIDE=$OUTSIDE$rest; return 0; }
    head=$UPTO
    rest=${rest#"$head"}
    open=${rest:0:1}
    OUTSIDE=$OUTSIDE$head
    # A `$` that no `(` follows names a parameter, which the shell expands
    # without running anything.
    if [ "$open" = '$' ] && [ "${rest:1:1}" != '(' ]; then
      OUTSIDE=$OUTSIDE$open
      rest=${rest:1}
      continue
    fi
    if [ "$open" = '`' ]; then
      rest=${rest:1}
      upto_unescaped "$rest" '`' || return 1
      body=$UPTO
      rest=${rest#"$body"}
      rest=${rest:1}
    else
      # The parentheses are counted, so a substitution holding another one
      # closes where it really closes.
      rest=${rest:2}
      depth=1
      body=""
      while :; do
        upto_unescaped "$rest" '()' || return 1
        piece=$UPTO
        rest=${rest#"$piece"}
        if [ "${rest:0:1}" = ')' ]; then
          depth=$((depth - 1))
          if [ "$depth" -eq 0 ]; then
            body=$body$piece
            rest=${rest:1}
            break
          fi
        else
          depth=$((depth + 1))
        fi
        body=$body$piece${rest:0:1}
        rest=${rest:1}
      done
    fi
    SUBS=$SUBS$NL$body$NL
  done
}
# The separator characters. A bracket expression's members carry no order, and
# the ampersand stands before the semicolon here so the two do not spell the
# Bash 4 case terminator that tools/bash32-lint reads.
SEP='[&;|()`'$NL']'
# What a quoted span the shell does not run has masked: its whitespace, so no
# word inside it reads as a word of the command; its `<`, so a `<<` written in
# it arms no heredoc; and the separators, so a `(` or a `;` written in it
# neither opens a command position for the next span nor cuts the segment.
SPAN_MASK='[[:space:]<&;|()`]'
# Quotes preserve data arguments as one word. Only text supplied to a shell
# interpreter, eval, source or dot opens a command position.
#
# Each quoted span keeps its quotes, since a command word may be quoted whole
# (`"/path/kendex" refresh`), while the characters SPAN_MASK names inside it
# are masked. A span the shell does run — the argument of a shell, `eval`,
# `source` or `.` word in the same segment — is opened as its own command
# position with its whitespace intact. A quote the shell hands on as a
# literal argument is not a boundary and opens no span, which is what keeps two
# escaped quotes from pairing around a real command. MASKED holds the result; a
# quote that still does not pair is a span the reader could not read, and the
# caller is told.
mask_spans() { # TEXT -> 0 with MASKED set, 1 when a quote does not pair
  local rest=$1 head quote span before out=""
  while :; do
    upto_unescaped "$rest" "'\"" || { MASKED=$out$rest; return 0; }
    head=$UPTO
    rest=${rest#"$head"}
    quote=${rest:0:1}
    rest=${rest:1}
    # A backslash inside a single-quoted span is a plain character, so only a
    # double-quoted span's closing quote can be escaped.
    if [ "$quote" = "'" ]; then
      case "$rest" in
        *\'*) span=${rest%%\'*} ;;
        *) return 1 ;;
      esac
    else
      upto_unescaped "$rest" '"' || return 1
      span=$UPTO
    fi
    rest=${rest#"$span$quote"}
    out=$out$head
    before=${out##*$SEP}
    if [[ $before =~ $DELIM_TAIL_RE ]] || ! runs_shell_text "$before"; then
      # A single-quoted span expands nothing, so all of it is masked; a
      # double-quoted one has its substitutions lifted out first.
      if [ "$quote" = "'" ]; then
        out=$out$quote${span//$SPAN_MASK/$MASK}$quote
      else
        lift_substitutions "$span" || return 1
        out=$out$quote${OUTSIDE//$SPAN_MASK/$MASK}$quote$SUBS
      fi
    else
      out=$out$NL$span$NL
    fi
  done
}
# The heredoc bodies. The shell feeds a body to a command rather than running
# it, so the body goes, unless that command is one that runs shell text and the
# body is the command text it runs. The `<<` is read off the line with its
# comment dropped and its quoted spans masked, so a `<<` only written down does
# not arm one. A body is dropped only once its terminator line is found: an
# unterminated body is text the reader could not read, and dropping it would
# take the rest of the command with it. Each segment then loses its comment.
command_segments() { # TEXT -> SEGMENTS, one segment per line
  local joined=${1//\\$NL/ } line index count delim expands end term judged="" cut
  local lines
  COMMAND_MODEL=modeled
  lines=()
  while IFS= read -r line; do
    lines[${#lines[@]}]=$line
  done <<EOF
$joined
EOF
  index=0
  count=${#lines[@]}
  while [ "$index" -lt "$count" ]; do
    line=${lines[$index]}
    judged=$judged$line$NL
    index=$((index + 1))
    uncommented "$line"
    if mask_spans "$BARE"; then
      BARE=$MASKED
    fi
    # Descriptor duplication is not a command separator. Cutting its &
    # would lose the following executable, so the complete text falls back.
    case "$BARE" in *[\<\>]\&*) COMMAND_MODEL=unmodeled ;; esac
    [[ $BARE =~ (^|[^<])\<\<-?[[:space:]]*([^[:space:]\<][^[:space:]]*) ]] || continue
    delim=${BASH_REMATCH[2]}
    # A later command can consume this body through a pipe or a command
    # list. Only a heredoc on one simple command is modeled.
    case "$BARE" in *$SEP*) COMMAND_MODEL=unmodeled ;; esac
    # `<<'EOF'` and `<<"EOF"` name the same delimiter as `<<EOF`, but a quoted
    # delimiter stops the shell expanding the body, so nothing in that body runs.
    expands=1
    case "$delim" in
      \'*\' | \"*\") delim=${delim:1:${#delim} - 2}; expands="" ;;
    esac
    end=$index
    while [ "$end" -lt "$count" ]; do
      term=${lines[$end]}
      [ "${term#"${term%%[![:space:]]*}"}" = "$delim" ] && break
      end=$((end + 1))
    done
    [ "$end" -lt "$count" ] || { COMMAND_MODEL=unmodeled; continue; }
    if runs_shell_text "$BARE" stdin; then
      while [ "$index" -lt "$end" ]; do
        judged=$judged${lines[$index]}$NL
        index=$((index + 1))
      done
    elif [ -n "$expands" ]; then
      # The body itself is data, but the shell expands it before the command
      # reads it, so a command substitution inside it runs. A line holding one
      # the reader cannot close is kept whole rather than dropped.
      while [ "$index" -lt "$end" ]; do
        if lift_substitutions "${lines[$index]}"; then
          judged=$judged$SUBS
        else
          COMMAND_MODEL=unmodeled
          judged=$judged${lines[$index]}$NL
        fi
        index=$((index + 1))
      done
    fi
    index=$((end + 1))
  done
  # A quote the reader could not pair leaves the original text to be cut
  # whole, the reach a caller's patterns had before any span was read.
  if mask_spans "$judged"; then
    cut=$MASKED
  else
    COMMAND_MODEL=unmodeled
    cut=$joined
  fi
  cut_segments "$cut"
  # One fallback covers every form the reader cannot model completely.
  if [ "$COMMAND_MODEL" = unmodeled ]; then
    cut_segments "$joined" fallback
  fi
}
cut_segments() { # TEXT [fallback] -> SEGMENTS
  local cut=$1 line out=""
  cut=${cut//;/$NL}
  cut=${cut//&/$NL}
  cut=${cut//\|/$NL}
  cut=${cut//\(/$NL}
  cut=${cut//\)/$NL}
  cut=${cut//\`/$NL}
  while IFS= read -r line; do
    if [ "${2:-}" = fallback ]; then
      BARE=$line
    else
      uncommented "$line"
      command_text "$BARE"
    fi
    out=$out$BARE$NL
  done <<EOF
$cut
EOF
  SEGMENTS=$out
}
# The executable of a simple command. Assignments and redirections are the
# shell's, and launching prefixes consume their own options before the child
# executable. Shell control words also introduce a command, but only when
# unquoted and without a path. An option value named `kendex` is never that child.
# These prefixes occur in tool commands judged by block-worktree-refresh;
# Only a modeled invocation keeps its remaining words as arguments.
command_text() { # SEGMENT -> COMMAND_TEXTS
  local rest=$1 word raw name data launcher="" operand="" options=1
  COMMAND_TEXTS=""
  if [ "${COMMAND_MODEL:-modeled}" = unmodeled ]; then
    COMMAND_TEXTS=$1
    return 0
  fi
  while :; do
    rest=${rest#"${rest%%[![:space:]]*}"}
    [ -n "$rest" ] || return 0
    word=${rest%%[[:space:]]*}
    raw=$word
    word=${word//[\'\"]/}
    if [ -n "$operand" ]; then
      operand=""
    elif [[ $word =~ ^[0-9]*[\<\>] ]]; then
      [[ $word =~ ^[0-9]*[\<\>]+$ ]] && operand=1
    elif [ -n "$launcher" ] && [ -n "$options" ] && [ "$word" = -- ]; then
      options=""
    elif [ -n "$launcher" ] && [ -n "$options" ] && [[ $word == -* ]]; then
      case "$launcher:$word" in
        command:-v | command:-V) return 0 ;;
        command:-p | env:-i | env:--ignore-environment | sudo:-E | exec:-c | exec:-l | exec:-cl | time:-p) ;;
        env:--unset | env:--chdir | env:-u | env:-C | env:-iC | sudo:--user | sudo:--group | sudo:--host | sudo:--prompt | sudo:--chdir | sudo:--chroot | sudo:--role | sudo:--type | sudo:--other-user | sudo:--close-from | sudo:-u | sudo:-g | sudo:-h | sudo:-p | sudo:-D | sudo:-ED | sudo:-R | sudo:-r | sudo:-t | sudo:-U | sudo:-C | timeout:--signal | timeout:--kill-after | timeout:-s | timeout:-k | exec:-a | exec:-cla) operand=1 ;;
        env:--unset=* | env:--chdir=*) ;;
        *) COMMAND_MODEL=unmodeled; COMMAND_TEXTS=$1; return 0 ;;
      esac
    elif [ "$launcher" = timeout ]; then
      # timeout's duration precedes the child command.
      launcher=""
      options=1
    elif [ "$launcher" = time ]; then
      launcher=""
      options=1
      continue
    elif [[ $word =~ ^[[:alpha:]_][[:alnum:]_]*= ]] && { [ -z "$launcher" ] || [ "$launcher" = env ]; }; then
      :
    elif [ "$raw" = "$word" ] && [ -z "$launcher" ] && [[ $word =~ ^(if|elif|then|else|while|until|do|!|\{|co[p]roc)$ ]]; then
      :
    elif [ "$raw" = time ] && [ -z "$launcher" ]; then
      launcher=time
      options=1
    else
      name=${word##*/}
      case "$name" in
        env | command | sudo | timeout | exec)
          launcher=$name
          options=1
          ;;
        eval)
          case "${rest#"$raw"}" in *[[:space:]]--*) COMMAND_MODEL=unmodeled ;; esac
          if [ "${2:-}" = shell ]; then
            COMMAND_TEXTS=$rest
            return 0
          fi
          launcher=""
          options=1
          ;;
        kendex | sh | bash | dash | ash | zsh | ksh | fish | source | .)
          COMMAND_TEXTS=$rest
          return 0
          ;;
        git | gh)
          # Commit messages and PR/issue creation fields are data. Other git
          # and gh commands can run arguments, aliases or configured commands.
          # Their executable name alone proves no argument contract.
          case "$name" in
            git) data='^[[:space:]]+commit([[:space:]]|$)' ;;
            gh) data='^[[:space:]]+(pr|issue)[[:space:]]+create([[:space:]]|$)' ;;
          esac
          if [[ ${rest#"$raw"} =~ $data ]]; then
            COMMAND_TEXTS=$rest
          else
            COMMAND_MODEL=unmodeled
            COMMAND_TEXTS=$1
          fi
          return 0
          ;;
        # These tool commands consume arguments as data. The catalog GitHub
        # and Linear CLIs and dev return writer have the same contract.
        echo | printf | cat | pwd | cd | pushd | true | false | : | github.sh | linear.sh | dev-return-write)
          COMMAND_TEXTS=$rest
          return 0
          ;;
        'fi' | 'done' | 'esac' | \})
          return 0
          ;;
        *)
          COMMAND_MODEL=unmodeled
          COMMAND_TEXTS=$1
          return 0
          ;;
      esac
    fi
    rest=${rest#"$raw"}
  done
}
