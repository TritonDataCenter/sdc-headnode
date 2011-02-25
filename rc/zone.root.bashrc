if [ "$PS1" ]; then
  shopt -s checkwinsize cdspell extglob histappend
  alias ll='ls -lF'
  HISTCONTROL=ignoreboth
  HISTIGNORE="[bf]g:exit:quit"

  [[ -f /.dcinfo ]] && . /.dcinfo
  if [[ -n ${SDC_DATACENTER_NAME} && -n ${SDC_DATACENTER_HEADNODE_ID} ]]; then
    PS1="[\u@\h (${SDC_DATACENTER_NAME}:${SDC_DATACENTER_HEADNODE_ID}) \w]\\$ "
  elif [[ -n ${SDC_DATACENTER_NAME} ]]; then
    PS1="[\u@\h (${SDC_DATACENTER_NAME}) \w]\\$ "
  else
    PS1="[\u@\h \w]\\$ "
  fi
  if [ -n "$SSH_CLIENT" ]; then
    [ -n "${SSH_CLIENT}" ] && PROMPT_COMMAND='echo -ne "\033]0;${HOSTNAME%%\.*} \007" && history -a'
  fi
fi
