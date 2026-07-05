# Exemplo de Aplicação Python FastAPI

Este é um exemplo simples de uma aplicação Python usando o framework FastAPI, conteinerizada com Docker.

## Descrição

A aplicação oferece um único endpoint `/` que retorna uma mensagem JSON "Hello World".

Este projeto inclui múltiplos Dockerfiles para demonstrar diferentes abordagens de conteinerização:

*   `Dockerfile`: Um Dockerfile direto que configura o ambiente, instala as dependências e executa a aplicação.
*   `Dockerfile.stages`: Um Dockerfile multi-estágios que primeiro constrói um ambiente virtual com as dependências em um estágio `builder`, e então as copia para uma imagem final menor. Esta é uma prática recomendada para criar imagens Docker otimizadas e mais seguras.

## Como Executar com Docker

### Construindo a Imagem

Você pode escolher qual Dockerfile usar.

**Usando `Dockerfile`:**

```bash
docker build -t python-app .
```

**Usando `Dockerfile.stages`:**

```bash
docker build -t python-app-staged -f Dockerfile.stages .
```

### Executando o Contêiner

Após construir a imagem, execute o contêiner:

```bash
docker run -d -p 8000:8000 --name my-python-app python-app
```

Ou, se você usou a construção multi-estágios:

```bash
docker run -d -p 8000:8000 --name my-python-app python-app-staged
```

### Acessando a Aplicação

Assim que o contêiner estiver em execução, você pode acessar a aplicação em [http://localhost:8000](http://localhost:8000) no seu navegador web ou usando uma ferramenta como `curl`:

```bash
curl http://localhost:8000
```

Você deverá ver a seguinte saída:

```json
{"message":"Hello World"}
```

## Arquivos

*   `main.py`: O arquivo principal da aplicação contendo o código FastAPI.
*   `requirements.txt`: Lista as dependências Python para o projeto.
*   `Dockerfile`: Um Dockerfile padrão para construir a imagem da aplicação.
*   `Dockerfile.stages`: Um Dockerfile multi-estágios para uma construção otimizada.
*   `start.sh`: Um script shell para configurar e executar a aplicação localmente.
*   `.dockerignore`: Especifica quais arquivos e diretórios excluir do contexto de build do Docker.
