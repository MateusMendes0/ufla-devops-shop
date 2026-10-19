# Atividade 5 — Docker Compose e GHCR

## 1. Serviços saudáveis

Para verificar o status da execução da stack utilizando a imagem que publiquei no GitHub Container Registry (GHCR), executei o comando `docker compose ps`:

```text
NAME                       IMAGE                                   COMMAND                  SERVICE   CREATED              STATUS                        PORTS
ufla-devops-shop-api-1     ghcr.io/mateusmendes0/ufla-shop:1.0.0   "uvicorn app:api --h…"   api       About a minute ago   Up About a minute (healthy)   8000/tcp
ufla-devops-shop-banco-1   postgres:16-alpine                      "docker-entrypoint.s…"   banco     4 minutes ago        Up 4 minutes (healthy)        5432/tcp
ufla-devops-shop-cache-1   redis:7-alpine                          "docker-entrypoint.s…"   cache     4 minutes ago        Up 4 minutes (healthy)        6379/tcp
ufla-devops-shop-nginx-1   nginx:1.27-alpine                       "/docker-entrypoint.…"   nginx     4 minutes ago        Up 4 minutes (healthy)        0.0.0.0:80->80/tcp, [::]:80->80/tcp
```

Como é possível observar, os quatro serviços estão com o status `healthy`. Mantive apenas o Nginx expondo a porta 80 no host; as portas `8000/tcp`, `5432/tcp` e `6379/tcp` não possuem mapeamento para a máquina hospedeira, operando exclusivamente na rede interna do Docker.

## 2. Prova de persistência

No meu ambiente local, já havia uma instância do Nginx em execução no WSL ocupando a porta `localhost:80`. Devido a esse conflito no host, optei por executar as requisições de teste em Python diretamente de dentro do container da API, acessando `http://nginx` pela rede interna do Docker para passar pelo proxy reverso da aplicação normalmente.

Enviei uma requisição `POST http://nginx/api/produtos` com o seguinte payload:

```json
{"nome":"Prova de persistencia","preco":9.9,"estoque":1}
```

Abaixo está o registro obtido pelo script de validação, que também realizou a criação de um carrinho e confirmou o funcionamento completo da aplicação:

```text
{"produto_id":13,"carrinho_id":"c854237a2ea3","info":{"aplicacao":"ufla-devops-shop","versao":"1.0.0","banco":"postgresql","cache":"redis","instancia":"42def28b3dcb"}}
HEAD e GET via Nginx: 200. Produto criado: 201.
```

Em seguida, encerrei os containers executando `docker compose down` (sem o parâmetro `-v`, preservando os volumes nomeados) e reiniciei a stack com `docker compose up -d --wait`. Os logs abaixo ilustram esse processo (com as linhas intermediárias de criação e espera omitidas para melhor legibilidade):

```text
$ docker compose down
 Container ufla-devops-shop-nginx-1 Stopped
 Container ufla-devops-shop-nginx-1 Removed
 Container ufla-devops-shop-api-1 Stopped
 Container ufla-devops-shop-api-1 Removed
 Container ufla-devops-shop-cache-1 Stopped
 Container ufla-devops-shop-cache-1 Removed
 Container ufla-devops-shop-banco-1 Stopped
 Container ufla-devops-shop-banco-1 Removed
 Network ufla-devops-shop_default Removed

$ docker compose up -d --wait
 Container ufla-devops-shop-banco-1 Healthy
 Container ufla-devops-shop-cache-1 Healthy
 Container ufla-devops-shop-api-1 Healthy
 Container ufla-devops-shop-nginx-1 Healthy
```

Após a recriação dos containers, executei a consulta `GET http://nginx/api/busca?q=persistencia` para validar se o registro permaneceu íntegro, obtendo o produto cadastrado com `"total": 1`:

```json
{"termo": "persistencia", "total": 1, "resultados": [{"id": 13, "nome": "Prova de persistencia", "descricao": "", "preco": 9.9, "estoque": 1, "criado_em": "2026-10-19T13:10:10.573746+00:00"}]}
```

Saída final do teste:

```text
Persistencia confirmada: produto no PostgreSQL e carrinho no Redis apos down/up.
```

O resultado confirma que o volume `banco_dados` manteve os dados persistidos no PostgreSQL e que o Redis também preservou as informações do carrinho através do modo AOF em conjunto com o volume `cache_dados`.

## 3. Imagem pública no GHCR

A imagem construída e publicada para a atividade é: `ghcr.io/mateusmendes0/ufla-shop:1.0.0`.

O pacote é público e pode ser inspecionado na página: [ufla-shop no GitHub Packages](https://github.com/users/MateusMendes0/packages/container/package/ufla-shop).

Para comprovar que a imagem pode ser baixada por qualquer usuário sem necessidade de autenticação prévia, executei o `docker pull` com um arquivo de configuração temporário contendo `{"auths":{}}` (sem credenciais ativas):

```text
1.0.0: Pulling from mateusmendes0/ufla-shop
Digest: sha256:932746d091bd18543ac326472f9b6bd6a6260b1f76263ed23ee913bbb76e225b
Status: Image is up to date for ghcr.io/mateusmendes0/ufla-shop:1.0.0
ghcr.io/mateusmendes0/ufla-shop:1.0.0
```

No arquivo `compose.yaml`, o serviço `api` referencia diretamente essa imagem pública utilizando a tag de versionamento semântico `1.0.0`.

## 4. Por que usar `service_healthy`?

A utilização do `depends_on` em sua forma padrão apenas define a ordem de inicialização dos containers, mas não assegura que as aplicações internas estejam prontas para aceitar conexões de rede. Isso faria com que a API tentasse se comunicar com o banco de dados e com o cache antes de estarem operacionais, gerando falhas logo na inicialização.

Ao utilizar a diretiva `condition: service_healthy`, o Docker Compose aguarda que o healthcheck de cada dependência seja concluído com êxito antes de iniciar os serviços dependentes. Dessa maneira, garanti que a API só seja iniciada após `pg_isready` (no PostgreSQL) e `redis-cli ping` (no Redis) confirmarem a plena disponibilidade de ambos os serviços.
