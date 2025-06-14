# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
HOMEBREW="/opt/homebrew/bin:/opt/homebrew/sbin"
export PATH="$HOMEBREW:$PATH"
export PATH=$HOME/development/flutter/bin:$PATH

# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('/opt/homebrew/Caskroom/miniforge/base/bin/conda' 'shell.zsh' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
eval "$__conda_setup"
else
if [ -f "/opt/homebrew/Caskroom/miniforge/base/etc/profile.d/conda.sh" ]; then
. "/opt/homebrew/Caskroom/miniforge/base/etc/profile.d/conda.sh"
else
export PATH="/opt/homebrew/Caskroom/miniforge/base/bin:$PATH"
fi
fi
unset __conda_setup
# <<< conda initialize <<<

# oh-my-posh
eval "$(oh-my-posh init zsh --config ~/.config/OhMyPosh/catppuccin_mocha.omp.json)"

# fzf 
eval "$(fzf --zsh)"

# eza, better ls 
alias ls='eza --long --icons=always --group-directories-first --git --all --time-style='+%Y-%m-%d %H:%M' --time=modified --no-user'

# zsh-autosuggestions
source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh

# zsh-syntax-highlighting
source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# Better history 
HISTFILE=$HOME/.zhistory
SAVEHIST=1000
HISTSIZE=999
setopt share_history
setopt hist_expire_dups_first
setopt hist_ignore_dups
setopt hist_verify
bindkey '^[[A' history-search-backward
bindkey '^[[B' history-search-forward
