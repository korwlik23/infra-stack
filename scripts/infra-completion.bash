# shellcheck shell=bash disable=SC2207
# Tab completion ของคำสั่ง infra — harden.sh ลิงก์ไว้ที่ /etc/bash_completion.d/infra
# เครื่องที่ติดตั้งก่อน v2.13: infra completion (ครั้งเดียว)

_infra_projects() {
  local f
  for f in "$1"/projects/*/docker-compose.yml; do
    if [ -f "$f" ]; then f="${f%/docker-compose.yml}"; echo "${f##*/}"; fi
  done
}

_infra_stacks() {
  local f
  for f in "$1"/docker/docker-compose.*.yml; do
    if [ -f "$f" ]; then f="${f##*/docker-compose.}"; echo "${f%.yml}"; fi
  done
}

_infra() {
  local cur="${COMP_WORDS[COMP_CWORD]}" cmd="${COMP_WORDS[1]:-}" n="$COMP_CWORD" root words="" d
  root="$(dirname "$(readlink -f "$(command -v infra)")")/.."
  if [ "$n" = 1 ]; then
    words="list new git deploy env restart rollback check logs artisan shell load
           status secrets up stop update dns cron completion
           backup restore restore-server psql mysql redis reset-password help"
    COMPREPLY=($(compgen -W "$words" -- "$cur"))
    return
  fi
  case "$cmd" in
    git|deploy|env|restart|rollback|check|artisan|shell|load)
      if [ "$n" = 2 ]; then
        words="$(_infra_projects "$root")"
      elif [ "$cmd" = deploy ] && [ "$n" = 3 ]; then
        words="--seed --no-seed"
      elif [ "$cmd" = rollback ] && [ "$n" = 3 ]; then
        words="previous"
      elif [ "$cmd" = load ] && [ "$n" = 3 ]; then
        COMPREPLY=($(compgen -f -- "$cur")); return
      fi ;;
    logs|log)
      [ "$n" != 2 ] || words="$(_infra_projects "$root") auto-deploy backup install $(docker ps --format '{{.Names}}' 2>/dev/null)" ;;
    up|stop)
      if [ "$n" = 2 ]; then
        words="$(_infra_stacks "$root")"
      else
        words="$(docker compose --env-file "$root/.env" -f "$root/docker/docker-compose.${COMP_WORDS[2]}.yml" config --services 2>/dev/null)"
      fi ;;
    update)
      [ "$n" != 2 ] || words="$(_infra_stacks "$root") all" ;;
    dns)
      words="$(_infra_stacks "$root")" ;;
    new)
      if [ "$n" = 3 ]; then
        for d in "$root"/templates/*/; do d="${d%/}"; words="$words ${d##*/}"; done
      elif [ "$n" = 4 ]; then
        words="--mysql"
      fi ;;
    restore)
      if [ "$n" = 2 ]; then
        words="postgres mysql volumes secrets"
      elif [ "${COMP_WORDS[2]}" = volumes ]; then
        words="--overwrite $(docker volume ls -q 2>/dev/null)"
      else
        COMPREPLY=($(compgen -f -- "$cur")); return
      fi ;;
    restore-server)
      COMPREPLY=($(compgen -d -- "$cur")); return ;;
    reset-password)
      [ "$n" != 2 ] || words="n8n grafana" ;;
  esac
  COMPREPLY=($(compgen -W "$words" -- "$cur"))
}

complete -F _infra infra
