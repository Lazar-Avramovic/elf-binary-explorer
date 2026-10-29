_bx_completions() {
    local cur prev
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    COMPREPLY=()

    if [ "$COMP_CWORD" -eq 1 ]; then
        COMPREPLY=( $(compgen -W "info sections hex help version" -- "$cur") )
        return
    fi

    case "$prev" in
        -o|--offset|-n|--length)
            COMPREPLY=( $(compgen -W "0 16 32 64 0x10" -- "$cur") )
            return
            ;;
    esac

    case "${COMP_WORDS[1]}" in
        hex)
            COMPREPLY=( $(compgen -W "-o --offset -n --length --" -- "$cur") $(compgen -f -- "$cur") )
            ;;
        *)
            COMPREPLY=( $(compgen -f -- "$cur") )
            ;;
    esac
}

complete -F _bx_completions bx
