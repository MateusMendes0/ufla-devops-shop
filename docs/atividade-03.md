# Atividade 3 — deploy da loja

Testei esta execução no Ubuntu do WSL2. O WSL já tinha PostgreSQL e
Redis, mas a aplicação e o Nginx ainda não estavam instalados. O primeiro teste
mostrou que o banco `loja` preexistente precisava liberar acesso ao esquema
`public` para `ufla-shop`; ajustei o `deploy.sh` e repeti tudo abaixo.

## Como rodar em uma máquina limpa

Use Ubuntu ou Debian com `systemd` ativo. No WSL, `ps -p 1 -o comm=` deve mostrar
`systemd`. Depois de clonar o repositório, entre na pasta e execute:

```bash
sudo bash scripts/deploy.sh
```

O script instala os pacotes necessários, cria o usuário e o banco quando ainda
não existem, copia a aplicação para `/opt/ufla-shop`, configura os serviços e o
Nginx e consulta `/ready`. A primeira execução cria `/etc/ufla-shop.env` a partir
do exemplo. Se for preciso mudar a conexão do banco, edite esse arquivo em
`/etc`; as próximas execuções do deploy preservam seu conteúdo. O certificado
TLS é autoassinado, por isso o teste local usa `curl -k`.

## Reinício automático

No WSL, `pidof uvicorn` não encontrou o processo porque o executável aparece
como um script Python. Peguei o PID principal pelo systemd: era `9544`. Enviei
`kill -9 9544` como root, aguardei mais de cinco segundos e consultei o status.
O novo PID, `9875`, e a linha de reinício confirmam que o serviço voltou.

```text
$ systemctl status ufla-shop.service --no-pager --full
● ufla-shop.service - UFLA Shop API
     Loaded: loaded (/etc/systemd/system/ufla-shop.service; enabled; preset: enabled)
     Active: active (running) since Sun 2026-09-27 10:39:23 -03; 15s ago
 Invocation: 9539f2f6bd834b319350a8d64122b3fa
   Main PID: 9875 (uvicorn)
      Tasks: 1 (limit: 9452)
     Memory: 47.8M (peak: 47.8M)
        CPU: 409ms
     CGroup: /system.slice/ufla-shop.service
             └─9875 /opt/ufla-shop/.venv/bin/python /opt/ufla-shop/.venv/bin/uvicorn app:api --host 127.0.0.1 --port 8000

Sep 27 10:39:23 DESKTOP-MATEUS systemd[1]: ufla-shop.service: Scheduled restart job, restart counter is at 1.
Sep 27 10:39:23 DESKTOP-MATEUS systemd[1]: Started ufla-shop.service - UFLA Shop API.
Sep 27 10:39:23 DESKTOP-MATEUS uvicorn[9875]: INFO:     Started server process [9875]
Sep 27 10:39:23 DESKTOP-MATEUS uvicorn[9875]: INFO:     Waiting for application startup.
Sep 27 10:39:23 DESKTOP-MATEUS uvicorn[9875]: 2026-09-27 10:39:23,844 INFO loja: ufla-devops-shop 1.0.0 subindo (banco=postgresql, cache=redis, instancia=DESKTOP-MATEUS)
Sep 27 10:39:23 DESKTOP-MATEUS uvicorn[9875]: 2026-09-27 10:39:23,904 INFO loja.banco: banco pronto (modo postgresql)
Sep 27 10:39:23 DESKTOP-MATEUS uvicorn[9875]: INFO:     Application startup complete.
Sep 27 10:39:23 DESKTOP-MATEUS uvicorn[9875]: INFO:     Uvicorn running on http://127.0.0.1:8000 (Press CTRL+C to quit)
```

## HTTP e HTTPS

O Nginx recebe as conexões externas. A API permanece em `127.0.0.1:8000`.
Estas são as respostas dos dois comandos pedidos, sem a barra de progresso que
o `curl` escreve no terminal:

```text
$ curl -kI https://localhost
HTTP/1.1 200 OK
Server: nginx/1.28.3 (Ubuntu)
Date: Sun, 27 Sep 2026 13:40:53 GMT
Content-Type: text/html; charset=utf-8
Content-Length: 1305
Connection: keep-alive
accept-ranges: bytes
last-modified: Sun, 27 Sep 2026 12:53:14 GMT
etag: "eafdead672f1086dcba9226da815a244"

$ curl -I http://localhost
HTTP/1.1 301 Moved Permanently
Server: nginx/1.28.3 (Ubuntu)
Date: Sun, 27 Sep 2026 13:40:53 GMT
Content-Type: text/html
Content-Length: 178
Connection: keep-alive
Location: https://localhost/
```

## Três backups

Rodei `sudo systemctl start ufla-shop-backup.service` três vezes, em minutos
diferentes, porque o nome do arquivo usa hora e minuto. Os três arquivos foram
gerados e o serviço registrou cada execução no journal.

```text
$ sudo ls -la /var/backups/ufla-shop
total 20
drwxr-x--- 2 ufla-shop ufla-shop 4096 Sep 27 10:40 .
drwxr-xr-x 3 root      root      4096 Sep 27 10:36 ..
-rw------- 1 ufla-shop ufla-shop 1755 Sep 27 10:38 loja-2026-09-27-1038.sql.gz
-rw------- 1 ufla-shop ufla-shop 1752 Sep 27 10:39 loja-2026-09-27-1039.sql.gz
-rw------- 1 ufla-shop ufla-shop 1754 Sep 27 10:40 loja-2026-09-27-1040.sql.gz
```

## Duas execuções seguidas do deploy

Depois dos ajustes, rodei `sudo bash scripts/deploy.sh` duas vezes seguidas.
Ambas terminaram com código 0 e com o healthcheck bem-sucedido. Estas são as
últimas cinco linhas de cada execução:

```text
Primeira execução:
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
Synchronizing state of nginx.service with SysV service script with /usr/lib/systemd/systemd-sysv-install.
Executing: /usr/lib/systemd/systemd-sysv-install enable nginx
Deploy realizado com sucesso.

Segunda execução:
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
Synchronizing state of nginx.service with SysV service script with /usr/lib/systemd/systemd-sysv-install.
Executing: /usr/lib/systemd/systemd-sysv-install enable nginx
Deploy realizado com sucesso.
```
