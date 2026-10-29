complete -c bx -f -n '__fish_use_subcommand' -a info -d 'Show ELF header summary'
complete -c bx -f -n '__fish_use_subcommand' -a sections -d 'List ELF sections'
complete -c bx -f -n '__fish_use_subcommand' -a hex -d 'Hex dump a file'
complete -c bx -f -n '__fish_use_subcommand' -a help -d 'Show help'
complete -c bx -f -n '__fish_use_subcommand' -a version -d 'Show version'

complete -c bx -n '__fish_seen_subcommand_from hex' -s o -l offset -r -d 'Start offset'
complete -c bx -n '__fish_seen_subcommand_from hex' -s n -l length -r -d 'Dump length'
