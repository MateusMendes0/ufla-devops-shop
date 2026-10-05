# Atividade 4 — Docker

## 1. Imagem inicial e final

Como a Parte 2 já começou otimizada, reconstruí uma versão funcional com slim,
cache do pip e bytecode para comparação.

```text
$ docker images --filter reference=ufla-shop:inicial --filter reference=ufla-shop:1.0
IMAGE               ID             DISK USAGE   CONTENT SIZE   EXTRA
ufla-shop:1.0       4741bd081cea        125MB         29.2MB   U
ufla-shop:inicial   cb67498e1316        285MB           74MB   U
```

| Medida | Inicial | Final |
|--------|---------|-------|
| `docker images` (uso em disco) | 285 MB | 125 MB |
| Camadas descompactadas (`docker history`) | 210,92 MB | **95,85 MB** |

Neste Docker Desktop, o uso em disco inclui conteúdo comprimido e descompactado;
a soma das camadas confirma que a final tem menos de 150 MB descompactados.

## 2. O que mudou

Economia descompactada, medida comparando uma mudança por vez com `docker history`:

| Mudança | Economia |
|---------|----------|
| `--no-cache-dir`: não guardar downloads do pip | 13,14 MB |
| `--no-compile`: não gerar bytecode das dependências | 20,14 MB |
| Multi-stage: deixar arquivos de instalação no builder | 12 KiB |
| Trocar slim por Alpine, com wheels para musl | 81,78 MB |

**Economia total: 115,07 MB (54,56%).** O multi-stage economizou pouco porque
cache e bytecode já tinham sido retirados na etapa anterior.

A imagem recebe somente dependências de execução, `app/` e `static/`.
O `.dockerignore` exclui Git, ambiente virtual, testes, caches, bancos e `.env`;
essas exclusões já estavam nas duas versões e não entram na economia acima.

## 3. Verificação

Build: `docker build -t ufla-shop:1.0 .`. Usei `8002:8000` porque a porta 8000
estava ocupada; a loja rodou com SQLite e cache em memória.

```text
$ docker image inspect --format '{{.Size}}' ufla-shop:1.0 | numfmt --to=si
30M

$ docker run --rm ufla-shop:1.0 id -u
10001

$ docker run --rm ufla-shop:1.0 ls -a
.
..
app
static

$ docker inspect --format '{{.State.Health.Status}}' loja
healthy

$ curl.exe -fsS -w '\nHTTP %{http_code}\n' http://localhost:8002/health
{"status":"ok","versao":"1.0.0"}
HTTP 200

$ time docker stop loja
loja
real    0m1.102s
user    0m0.013s
sys     0m0.010s

$ docker inspect --format '{{.State.ExitCode}}' loja
0
```

`inspect .Size` mostrou o conteúdo comprimido neste Docker Desktop.
`GET /api/produtos` retornou **12 produtos** nas duas versões; a parada final
levou **1,102 s**, com saída zero.

## 4. Por que `/health` e não `/ready`?

O HEALTHCHECK consulta `/health` porque ela verifica se a aplicação está viva, sem depender do banco ou do cache. Já `/ready` verifica essas dependências e poderia indicar falha mesmo com o processo da aplicação funcionando.
