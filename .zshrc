# zmodload zsh/zprof
zmodload zsh/files
zmodload zsh/stat
zmodload zsh/datetime

typeset -g ZSH_DATA_ROOT="${XDG_DATA_HOME:-${HOME}/.local/share}/zsh"
typeset -g ZSH_PLUGIN_DIR="${ZSH_DATA_ROOT}/plugins"
typeset -g ZSH_COMPLETION_DIR="${ZSH_DATA_ROOT}/completions"
typeset -g ZSH_CACHE_DIR="${XDG_CACHE_HOME:-${HOME}/.cache}/zsh"

mkdir -p "$ZSH_PLUGIN_DIR" "$ZSH_COMPLETION_DIR" "$ZSH_CACHE_DIR"

zsh_update() {
    print -P "%F{yellow}Updating Zsh plugins and completions...%f"

    if (( ${+functions[async_stop_worker]} )); then
        print -P "%F{cyan}Stopping async workers...%f"
        async_stop_worker _main_worker 2>/dev/null
    fi

    print -P "%F{yellow}Clearing compiled cache...%f"
    command find "$ZSH_DATA_ROOT" "$ZSH_CACHE_DIR" \
        -name '*.zwc' -delete 2>/dev/null
    rm -f "${ZDOTDIR:-$HOME}"/.z{shrc,compdump}.zwc 2>/dev/null

    rm -rf "${XDG_STATE_HOME:-$HOME/.local/state}/zsh-autocomplete" 2>/dev/null
    ZSH_UPDATING=1 exec zsh
}

zcompile_many() {
    local f
    for f; do zcompile -R -- "$f".zwc "$f" 2>/dev/null; done
}

zcompile_one() {
    local file="$1"
    [[ -f $file ]] || return
    if [[ -n "$ZSH_UPDATING" || ! -f ${file}.zwc || $file -nt ${file}.zwc ]]; then
        zcompile -R -- "${file}.zwc" "$file" 2>/dev/null
    fi
}

ensure_repo() {
    local url="$1" dest="$2" ref="${3:-}"
    if [[ -d "${dest}/.git" ]]; then
        if (( ${+ZSH_UPDATING} )); then
            print -P "%F{cyan}Updating repo:%f ${dest:t}"
            if [[ -n $ref ]]; then
                if [[ -f "${dest}/.git/shallow" ]]; then
                    print -P "%F{cyan}Unshallowing:%f ${dest:t}"
                    git -C "$dest" fetch --unshallow --quiet 2>/dev/null || \
                        git -C "$dest" fetch --quiet 2>/dev/null || true
                else
                    git -C "$dest" fetch --quiet 2>/dev/null || true
                fi
                git -C "$dest" checkout --quiet "$ref" 2>/dev/null || true
            else
                git -C "$dest" pull --ff-only --quiet 2>/dev/null || true
            fi
        fi
    else
        print -P "%F{green}Cloning repo:%f ${dest:t}"
        if [[ -n $ref ]]; then
            git clone --quiet "$url" "$dest" >/dev/null 2>&1 || return
            git -C "$dest" checkout --quiet "$ref" 2>/dev/null || true
        else
            git clone --depth=1 "$url" "$dest" >/dev/null 2>&1 || return
        fi
    fi
}

ensure_remote_file() {
    local url="$1" dest="$2"
    if [[ ! -f "$dest" || -n "$ZSH_UPDATING" ]]; then
        if (( ${+ZSH_UPDATING} )); then print -P "%F{cyan}Updating file:%f ${dest:t}"; fi
        curl -fsSL --create-dirs "$url" -o "$dest" 2>/dev/null || return
        zcompile_one "$dest"
    fi
}

ensure_eval_cache() {
    local cmd="$1" file="$2"
    if [[ ! -f "$file" || -n "$ZSH_UPDATING" ]]; then
        if (( ${+ZSH_UPDATING} )); then print -P "%F{cyan}Updating cache:%f ${file:t}"; fi
        eval "$cmd" >| "$file" 2>/dev/null || return
        zcompile_one "$file"
    fi
}

generate_completion() {
    local file="$1"; shift
    local -a cmd=("$@")
    local binary="${cmd[1]}"

    if [[ -f "$file" && -z "$ZSH_UPDATING" ]]; then
        return
    fi

    whence -p "$binary" >/dev/null 2>&1 || return

    local tmp="${file}.tmp"
    if "${cmd[@]}" >"$tmp" 2>/dev/null; then
        mv "$tmp" "$file"
        zcompile_one "$file"
    else
        rm -f "$tmp"
    fi
}

download_completion() {
    local file="$1" url="$2"
    if [[ ! -f "$file" || -n "$ZSH_UPDATING" ]]; then
        local tmp="${file}.tmp"
        if curl -fsSL "$url" -o "$tmp" 2>/dev/null; then
            mv "$tmp" "$file"
            zcompile_one "$file"
        else
            rm -f "$tmp"
        fi
    fi
}

copy_completion() {
    local source="$1" target="$2"
    [[ -r $source ]] || return
    if [[ ! -f "$target" || "$source" -nt "$target" || -n "$ZSH_UPDATING" ]]; then
        cp "$source" "$target"
        zcompile_one "$target"
    fi
}

# --- zsh-async --------------------------------------------------------------------
typeset -g ZSHASYNC_FILE="${ZSH_PLUGIN_DIR}/zsh-async/async.zsh"
ensure_remote_file \
    "https://raw.githubusercontent.com/mafredri/zsh-async/master/async.zsh" \
    "$ZSHASYNC_FILE"
source "$ZSHASYNC_FILE"

# --- Zoxide ------------------------------------------------------------------------

typeset -g _HAS_ZOXIDE=0
if [[ -x "$(command -v zoxide)" ]]; then
    _HAS_ZOXIDE=1
    ensure_eval_cache "zoxide init zsh --cmd cd" "${ZSH_CACHE_DIR}/zoxide.zsh"
    source "${ZSH_CACHE_DIR}/zoxide.zsh"
else
    setup_zoxide() {
        print -P "%F{yellow}Installing zoxide...%f"
        curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
    }
fi

typeset -ga _ZOXIDE_RECENT_DIRS=()

if (( _HAS_ZOXIDE )); then
    _zoxide_autocd_widget() {
        if [[ -n $BUFFER && $BUFFER != *' '* ]] && ! whence "$BUFFER" >/dev/null 2>&1 && [[ ! -d $BUFFER ]]; then
            local target=$(zoxide query -- "$BUFFER" 2>/dev/null)
            if [[ -n $target ]]; then
                cd "$target"
                BUFFER=''
                zle .reset-prompt
                return
            fi
        fi
        zle .accept-line
    }
    zle -N accept-line _zoxide_autocd_widget

    _zoxide_job() {
        zoxide query --list
    }
fi

# --- Core autoloads ----------------------------------------------------------------

skip_global_compinit=1
setopt prompt_subst
setopt correct_all
setopt HIST_FIND_NO_DUPS
setopt MENU_COMPLETE
setopt AUTO_LIST
setopt COMPLETE_IN_WORD
setopt HASH_EXECUTABLES_ONLY
# setopt NO_HASH_CMDS
# setopt NO_HASH_DIRS
setopt AUTO_CD

zstyle ':autocomplete:*' min-delay 0.1
zstyle ':autocomplete:*' min-input 2
zstyle ':completion:correct-word:*' max-errors 5
zstyle ':autocomplete:*complete*:*' insert-unambiguous yes
zstyle ':autocomplete:*history*:*' insert-unambiguous yes
zstyle ':autocomplete:history-search-backward:*' list-lines 256
zstyle ':autocomplete:history-incremental-search-backward:*' list-lines 8
# zstyle ':completion:*' ignored-patterns '*.dll'
zstyle ':completion:*' completer _expand _complete _match _prefix
zstyle '*:compinit' arguments -C

# --- Prompt ------------------------------------------------------------------------
#
# Inspired by agkozak-zsh-prompt

autoload -Uz add-zsh-hook

autoload -Uz colors && colors
setopt PROMPT_CR PROMPT_SP

_prompt_git_status() {
    local ref branch
    ref=$(command git symbolic-ref --quiet HEAD 2>/dev/null) || {
        [[ $? == 128 ]] && return
        ref=$(command git rev-parse --short HEAD 2>/dev/null) || return
    }
    branch=${ref#refs/heads/}
    [[ -z $branch ]] && return

    local git_status symbols
    git_status="$(LC_ALL=C GIT_OPTIONAL_LOCKS=0 command git status 2>&1)"

    local -a sym=('⇣⇡' '⇣' '⇡' '+' 'x' '!' '>' '?')
    local -a pat=(
        ' have diverged,'
        'Your branch is behind '
        'Your branch is ahead of '
        'new file:   '
        'deleted:    '
        'modified:   '
        'renamed:    '
        'Untracked files:'
    )
    local i
    for (( i = 1; i <= $#pat; i++ )); do
        [[ $git_status == *${pat[i]}* ]] && symbols+=${sym[i]}
    done

    printf ' (%s%s)' "$branch" "${symbols:+ $symbols}"
}

_prompt_set_git_psvars() {
    psvar[3]="$1"
    psvar[6]=${${${1#*\(}% *}%\)}
    psvar[7]=${${1%\)}##* }
    [[ ${1#*\(} != *' '* ]] && psvar[7]=''
}

typeset -g _PROMPT_READY=0

_prompt_preexec() {
    _PROMPT_READY=0
}

_prompt_redraw() {
    _prompt_set_git_psvars "$1"
    if zle && [[ -z $BUFFER ]] && (( _PROMPT_READY )); then
        zle .reset-prompt
    fi
}

# --- Theme variables -----------------------------------------------------------

ZSH_THEME_GIT_PROMPT_PREFIX="%{$fg_bold[blue]%}(%{$fg[red]%}"
ZSH_THEME_GIT_PROMPT_SUFFIX="%{$reset_color%}"
ZSH_THEME_GIT_PROMPT_CLEAN="%{$fg[blue]%}) "
ZSH_THEME_VIRTUALENV_PREFIX="%{$fg_bold[blue]%}(%{$fg[green]%}"
ZSH_THEME_VIRTUALENV_SUFFIX="%{$fg[blue]%}) "

# --- Build PROMPT --------------------------------------------------------------

PROMPT=''
[[ -v WSL_DISTRO_NAME ]] && PROMPT+='%{$fg_bold[red]%}(WSL)%{$reset_color%} '
PROMPT+='%{$fg_bold[cyan]%}%d%{$reset_color%} '
PROMPT+='%{$(virtualenv_prompt_info)%}'
PROMPT+='%{%(3V.${ZSH_THEME_GIT_PROMPT_PREFIX}%6v%(7V.::%7v.)${ZSH_THEME_GIT_PROMPT_CLEAN}${ZSH_THEME_GIT_PROMPT_SUFFIX}.)%}'
PROMPT+=$'\n'
PROMPT+='%(?:%{$fg_bold[green]%}➜:%{$fg_bold[red]%}➜)  %{$reset_color%}$ '


# --- Async Worker & Callback --------------------------------------------------

_main_async_callback() {
    case $1 in
        _prompt_git_status)     _prompt_redraw "$3" ;;
        _zoxide_job) _ZOXIDE_RECENT_DIRS=( ${(f)3} ) ;;
    esac
}

async_start_worker _main_worker -n
async_register_callback _main_worker _main_async_callback

_main_precmd() {
    async_flush_jobs _main_worker

    psvar[3]=''
    async_job _main_worker _prompt_git_status

    # Only do Zoxide if it exists
    if (( _HAS_ZOXIDE )); then
        async_job _main_worker _zoxide_job
    fi

    _PROMPT_READY=1
}

add-zsh-hook preexec _prompt_preexec
add-zsh-hook precmd _main_precmd

# --- System specific stuff ---------------------------------------------------------

if [[ $OSTYPE != Windows_NT && $OSTYPE != cygwin && $OSTYPE != msys ]]; then
    # remove existing _docker completion function without removing the file
    # for some reason, /usr/share/zsh/vendor-completions/_docker always gets loaded
    # over the generated one
    if [[ -e /usr/share/zsh/vendor-completions/_docker ]]; then
        unfunction _docker
    fi

    case ":${PATH}:" in
        *:"$HOME/.local/bin":*)
            ;;
        *)
        export PATH="$HOME/.local/bin:$PATH"
        ;;
    esac

elif [[ $OSTYPE == cygwin ]]; then
    explorer() {
        if [[ -n "$1" ]]; then
            explorer.exe "$(cygpath -w "$1")"
        else
            explorer.exe "$(cygpath -w .)"
        fi
    }
    zstyle ':completion:*' fake-files '/: c v'
fi

# --- History configuration ---------------------------------------------------------

# Sourced from Oh My Zsh

function omz_history {
  local clear list stamp REPLY
  zparseopts -E -D c=clear l=list f=stamp E=stamp i=stamp t:=stamp

  if [[ -n "$clear" ]]; then
    print -nu2 "This action will irreversibly delete your command history. Are you sure? [y/N] "
    builtin read -E
    [[ "$REPLY" = [yY] ]] || return 0

    print -nu2 >| "$HISTFILE"
    fc -p "$HISTFILE"

    print -u2 History file deleted.
  elif [[ $# -eq 0 ]]; then
    builtin fc "${stamp[@]}" -l 1
  else
    builtin fc "${stamp[@]}" -l "$@"
  fi
}

setup_history() {
    # Timestamp format
    case ${HIST_STAMPS-} in
    "mm/dd/yyyy") alias history='omz_history -f' ;;
    "dd.mm.yyyy") alias history='omz_history -E' ;;
    "yyyy-mm-dd") alias history='omz_history -i' ;;
    "") alias history='omz_history' ;;
    *) alias history="omz_history -t '$HIST_STAMPS'" ;;
    esac

    ## History file configuration
    [ -z "$HISTFILE" ] && HISTFILE="$HOME/.zsh_history"
    [ "$HISTSIZE" -lt 50000 ] && HISTSIZE=50000
    [ "$SAVEHIST" -lt 10000 ] && SAVEHIST=10000

    ## History command configuration
    setopt -g extended_history       # record timestamp of command in HISTFILE
    setopt -g hist_expire_dups_first # delete duplicates first when HISTFILE size exceeds HISTSIZE
    setopt -g hist_ignore_dups       # ignore duplicated commands history list
    setopt -g hist_ignore_space      # ignore commands that start with space
    setopt -g hist_verify            # show command with history expansion to user before running it
    setopt -g share_history          # share command history data
}

setup_history

# --- Autosuggestions and Oh My Zsh libs --------------------------------------------

load_omz_libs() {
    typeset -g OMZ_LIB_DIR="${ZSH_PLUGIN_DIR}/ohmyzsh/lib"
    ensure_remote_file \
        "https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/lib/key-bindings.zsh" \
        "${OMZ_LIB_DIR}/key-bindings.zsh"

    source "${OMZ_LIB_DIR}/key-bindings.zsh"
}
load_omz_libs

load_zsh_autocomplete() {
    typeset -g ZSHAUTO_DIR="${ZSH_PLUGIN_DIR}/zsh-autocomplete"
    ensure_repo \
        "https://github.com/marlonrichert/zsh-autocomplete.git" \
        "$ZSHAUTO_DIR" \
        "2be4e7f0b435138b0237d4f068b2a882fb06edc4^"

    if (( ${+ZSH_UPDATING} )) || [[ ! -f "${ZSHAUTO_DIR}/zsh-autocomplete.plugin.zsh.zwc" ]]; then
        local -a files_to_compile
        setopt localoptions extendedglob
        files_to_compile=(
            "${ZSHAUTO_DIR}"/**/(zsh-autocomplete.plugin.zsh|(.|_)autocomplete__*)~*.zwc(N)
        )

        (( ${#files_to_compile[@]} > 0 )) && zcompile_many "${files_to_compile[@]}"
        unsetopt localoptions extendedglob
    fi


    __init_autocomplete() {
        bindkey -M menuselect '\r' .accept-line
        bindkey '\t' menu-select "$terminfo[kcbt]" menu-select
        bindkey -M menuselect '\t' menu-complete "$terminfo[kcbt]" reverse-menu-complete
    }

    source "${ZSHAUTO_DIR}/zsh-autocomplete.plugin.zsh"
    __init_autocomplete
    unset -f __init_autocomplete
}

load_zsh_autocomplete

# --- virtualenv --------------------------------------------------------------------

function virtualenv_prompt_info() {
    [[ -n ${VIRTUAL_ENV} ]] || return
    local venv_name="${VIRTUAL_ENV_PROMPT:-${VIRTUAL_ENV:t:gs/%/%%}}"
    venv_name="${venv_name//[\(\) ]/}"
    print -rn -- "${ZSH_THEME_VIRTUALENV_PREFIX-[}${venv_name}${ZSH_THEME_VIRTUALENV_SUFFIX-]}"
}

# disables prompt mangling in virtual_env/bin/activate
export VIRTUAL_ENV_DISABLE_PROMPT=1

# --- Python virtualenv auto-activation ---------------------------------------------

if [[ -v WSL_DISTRO_NAME ]]; then
    alias virtualenv='virtualenv ~/.virtualenvs/$(basename "$PWD")'
fi

__python_venv() {
    local venv_paths=()

    if [[ -v WSL_DISTRO_NAME ]]; then
        venv_paths+=("$HOME/.virtualenvs/$(basename "$PWD")")
    fi
    venv_paths+=(".venv")

    for venv in $venv_paths; do
        if [[ -d "$venv" ]]; then
            local activate_script=""
            [[ -f "$venv/bin/activate" ]] && activate_script="$venv/bin/activate"
            [[ -f "$venv/Scripts/activate" ]] && activate_script="$venv/Scripts/activate"

            if [[ -n "$activate_script" ]]; then
                source "$activate_script" 2>/dev/null && return
            fi
        fi
    done

    if [[ -v VIRTUAL_ENV ]]; then
        local parent_dir="$(dirname "$VIRTUAL_ENV")"
        [[ "$PWD" != "$parent_dir"* ]] && deactivate 2>/dev/null
    fi
}

add-zsh-hook chpwd __python_venv
__python_venv

# --- UV installer (if missing) -----------------------------------------------------

if [[ ! -f "$HOME/.local/bin/uv" && ! -f "$HOME/.local/bin/uv.exe" ]]; then
    setup_uv() {
        print -P "%F{yellow}Installing uv...%f"
        curl -LsSf https://astral.sh/uv/install.sh | sh
    }
fi


# --- Completion system init --------------------------------------------------------

load_completions() {
    typeset -g ZSH_COMPLETIONS_DIR="${ZSH_PLUGIN_DIR}/zsh-completions"
    ensure_repo "https://github.com/zsh-users/zsh-completions.git" "$ZSH_COMPLETIONS_DIR"

    fpath=(
        "$ZSH_COMPLETION_DIR"
        "$ZSH_COMPLETIONS_DIR/src"
        $fpath
    )

    generate_completion "${ZSH_COMPLETION_DIR}/_uv"      uv generate-shell-completion zsh
    generate_completion "${ZSH_COMPLETION_DIR}/_poetry"  poetry completions zsh
    generate_completion "${ZSH_COMPLETION_DIR}/_packwiz" packwiz completion zsh
    generate_completion "${ZSH_COMPLETION_DIR}/_rustup"  rustup completions zsh rustup
    download_completion "${ZSH_COMPLETION_DIR}/_git"      https://raw.githubusercontent.com/git/git/master/contrib/completion/git-completion.zsh

    generate_completion "${ZSH_COMPLETION_DIR}/_pip"      pip completion --zsh


    generate_completion "${ZSH_COMPLETION_DIR}/_docker"   docker completion zsh

    if [[ ! -f "${ZSH_COMPLETION_DIR}/_cargo" || -n "$ZSH_UPDATING" ]]; then
        local sysroot
        sysroot="$(rustc --print sysroot 2>/dev/null)"
        if [[ -n $sysroot ]]; then
            copy_completion \
                "${sysroot}/share/zsh/site-functions/_cargo" \
                "${ZSH_COMPLETION_DIR}/_cargo"
        fi
    fi

    if (( ${+ZSH_UPDATING} )); then
        local -a comps_to_compile
        setopt localoptions extendedglob

        comps_to_compile+=( "${ZSH_COMPLETIONS_DIR}/src"/_* )

        (( ${#comps_to_compile[@]} > 0 )) && zcompile_many "${comps_to_compile[@]}"
    fi
}
load_completions


# --- Self Compile ------------------------------------------------------------------

typeset -g ZSHRC_PATH="${ZDOTDIR:-$HOME}/.zshrc"
if [[ ! -f "${ZSHRC_PATH}.zwc" || "${ZSHRC_PATH}" -nt "${ZSHRC_PATH}.zwc" ]]; then
    zcompile -R -- "${ZSHRC_PATH}.zwc" "${ZSHRC_PATH}" 2>/dev/null || true
fi

# --- Final cleanup / optional helpers ----------------------------------------------
_prompt_cleanup_helpers() {
    (( ${+ZSH_UPDATING} )) && return
    unset -f zcompile_many zcompile_one ensure_repo ensure_remote_file ensure_eval_cache \
             generate_completion download_completion copy_completion \
             _prompt_cleanup_helpers 2>/dev/null || true
}
_prompt_cleanup_helpers
# zprof > "$HOME/zsh-profiling.txt"
