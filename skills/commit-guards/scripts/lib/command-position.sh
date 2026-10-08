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
# Optional command-local results are advertised by COMMAND_SEGMENTS_API.
# SEGMENT_TEXTS, SEGMENT_COMMANDS, SEGMENT_MODELS and SEGMENT_CAUSES hold answers for
# each simple command. A modeled command keeps its argument contract even
# when a neighboring command is unmodeled. Unsupported commands keep raw
# text within their own boundaries. Unknown programs may launch arguments.
#
# `command_text SEGMENT` keeps the published executable-candidate contract:
# COMMAND_TEXTS holds each remaining word and its suffix, one per line, after
# assignments. The command-local reader uses command_position to select the
# executable and report whether the argument contract is modeled.
#
# The helpers below leave their answers in BARE, UPTO, SUBS, OUTSIDE, MASKED
# UNMASKED and COMMAND_TEXTS, so a caller does not use those names for its own state.

COMMAND_SEGMENTS_API=command-local-v1
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
  if [ "$mode" = published ]; then
    # Published scalar consumers have no unsupported-command result. Retain
    # their conservative shell-input projection through candidate suffixes.
    command_text "$bare"
    while IFS= read -r rest; do
      word=${rest%%[[:space:]]*}
      word=${word//[\'\"]/}
      case "${word##*/}" in *sh | eval | source | .) return 0 ;; esac
    done <<EOF
$COMMAND_TEXTS
EOF
    return 1
  fi
  command_position "$bare" shell
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
        [ -z "${rest//[[:space:]]/}" ] || { COMMAND_MODEL=unmodeled; COMMAND_CAUSE=shell-options; }
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
  local rest=$1 head quote span before out="" original=""
  while :; do
    upto_unescaped "$rest" "'\"" || { MASKED=$out$rest; UNMASKED=$original$rest; return 0; }
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
    original=$original$head
    before=${out##*$SEP}
    if [ "${2:-}" = boundaries ] || [[ $before =~ $DELIM_TAIL_RE ]] || ! runs_shell_text "$before" "${2:-span}"; then
      # A single-quoted span expands nothing, so all of it is masked; a
      # double-quoted one has its substitutions lifted out first.
      if [ "$quote" = "'" ]; then
        out=$out$quote${span//$SPAN_MASK/$MASK}$quote
        original=$original$quote$span$quote
      else
        if [ "${2:-}" = boundaries ]; then
          OUTSIDE=$span
          SUBS=""
        else
          lift_substitutions "$span" || return 1
        fi
        original=$original$quote$OUTSIDE$quote$SUBS
        out=$out$quote${OUTSIDE//$SPAN_MASK/$MASK}$quote$SUBS
      fi
    else
      out=$out$NL$span$NL
      original=$original$NL$span$NL
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
command_segments() { # TEXT -> aligned SEGMENT_TEXTS, SEGMENT_MODELS, SEGMENT_CAUSES
  local joined=${1//\\$NL/ } line index count delim expands end term judged="" cause
  local lines
  SEGMENTS=""
  SEGMENT_COMMANDS=()
  SEGMENT_TEXTS=()
  SEGMENT_MODELS=()
  SEGMENT_CAUSES=()
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
    index=$((index + 1))
    COMMAND_MODEL=modeled
    COMMAND_CAUSE=""
    uncommented "$line"
    if mask_spans "$BARE"; then
      BARE=$MASKED
    fi
    if ! [[ $BARE =~ (^|[^<])\<\<-?[[:space:]]*([^[:space:]\<][^[:space:]]*) ]]; then
      judged=$judged$line$NL
      continue
    fi
    delim=${BASH_REMATCH[2]}
    command_position "$BARE"
    cause=$COMMAND_CAUSE
    case "$BARE" in *$SEP*) cause=heredoc-command-list ;; esac
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
    if [ "$end" -eq "$count" ]; then
      cut_segments "$judged"
      judged=""
      cut_segments "$line" unterminated-heredoc
      continue
    fi
    # A heredoc shared by a command list has no proven consumer. The header
    # still keeps each command's data contract; only its input stays raw.
    if [ -n "$cause" ]; then
      cut_segments "$judged$line"
      judged=""
      term=""
      while [ "$index" -lt "$end" ]; do
        term=$term${lines[$index]}$NL
        index=$((index + 1))
      done
      cut_segments "$term" "$cause"
    else
      judged=$judged$line$NL
      COMMAND_MODEL=modeled
      COMMAND_CAUSE=""
      if runs_shell_text "$BARE" stdin; then
        while [ "$index" -lt "$end" ]; do
          judged=$judged${lines[$index]}$NL
          index=$((index + 1))
        done
      elif [ -n "$expands" ]; then
        while [ "$index" -lt "$end" ]; do
          if lift_substitutions "${lines[$index]}"; then
            judged=$judged$SUBS
          else
            cut_segments "$judged"
            judged=""
            cut_segments "${lines[$index]}" unpaired-substitution
          fi
          index=$((index + 1))
        done
      fi
    fi
    index=$((end + 1))
  done
  cut_segments "$judged"
  # Published callers read SEGMENTS without command-local metadata. Preserve
  # their whole-command model answer as well as the optional per-command one.
  COMMAND_MODEL=modeled
  index=0
  while [ "$index" -lt "${#SEGMENT_MODELS[@]}" ]; do
    [ "${SEGMENT_MODELS[$index]}" != unmodeled ] || COMMAND_MODEL=unmodeled
    index=$((index + 1))
  done
}
cut_segments() { # TEXT [UNMODELED-CAUSE] -> append command answers
  local text=$1 cause=${2:-} cut original line raw masked model detail length executable published
  if [ -n "$cause" ]; then
    cut=$text
    original=$text
  elif mask_spans "$text" boundaries; then
    cut=$MASKED
    original=$UNMASKED
  else
    cause=unpaired-text
    cut=$text
    original=$text
  fi
  # Descriptor duplication's ampersand belongs to this command, including
  # raw fallback commands with the redirection between executable and verb.
  cut=${cut//>\&/>$MASK}
  cut=${cut//<\&/<$MASK}
  cut=${cut//;/$NL}
  cut=${cut//&/$NL}
  cut=${cut//\|/$NL}
  cut=${cut//\(/$NL}
  cut=${cut//\)/$NL}
  cut=${cut//\`/$NL}
  while IFS= read -r line; do
    length=${#line}
    raw=${original:0:length}
    original=${original:length+1}
    [ -n "${raw//[[:space:]]/}" ] || continue
    if [ -n "$cause" ]; then
      model=unmodeled
      detail=$cause
    else
      COMMAND_MODEL=modeled
      COMMAND_CAUSE=""
      uncommented "$line"
      raw=${raw:0:${#BARE}}
      mask_spans "$raw" boundaries || return 1
      masked=$MASKED
      command_position "$masked"
      executable=$COMMAND_TEXTS
      case "$raw" in
        *[\<\>]\&*) COMMAND_MODEL=unmodeled; COMMAND_CAUSE=descriptor-redirection ;;
      esac
      if [ "$COMMAND_MODEL" = modeled ]; then
        if mask_spans "$raw"; then
          # Opening shell input or substitutions produces command text. Feed
          # that text back through this same boundary and model owner.
          if [ "$COMMAND_MODEL" = modeled ] && [ "$MASKED" != "$masked" ]; then
            cut_segments "$UNMASKED"
            continue
          fi
        else
          COMMAND_MODEL=unmodeled
          COMMAND_CAUSE=unpaired-text
        fi
      fi
      if [ "$COMMAND_MODEL" = unmodeled ]; then
        cut_segments "$raw" "$COMMAND_CAUSE"
        continue
      fi
      model=modeled
      detail=""
      raw=$MASKED
    fi
    published=$raw
    if [ "$model" = unmodeled ]; then
      # Keep raw command-local fallback separate from the published view.
      # Published hooks need shell input opened and quoted arguments masked.
      uncommented "$raw"
      if mask_spans "$BARE" published; then published=$MASKED; fi
    fi
    SEGMENTS=$SEGMENTS$published$NL
    SEGMENT_COMMANDS[${#SEGMENT_COMMANDS[@]}]=${executable:-}
    SEGMENT_TEXTS[${#SEGMENT_TEXTS[@]}]=$raw
    SEGMENT_MODELS[${#SEGMENT_MODELS[@]}]=$model
    SEGMENT_CAUSES[${#SEGMENT_CAUSES[@]}]=$detail
  done <<EOF
$cut
EOF
}
# The executable of a simple command. Assignments and redirections are the
# shell's, and launching prefixes consume their own options before the child
# executable. Shell control words also introduce a command, but only when
# unquoted and without a path. An option value named `kendex` is never that child.
# These prefixes occur in tool commands judged by block-worktree-refresh;
# Only a modeled invocation keeps its remaining words as arguments.
command_position() { # SEGMENT -> COMMAND_TEXTS
  local rest=$1 word raw name data launcher="" operand="" options=1
  COMMAND_TEXTS=""
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
        *) COMMAND_MODEL=unmodeled; COMMAND_CAUSE=prefix-options; COMMAND_TEXTS=$1; return 0 ;;
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
          case "${rest#"$raw"}" in *[[:space:]]--*) COMMAND_MODEL=unmodeled; COMMAND_CAUSE=eval-options ;; esac
          if [ "${2:-}" = shell ]; then
            COMMAND_TEXTS=$rest
            return 0
          fi
          data=${rest#"$raw"}
          data=${data#"${data%%[![:space:]]*}"}
          case "$data" in
            [\'\"]*) COMMAND_TEXTS=$rest; return 0 ;;
          esac
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
            COMMAND_CAUSE=argument-contract
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
          COMMAND_CAUSE=unknown-command
          COMMAND_TEXTS=$1
          return 0
          ;;
      esac
    fi
    rest=${rest#"$raw"}
  done
}

# Published callers judge each executable candidate. Assignments precede the
# command; subsequent words remain candidates because launchers can run them.
command_text() { # SEGMENT -> COMMAND_TEXTS, one candidate suffix per line
  local rest=$1 word name
  while :; do
    rest=${rest#"${rest%%[![:space:]]*}"}
    word=${rest%%[[:space:]]*}
    case "$word" in
      [[:alpha:]_]*=*) ;;
      *) break ;;
    esac
    name=${word%%=*}
    case "$name" in
      *[![:alnum:]_]*) break ;;
    esac
    rest=${rest#"$word"}
  done
  COMMAND_TEXTS=""
  while :; do
    rest=${rest#"${rest%%[![:space:]]*}"}
    [ -n "$rest" ] || return 0
    COMMAND_TEXTS=$COMMAND_TEXTS$rest$NL
    word=${rest%%[[:space:]]*}
    rest=${rest#"$word"}
  done
}
