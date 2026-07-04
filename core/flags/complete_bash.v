module flags

const complete_bash_template_full = r'
_rg() {
  local i cur prev opts cmds
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"
  cmd=""
  opts=""

  for i in ${COMP_WORDS[@]}; do
    case "${i}" in
      rg)
        cmd="rg"
        ;;
      *)
        ;;
    esac
  done

  case "${cmd}" in
    rg)
      opts="!OPTS!"
      if [[ ${cur} == -* || ${COMP_CWORD} -eq 1 ]] ; then
        COMPREPLY=($(compgen -W "${opts}" -- "${cur}"))
        return 0
      fi
      case "${prev}" in
!CASES!
      esac
      COMPREPLY=($(compgen -W "${opts}" -- "${cur}"))
      return 0
      ;;
  esac
}

complete -F _rg -o bashdefault -o default rg
'

const complete_bash_template_case = r'
        !FLAG!)
          COMPREPLY=($(compgen -f "${cur}"))
          return 0
          ;;
'

const complete_bash_template_case_choices = r'
        !FLAG!)
          COMPREPLY=($(compgen -W "!CHOICES!" -- "${cur}"))
          return 0
          ;;
'

/// Generate completions for Bash.
///
/// Note that these completions are based on what was produced for ripgrep <=13
/// using Clap 2.x. Improvements on this are welcome.
pub fn generate_complete_bash() string {
	mut opts := ''
	for flag in flags {
		opts += '--'
		opts += flag.name_long()
		opts += ' '
		if short := flag.name_short() {
			opts += '-'
			opts += short.ascii_str()
			opts += ' '
		}
		if name := flag.name_negated() {
			opts += '--'
			opts += name
			opts += ' '
		}
	}
	opts += '<PATTERN> <PATH>...'

	mut cases := ''
	for flag in flags {
		template := if flag.doc_choices().len > 0 {
			complete_bash_template_case_choices.trim_right('\n').replace('!CHOICES!',
				flag.doc_choices().join(' '))
		} else {
			complete_bash_template_case.trim_right('\n')
		}
		name := '--${flag.name_long()}'
		cases += template.replace('!FLAG!', name)
		if short := flag.name_short() {
			short_name := '-${short.ascii_str()}'
			cases += template.replace('!FLAG!', short_name)
		}
		if negated := flag.name_negated() {
			negated_name := '--${negated}'
			cases += template.replace('!FLAG!', negated_name)
		}
	}

	return complete_bash_template_full.replace('!OPTS!', opts).replace('!CASES!', cases).trim_left('\n')
}
