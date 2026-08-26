#!/usr/bin/env bash
set -e

p10k_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"

if [[ ! -d "$p10k_dir" ]]; then
    git clone --depth=1 \
        https://github.com/romkatv/powerlevel10k.git \
        "$p10k_dir"
fi

cp .devcontainer/.p10k.zsh "$HOME/.p10k.zsh"

sed -i 's/^ZSH_THEME=.*/ZSH_THEME="powerlevel10k\/powerlevel10k"/' "$HOME/.zshrc"

grep -qF 'source ~/.p10k.zsh' "$HOME/.zshrc" || \
    echo '[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh' >> "$HOME/.zshrc"