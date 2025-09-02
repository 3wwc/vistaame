#!/usr/bin/env bash
set -Eeuo pipefail

DOMAIN="${DOMAIN:-vistaame.com.br}"
APP_USER="${APP_USER:-www-data}"
WEBROOT="${WEBROOT:-/var/www/$DOMAIN}"
PURGE_OPENSEARCH="${PURGE_OPENSEARCH:-false}"  # true para remover pacote do SO
LOG="/root/theme-algolia-$(date +%F-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

ok(){ echo -e "\e[32m✔ $*\e[0m"; }
info(){ echo -e "\e[34m➜ $*\e[0m"; }
warn(){ echo -e "\e[33m⚠ $*\e[0m"; }
err(){ echo -e "\e[31m✘ $*\e[0m"; }
trap 'err "Falha na linha $LINENO: $BASH_COMMAND. Log: $LOG"; exit 1' ERR
[[ $EUID -eq 0 ]] || { err "Execute como root (sudo)."; exit 1; }

as_app_env() {
  local home; home="$(getent passwd "$APP_USER" | cut -d: -f6)"; [[ -z "$home" ]] && home="/var/www"
  mkdir -p "$home/.composer" /var/tmp/composer-tmp "$WEBROOT"
  chown -R "$APP_USER":www-data "$home/.composer" "$WEBROOT" /var/tmp/composer-tmp
  chmod 700 "$home/.composer"; chmod 2755 "$WEBROOT"
  sudo -u "$APP_USER" -H bash -lc "cd '$WEBROOT' && $*"
}

command -v php >/dev/null || { err "PHP não encontrado"; exit 1; }
command -v composer >/dev/null || { err "Composer não encontrado"; exit 1; }
[[ -d "$WEBROOT" ]] || { err "WEBROOT não existe: $WEBROOT"; exit 1; }

# 0) Engine de busca: manter 'opensearch' só na CONFIG (serviço pode ficar parado)
info "Mantendo engine como 'opensearch' para compatibilidade e usando Algolia na loja…"
as_app_env "php bin/magento config:set catalog/search/engine opensearch"
as_app_env "php bin/magento config:set catalog/search/opensearch_server_hostname 127.0.0.1"
as_app_env "php bin/magento config:set catalog/search/opensearch_server_port 9200"
as_app_env "php bin/magento cache:flush || true"

# 1) Parar (e opcionalmente remover) OpenSearch no SO para poupar RAM
if systemctl list-unit-files | grep -q '^opensearch\.service'; then
  info "Desabilitando serviço OpenSearch (sem afetar config)…"
  systemctl disable --now opensearch || true
  if [[ "${PURGE_OPENSEARCH}" == "true" ]]; then
    info "Removendo pacote OpenSearch…"
    DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Use-Pty=0 purge -y opensearch || true
    DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Use-Pty=0 autoremove -y || true
  fi
fi

# 2) Swissup Marketplace
info "Instalando/Reinstalando Swissup Marketplace…"
as_app_env "composer require swissup/module-marketplace --no-interaction --with-all-dependencies"
as_app_env "php -d memory_limit=1024M bin/magento setup:upgrade --safe-mode=1"

# 3) Breeze
info "Instalando Breeze (swissup/breeze-blank) e habilitando módulos…"
as_app_env "composer require swissup/breeze-blank --no-interaction --with-all-dependencies"
as_app_env "php bin/magento module:enable Swissup_Breeze Swissup_Rtl || true"
as_app_env "php -d memory_limit=1024M bin/magento setup:upgrade"

# 4) Build low-mem (sem reindex de catalogsearch_fulltext)
info "Compilando e gerando estáticos (baixo consumo)…"
as_app_env "rm -rf var/cache/* var/page_cache/* generated/* || true"
as_app_env "php -d memory_limit=1024M bin/magento setup:di:compile"
as_app_env "php -d memory_limit=1024M bin/magento setup:static-content:deploy -f pt_BR en_US -j 1"

# 5) Limpeza e índices (evita tocar no catalogsearch_fulltext)
as_app_env "php bin/magento cache:flush"
as_app_env "php bin/magento indexer:reindex || true"

ok "Tema Breeze pronto e Magento compatível com Algolia (sem exigir OpenSearch em execução)."
echo "Log: $LOG"
