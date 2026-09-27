#!/usr/bin/env bash
set -euo pipefail

# 1. Usar Bash e interromper a execução em caso de erro.
# Executar com sudo em Ubuntu/Debian com systemd.
if [[ $EUID -ne 0 ]]; then
    echo "Execute com sudo: sudo bash scripts/deploy.sh" >&2
    exit 1
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    python3-venv python3-pip postgresql redis-server nginx openssl curl

# 2. Criar o usuário de sistema somente se ele ainda não existir.
id ufla-shop >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin ufla-shop
systemctl enable --now postgresql redis-server

# Autenticação peer pelo socket local: o usuário Linux ufla-shop acessa o banco
# com o mesmo nome de usuário, sem senha embutida no repositório.
if ! runuser -u postgres -- psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='ufla-shop'" | grep -qx 1; then
    runuser -u postgres -- psql -c 'CREATE ROLE "ufla-shop" LOGIN'
fi
if ! runuser -u postgres -- psql -tAc "SELECT 1 FROM pg_database WHERE datname='loja'" | grep -qx 1; then
    runuser -u postgres -- createdb --owner=ufla-shop loja
fi
# Também funciona quando o banco loja já existia com outro proprietário.
runuser -u postgres -- psql -d loja -c 'GRANT USAGE, CREATE ON SCHEMA public TO "ufla-shop"'
runuser -u postgres -- psql -d loja -c 'GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO "ufla-shop"'
runuser -u postgres -- psql -d loja -c 'GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA public TO "ufla-shop"'

# 3. Copiar a aplicação para /opt/ufla-shop, criar o venv e instalar requirements.txt.
# O arquivo de ambiente existente é preservado para não sobrescrever credenciais.
install -m 0644 "$REPO_DIR/config/ufla-shop.env.example" /etc/ufla-shop.env.example
if [[ ! -e /etc/ufla-shop.env ]]; then
    install -m 0600 /etc/ufla-shop.env.example /etc/ufla-shop.env
fi

install -d -o ufla-shop -g ufla-shop /opt/ufla-shop
cp -a "$REPO_DIR/app" "$REPO_DIR/static" /opt/ufla-shop/
install -m 0644 "$REPO_DIR/requirements.txt" /opt/ufla-shop/requirements.txt
install -d /opt/ufla-shop/scripts
install -m 0755 "$REPO_DIR/scripts/backup.sh" /opt/ufla-shop/scripts/backup.sh
if [[ ! -x /opt/ufla-shop/.venv/bin/python ]]; then
    python3 -m venv /opt/ufla-shop/.venv
fi
/opt/ufla-shop/.venv/bin/python -m pip install -r /opt/ufla-shop/requirements.txt
chown -R ufla-shop:ufla-shop /opt/ufla-shop
install -d -o ufla-shop -g ufla-shop -m 0750 /var/backups/ufla-shop

# 4. Instalar as units, recarregar o systemd e habilitar/reiniciar a aplicação.
install -m 0644 "$REPO_DIR/systemd/ufla-shop.service" /etc/systemd/system/
install -m 0644 "$REPO_DIR/systemd/ufla-shop-backup.service" /etc/systemd/system/
install -m 0644 "$REPO_DIR/systemd/ufla-shop-backup.timer" /etc/systemd/system/
systemctl daemon-reload
systemctl enable ufla-shop.service
systemctl restart ufla-shop.service
systemctl enable --now ufla-shop-backup.timer

# Configurar TLS e o proxy reverso do Nginx.
CERT=/etc/ssl/certs/ufla-shop.pem
KEY=/etc/ssl/private/ufla-shop.key
if [[ ! -f $CERT || ! -f $KEY ]]; then
    openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
        -keyout "$KEY" -out "$CERT" \
        -subj '/CN=localhost' -addext 'subjectAltName=DNS:localhost'
    chmod 0600 "$KEY"
fi
install -m 0644 "$REPO_DIR/nginx/loja.conf" /etc/nginx/sites-available/ufla-shop
ln -sfn /etc/nginx/sites-available/ufla-shop /etc/nginx/sites-enabled/ufla-shop
nginx -t
systemctl enable nginx
systemctl restart nginx

# 5. Consultar /ready até 10 vezes, com intervalo de 1 segundo; falhar sem HTTP 200.
for attempt in {1..10}; do
    if [[ $(curl -s -o /dev/null -w '%{http_code}' http://localhost:8000/ready || true) == 200 ]]; then
        echo "Deploy realizado com sucesso."
        exit 0
    fi
    sleep 1
done

echo "Healthcheck falhou; consulte journalctl -u ufla-shop.service." >&2
exit 1
