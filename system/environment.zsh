() {
    setopt localoptions allexport
    local environment_file
    for environment_file in "$HOME"/.dotfiles/*/environment.conf(N); do
        source "$environment_file" || return
    done
} || return
typeset -gU path
