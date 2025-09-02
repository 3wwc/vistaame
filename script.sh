#!/usr/bin/env bash
set -Eeuo pipefail

# ====== VARS (ajuste se quiser) ======
DOMAIN="${DOMAIN:-vistaame.com.br}"
APP_USER="${APP_USER:-www-data}"
WEBROOT="${WEBROOT:-/var/www/$DOMAIN}"
PURGE_OPENSEARCH="${PURGE_OPENSEARCH:-false}"  # true = remove pacote do SO
PHPV="${PHPV:-8.3}"                            # troque se usa 8.4

LOG="/root/theme-algolia-$(date +%F-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

ok()   { echo -e "\e[32m✔ $*\e[0m"; }
info() { echo -e "\e[34m➜ $*\e[0m"; }
warn() { echo -e "\e[33m⚠ $*\e[0m"; }
err()  { echo -e "\e[31m✘ $*\e[0m"; }
trap 'err "Falha na linha $LINENO: $BASH_COMMAND. Log: $LOG"; exit 1' ERR
require_root() { [[ $EUID -eq 0 ]] || { err "Execute como root (sudo)."; exit 1; }; }

as_app_env() {
  local home tmp="/tmp"
  home="$(getent passwd "$APP_USER" | cut -d: -f6)"; [[ -z "$home" ]] && home="/var/www"
  mkdir -p "$home/.composer" /var/tmp/composer-tmp "$WEBROOT"
  chown -R "$APP_USER":www-data "$home/.composer" "$WEBROOT" /var/tmp/composer-tmp
  chmod 700 "$home/.composer"; chmod 2755 "$WEBROOT"
  # se /tmp tiver noexec, usa /var/tmp
  mount | grep -q " /tmp " && mount | grep -q " /tmp .*noexec" && tmp="/var/tmp"
  sudo -u "$APP_USER" -H env -i \
    HOME="$home" PATH="/usr/local/bin:/usr/bin:/bin" \
    COMPOSER_HOME="$home/.composer" TMPDIR="$tmp/composer-tmp" \
    bash -lc "$*"
}

require_root
command -v php >/dev/null || { err "PHP não encontrado"; exit 1; }
command -v composer >/dev/null || { err "Composer não encontrado"; exit 1; }
[[ -d "$WEBROOT" ]] || { err "WEBROOT não existe: $WEBROOT"; exit 1; }

# ====== 0) Desligar OpenSearch no Magento (usar somente Algolia/MySQL) ======
info "Ajustando engine de busca para MySQL e desligando dependência do OpenSearch…"
as_app_env "php $WEBROOT/bin/magento config:set catalog/search/engine mysql"
as_app_env "php $WEBROOT/bin/magento indexer:reindex catalogsearch_fulltext || true"
as_app_env "php $WEBROOT/bin/magento cache:flush"

# ====== 1) Parar (e opcionalmente remover) o serviço OpenSearch ======
if systemctl list-unit-files | grep -q '^opensearch\.service'; then
  info "Parando e desabilitando OpenSearch no sistema…"
  systemctl disable --now opensearch || true
  if [[ "${PURGE_OPENSEARCH}" == "true" ]]; then
    info "Removendo pacote OpenSearch (opcional)…"
    DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Use-Pty=0 purge -y opensearch || true
    DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Use-Pty=0 autoremove -y || true
  fi
else
  warn "OpenSearch não encontrado como serviço; seguindo."
fi

# ====== 2) Instalar/Reinstalar Swissup Marketplace ======
info "Instalando/Reinstalando Swissup Marketplace (Composer)…"
as_app_env "composer require swissup/module-marketplace --no-interaction --with-all-dependencies"
as_app_env "php -d memory_limit=1024M $WEBROOT/bin/magento setup:upgrade --safe-mode=1"

# ====== 3) Instalar Breeze (Composer) e habilitar módulos ======
info "Instalando Breeze (swissup/breeze-blank) e habilitando módulos…"
as_app_env "composer require swissup/breeze-blank --no-interaction --with-all-dependencies"
as_app_env "php $WEBROOT/bin/magento module:enable Swissup_Breeze Swissup_Rtl || true"
as_app_env "php -d memory_limit=1024M $WEBROOT/bin/magento setup:upgrade"

# ====== 4) Compilar (low-mem) e deploy de estáticos com poucas jobs ======
info "Compilando DI (low-mem) e gerando estáticos…"
as_app_env "rm -rf $WEBROOT/var/cache/* $WEBROOT/var/page_cache/* $WEBROOT/generated/* || true"
as_app_env "php -d memory_limit=1024M $WEBROOT/bin/magento setup:di:compile"
as_app_env "php -d memory_limit=1024M $WEBROOT/bin/magento setup:static-content:deploy -f pt_BR en_US -j 1"

# ====== 5) Limpeza e índices ======
as_app_env "php $WEBROOT/bin/magento cache:flush"
as_app_env "php $WEBROOT/bin/magento indexer:reindex"

ok "Tema Breeze instalado e Magento ajustado para Algolia/MySQL."

cat <<EOF

Dicas finais:
- Ative o tema Breeze pelo Admin (Conteúdo → Design → Configuração → Escolha "Breeze Blank" no escopo).
- Certifique-se de que o Algolia está com as credenciais em Stores → Algolia Search.
- Se quiser remover totalmente OpenSearch do APT, rode com: PURGE_OPENSEARCH=true ./$(basename "$0")

Log desta execução: $LOG
EOF
