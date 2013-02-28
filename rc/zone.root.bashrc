if [ "$PS1" ]; then
  shopt -s checkwinsize cdspell extglob histappend
  alias ll='ls -lF'
  HISTCONTROL=ignoreboth
  HISTIGNORE="[bf]g:exit:quit"

  if [[ ! -f /var/smartdc/role ]]; then
      [[ ! -d /var/smartdc ]] && mkdir /var/smartdc
      /usr/sbin/mdata-get sdc:tags.smartdc_role > /var/smartdc/role
  fi
  SDC_ROLE=$(head -1 /var/smartdc/role)

  if [[ ! -f /var/smartdc/alias ]]; then
      [[ ! -d /var/smartdc ]] && mkdir /var/smartdc
      /usr/sbin/mdata-get sdc:alias > /var/smartdc/alias
  fi
  SDC_ALIAS=$(head -1 /var/smartdc/alias)

  [[ -f /.dcinfo ]] && . /.dcinfo
  if [[ -n ${SDC_DATACENTER_NAME} && -n ${SDC_ALIAS} ]]; then
    PS1="[\u@\h (${SDC_DATACENTER_NAME}:${SDC_ALIAS}) \w]\\$ "
  elif [[ -n ${SDC_DATACENTER_NAME} ]]; then
    PS1="[\u@\h (${SDC_DATACENTER_NAME}) \w]\\$ "
  elif [[ -n ${SDC_ALIAS} ]]; then
    PS1="[\u@\h (${SDC_ALIAS}) \w]\\$ "
  else
    PS1="[\u@\h \w]\\$ "
  fi
  if [ -n "$SSH_CLIENT" ]; then
    [ -n "${SSH_CLIENT}" ] && PROMPT_COMMAND='echo -ne "\033]0;${HOSTNAME%%\.*} \007" && history -a'
  fi
fi

function req() {
    if [ -n "${SDC_ROLE}" ]; then
        grep "$@" `svcs -L ${SDC_ROLE}` | bunyan
    fi
}
