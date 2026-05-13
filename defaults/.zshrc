# History
HISTFILE=$HOME/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt APPEND_HISTORY INC_APPEND_HISTORY SHARE_HISTORY
setopt HIST_IGNORE_ALL_DUPS HIST_REDUCE_BLANKS

# Completion
autoload -Uz compinit && compinit
zstyle ':completion:*' menu select

# Editor
command -v nvim &>/dev/null && export VISUAL=nvim EDITOR=nvim

# Emacs key bindings (zsh otherwise picks vi mode when EDITOR=vim/nvim)
bindkey -e

# Prompt: user@host: path (git branch)
prompt_git_branch() {
  git symbolic-ref --short HEAD 2>/dev/null
}
set_prompt() {
  local branch
  branch=$(prompt_git_branch)
  PROMPT="%F{magenta}%n%f@%F{yellow}%m%f: %F{cyan}%~%f${branch:+ %F{green}$branch%f}
$ "
}
precmd_functions+=(set_prompt)
