#!/usr/bin/env bash
set -Eeuo pipefail

# ===== Configuráveis =====
DOMAIN="${DOMAIN:-vistaame.com.br}"
APP_USER="${APP_USER:-www-data}"
WEBROOT="${WEBROOT:-/var/www/$DOMAIN}"
PHPV="${PHPV:-8.3}"
LANGS="${LANGS:-pt_BR en_US}"     # idiomas para deploy estático
JOBS="${JOBS:-1}"                 # menos jobs = menos RAM
SET_THEME="${SET_THEME:-false}"   # true = ativa o tema automaticamente (usa /root/mageos.vars)

LOG="/root/breeze-blank-$(date +%F-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

ok()   { echo -e "\e[32m✔ $*\e[0m"; }
info() { echo -e "\e[34m➜ $*\e[0m"; }
warn() { echo -e "\e[33m⚠ $*\e[0m"; }
err()  { echo -e "\e[31m✘ $*\e[0m"; }
trap 'err "Falha na linha $LINENO: $BASH_COMMAND. Log: $LOG"; exit 1' ERR
[[ $EUID -eq 0 ]] || { err "Execute como root (sudo)."; exit 1; }

as_app() {
  local home; home="$(getent passwd "$APP_USER" | cut -d: -f6)"; [[ -z "$home" ]] && home="/var/www"
  mkdir -p "$home/.composer" /var/tmp/composer-tmp "$WEBROOT"
  chown -R "$APP_USER":www-data "$home/.composer" "$WEBROOT" /var/tmp/composer-tmp
  chmod 700 "$home/.composer"; chmod 2755 "$WEBROOT"
  sudo -u "$APP_USER" -H bash -lc "cd '$WEBROOT' && $*"
}

command -v php >/dev/null || { err "PHP não encontrado"; exit 1; }
command -v composer >/dev/null || { err "Composer não encontrado"; exit 1; }
[[ -d "$WEBROOT" ]] || { err "WEBROOT não existe: $WEBROOT"; exit 1; }

info "Instalando Breeze Blank (swissup/breeze-blank)…"
if as_app "composer show swissup/breeze-blank >/dev/null 2>&1"; then
  warn "Pacote já presente; pulando composer require."
else
  as_app "composer require swissup/breeze-blank --no-interaction --with-all-dependencies"
fi

info "Habilitando módulos Breeze…"
as_app "php bin/magento module:enable Swissup_Breeze Swissup_Rtl || true"

info "Atualizando banco dos módulos…"
as_app "php -d memory_limit=1024M bin/magento setup:upgrade --safe-mode=1"

info "Compilando DI (low-mem) e gerando estáticos (${LANGS})…"
as_app "rm -rf var/cache/* var/page_cache/* generated/* || true"
as_app "php -d memory_limit=1024M bin/magento setup:di:compile"
as_app "php -d memory_limit=1024M bin/magento setup:static-content:deploy -f ${LANGS} -j ${JOBS}"

as_app "php bin/magento cache:flush"
ok "Breeze Blank instalado."

# ===== Ativar tema automaticamente (opcional) =====
if [[ "${SET_THEME}" == "true" ]]; then
  info "Ativando tema Breeze Blank (escopo default)…"
  if [[ -f /root/mageos.vars ]]; then
    # shellcheck disable=SC1091
    source /root/mageos.vars
    : "${DB_USER:?}" "${DB_PASS:?}" "${DB_NAME:?}"

    # Descobre o theme_id do Breeze (tenta nomes comuns)
    THEME_ROW="$(mysql -N -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -e \
      "SELECT theme_id, theme_path FROM theme
       WHERE theme_path IN ('Swissup/breeze-blank','Swissup/breeze')
       ORDER BY theme_id DESC LIMIT 1;")" || true

    THEME_ID="$(awk '{print $1}' <<<"$THEME_ROW" || true)"
    if [[ -n "${THEME_ID:-}" ]]; then
      info "Encontrado theme_id=${THEME_ID}. Aplicando na configuração…"
      as_app "php bin/magento config:set design/theme/theme_id ${THEME_ID}"
      as_app "php bin/magento cache:flush"
      ok "Tema ativado (theme_id=${THEME_ID})."
    else
      warn "Não consegui detectar o theme_id no banco. Ative via Admin: Conteúdo → Design → Configuração."
    fi
  else
    warn "Sem /root/mageos.vars; pulando ativação automática. Ative via Admin."
  fi
fi

ok "Tudo pronto. Log: $LOG"
