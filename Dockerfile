# Primeiro estágio: instala somente as dependências de execução.
FROM python:3.12-alpine AS dependencias

WORKDIR /construcao
COPY requirements.txt ./

RUN python -m pip install \
    --no-cache-dir \
    --no-compile \
    --only-binary=:all: \
    --prefix=/instalacao \
    -r requirements.txt

# Segundo estágio: recebe as dependências prontas, a API e o front estático.
FROM python:3.12-alpine AS execucao

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN addgroup -S -g 10001 loja \
    && adduser -S -D -H -u 10001 -G loja loja \
    && mkdir /loja \
    && chown loja:loja /loja

WORKDIR /loja

COPY --from=dependencias /instalacao/ /usr/local/
COPY app/ ./app/
COPY static/ ./static/

# O usuário pode criar o SQLite em /loja sem precisar de privilégios de root.
USER 10001:10001

EXPOSE 8000

# Usa a biblioteca padrão do Python para dispensar curl na imagem.
HEALTHCHECK --interval=5s --timeout=2s --start-period=2s --retries=3 \
    CMD ["python", "-c", "import urllib.request; resposta = urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=1); raise SystemExit(0 if resposta.status == 200 else 1)"]

# A forma exec entrega SIGTERM diretamente ao Uvicorn, que será o PID 1.
CMD ["uvicorn", "app:api", "--host", "0.0.0.0", "--port", "8000"]
