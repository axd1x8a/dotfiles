# set locale to en_US.UTF-8 on linux if not set or not any UTF-8 locale
if [[ $OSTYPE == linux* ]]; then
    if [[ -z $LANG || $LANG != *UTF-8 ]]; then
        locale-gen --purge en_US.UTF-8
        update-locale LANG=en_US.UTF-8
        export LANG=en_US.UTF-8
        exec zsh
    fi
fi

# Zinit Plugin Manager
declare -A ZINIT
ZINIT[HOME_DIR]="${HOME}/.zinit"
ZINIT[BIN_DIR]="${HOME}/.zinit/bin"
export ZSH_CACHE_DIR="${ZINIT[HOME_DIR]}"
if [[ ! -d $ZINIT[BIN_DIR] ]]; then
    print -P "Installing Zinit Plugin Manager..."
    mkdir -p "$ZINIT[BIN_DIR]"
    git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT[BIN_DIR]"
fi
source "${ZINIT[BIN_DIR]}/zinit.zsh"
# end Zinit Plugin Manager

autoload -U colors && colors
autoload -U add-zsh-hook

skip_global_compinit=1
setopt prompt_subst
setopt correct_all
setopt HIST_FIND_NO_DUPS
setopt MENU_COMPLETE    # Automatically highlight first element of completion menu
setopt AUTO_LIST        # Automatically list choices on ambiguous completion.
setopt COMPLETE_IN_WORD # Complete from both ends of a word.

zstyle ':autocomplete:*' min-delay 0.1
zstyle ':autocomplete:*' min-input 2
zstyle ':completion:correct-word:*' max-errors 10
# zstyle ':autocomplete:*complete*:*' insert-unambiguous yes
zstyle ':autocomplete:history-search-backward:*' list-lines 256
zstyle ':autocomplete:history-incremental-search-backward:*' list-lines 8
# zstyle ':completion:*' ignored-patterns '/c/windows/**/*'
zstyle ':completion:*' ignored-patterns '*.dll'
zstyle ':completion:*' completer _expand _complete _match _prefix

# zinit ice wait'!' lucid
zinit for OMZL::history.zsh

# zinit ice wait'!' lucid
zinit for OMZL::key-bindings.zsh

__init_autocomplete() {
    # if functions .autocomplete.__init__.precmd >/dev/null; then
    #     .autocomplete.__init__.precmd
    #     print -P "Autocomplete initialized via .autocomplete.__init__.precmd"
    # else
    #     .autocomplete:__main__:precmd
    #     print -P "Autocomplete initialized via .autocomplete:__main__:precmd"
    # fi

    bindkey -M menuselect '\r' .accept-line
    bindkey '\t' menu-select "$terminfo[kcbt]" menu-select
    bindkey -M menuselect '\t' menu-complete "$terminfo[kcbt]" reverse-menu-complete
}

zinit ice lucid nocd \
    atload'__init_autocomplete; unset __init_autocomplete'
zinit light marlonrichert/zsh-autocomplete

zinit ice wait lucid
zinit snippet OMZP::virtualenv

zinit light agkozak/agkozak-zsh-prompt

virtualenv_prompt_info() {}

setopt PROMPT_CR

AGKOZAK_LEFT_PROMPT_ONLY=1
AGKOZAK_SHOW_VIRTUALENV=0
AGKOZAK_PROMPT_DIRTRIM=0
AGKOZAK_CMD_EXEC_TIME=0
AGKOZAK_USER_HOST_DISPLAY=0
AGKOZAK_SHOW_BG=0
AGKOZAK_SHOW_STASH=0
AGKOZAK_MULTILINE=1

AGKOZAK_CUSTOM_SYMBOLS=('⇣⇡' '⇣' '⇡' '+' 'x' '!' '>' '?' 'S')

AGKOZAK_CUSTOM_PROMPT=''
if [[ -v WSL_DISTRO_NAME ]]; then
    AGKOZAK_CUSTOM_PROMPT+='%{$fg_bold[red]%}(WSL)%{$reset_color%} '
fi
AGKOZAK_CUSTOM_PROMPT+='%{$fg_bold[cyan]%}%d%{$reset_color%} '
AGKOZAK_CUSTOM_PROMPT+='%{$(virtualenv_prompt_info)%}'
AGKOZAK_CUSTOM_PROMPT+='%{%(3V.${ZSH_THEME_GIT_PROMPT_PREFIX}%6v%(7V.::%7v.)${ZSH_THEME_GIT_PROMPT_CLEAN}${ZSH_THEME_GIT_PROMPT_SUFFIX}.)%}'
# newline
AGKOZAK_CUSTOM_PROMPT+=$'\n'

AGKOZAK_CUSTOM_PROMPT+='%(?:%{$fg_bold[green]%}➜:%{$fg_bold[red]%}➜) '
AGKOZAK_CUSTOM_PROMPT+=' %{$reset_color%}$ '

ZSH_THEME_GIT_PROMPT_PREFIX="%{$fg_bold[blue]%}(%{$fg[red]%}"
ZSH_THEME_GIT_PROMPT_SUFFIX="%{$reset_color%}"
ZSH_THEME_GIT_PROMPT_DIRTY="%{$fg[blue]%}) %{$fg[yellow]%}✗ "
ZSH_THEME_GIT_PROMPT_CLEAN="%{$fg[blue]%}) "
ZSH_THEME_VIRTUALENV_PREFIX="%{$fg_bold[blue]%}(%{$fg[green]%}"
ZSH_THEME_VIRTUALENV_SUFFIX="%{$fg[blue]%}) "


if [[ -v WSL_DISTRO_NAME ]]; then
    alias virtualenv='virtualenv ~/.virtualenvs/$(basename $PWD)'
fi

md5ns() {
    echo -n "$1" | md5sum | cut -c1-4
}

__python_venv() {
    VENVPATH=.venv
    if [[ -v WSL_DISTRO_NAME ]]; then
        if [[ -d ~/.virtualenvs/$(basename $PWD) ]]; then
            source ~/.virtualenvs/$(basename $PWD)/bin/activate >/dev/null 2>&1
            return
        fi

    elif [[ ! -v WSL_DISTRO_NAME && -d $VENVPATH ]]; then
        if [[ -e $VENVPATH/Scripts/activate ]]; then
            source $VENVPATH/Scripts/activate >/dev/null 2>&1
            return
        elif [ -e $VENVPATH/bin/activate ]; then
            source $VENVPATH/bin/activate >/dev/null 2>&1
            return
        fi

    elif [[ -v VIRTUAL_ENV ]]; then
        PARENT_DIR="$(dirname "$VIRTUAL_ENV")"
        if [[ "$PWD" == "$PARENT_DIR"* ]]; then
            return
        fi
        deactivate
    fi
}

add-zsh-hook chpwd __python_venv
__python_venv


if [[ ! -e $HOME/.local/bin/uv ]]; then
    setup_uv() {
        curl -LsSf https://astral.sh/uv/install.sh | zsh
    }
fi

zinit for \
    wait lucid as"completion" \
    id-as"uv-completion" \
    blockf \
    nocompile \
    has"uv" \
    atclone"uv generate-shell-completion zsh > _uv" \
    atpull"%atclone" \
    run-atpull \
    zdharma-continuum/null

zinit for \
    wait lucid as"completion" \
    id-as"poetry-completion" \
    blockf \
    nocompile \
    has"poetry" \
    atclone"poetry completions zsh > _poetry" \
    atpull"%atclone" \
    run-atpull \
    zdharma-continuum/null

zinit for \
    wait lucid as"completition" \
    id-as"pip-completion" \
    blockf \
    nocompile \
    has"pip" \
    atclone"pip completion --zsh > _pip" \
    atpull"%atclone" \
    run-atpull \
    zdharma-continuum/null

zinit for \
    wait lucid as"completion" \
    id-as"packwiz-completion" \
    blockf \
    nocompile \
    has"packwiz" \
    atclone"packwiz completion zsh > _packwiz" \
    atpull"%atclone" \
    run-atpull \
    zdharma-continuum/null

# git
zinit for \
    wait lucid as"completion" \
    id-as"git-completion" \
    blockf \
    nocompile \
    has"git" \
    atclone"curl -o _git https://raw.githubusercontent.com/git/git/master/contrib/completion/git-completion.zsh" \
    atpull"%atclone" \
    run-atpull \
    zdharma-continuum/null

# rust boolshit
if [[ -e $HOME/.cargo ]]; then
    case ":${PATH}:" in
        *:"$HOME/.cargo/bin":*)
            ;;
        *)
        export PATH="$HOME/.cargo/bin:$PATH"
        ;;
    esac

    zinit for \
        wait lucid as"completion" \
        id-as"rustup-completion" \
        blockf \
        nocompile \
        has"rustup" \
        atclone"rustup completions zsh > _rustup" \
        atpull"%atclone" \
        run-atpull \
        zdharma-continuum/null

    zinit for \
        wait lucid as"completion" \
        id-as"cargo-completion" \
        blockf \
        nocompile \
        has"cargo" \
        atclone"rustup completions zsh cargo > _cargo" \
        atpull"%atclone" \
        run-atpull \
        zdharma-continuum/null
fi

if [[ $OSTYPE != Windows_NT && $OSTYPE != cygwin && $OSTYPE != msys ]]; then
    # remove existing _docker completion function without removing the file
    # for some reason, /usr/share/zsh/vendor-completions/_docker always gets loaded
    # over the generated one
    if [[ -e /usr/share/zsh/vendor-completions/_docker ]]; then
        unfunction _docker
    fi

    zinit for \
        wait lucid as"completion" \
        id-as"docker-compose-completion" \
        has"docker" \
        blockf \
        nocompile \
        atclone"docker completion zsh > _docker" \
        atpull"%atclone" \
        run-atpull \
        zdharma-continuum/null

    case ":${PATH}:" in
        *:"$HOME/.local/bin":*)
            ;;
        *)
        export PATH="$HOME/.local/bin:$PATH"
        ;;
    esac

elif [[ ! $IS_WSL ]]; then
    # PATH=$(echo $PATH | sed -E 's/(.*)(\/mingw64\/bin)(.*)/\1\3:\2/')
    explorer() {
        if [[ -n "$1" ]]; then
            explorer.exe "$(cygpath -w "$1")"
        else
            explorer.exe "$(cygpath -w .)"
        fi
    }
fi

# command_not_found_handler() {
#     echo "I don't know what '$1' is." >&2
#     return 1
# }

zinit for \
    atload"zicompinit; zicdreplay" \
    blockf \
    lucid \
    wait \
    zsh-users/zsh-completions
