# Exemplo: Nginx com Ubuntu 22.04

Container web com nginx servindo uma página HTML personalizada.

## Estrutura

```
examples/nginx/
├── Dockerfile
├── index.html
├── start.sh
└── README.md
```

## Pré-requisitos

- Docker instalado e em execução
- Porta 80 disponível no host

---

## Dockerfile

O `Dockerfile` utiliza as seguintes instruções:

| Instrução | Descrição |
|-----------|-----------|
| `FROM` | Imagem base `ubuntu:22.04` |
| `RUN` | Instala o nginx via `apt-get` |
| `ENV` | Define a variável de ambiente `estagio=dev` |
| `COPY` | Copia `index.html` para `/var/www/html/index.html` |
| `EXPOSE` | Declara a porta `80` |
| `CMD` | Inicia o nginx em foreground (`daemon off`) |

```dockerfile
FROM ubuntu:22.04
RUN apt-get update -y && apt-get install nginx -y
ENV estagio=dev
COPY index.html /var/www/html/index.html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

---

## Roteiro de Execução

### 1. Construir a imagem

```bash
docker build -t teste .
```

Verifique se a imagem foi criada:

```bash
docker images | grep teste
```

### 2. Criar e iniciar o container

```bash
docker run -d -p 80:80 --restart always --name webserver01 teste
```

| Flag | Descrição |
|------|-----------|
| `-d` | Executa em background |
| `-p 80:80` | Redireciona porta 80 do host para porta 80 do container |
| `--restart always` | Reinicia automaticamente em caso de falha ou reboot |
| `--name webserver01` | Nomeia o container |

### 3. Verificar o container em execução

```bash
docker ps | grep webserver01
```

### 4. Acessar a aplicação

Abra o navegador em:

```
http://localhost
```

Ou via terminal:

```bash
curl http://localhost
```

### 5. Verificar a variável de ambiente

```bash
docker exec webserver01 printenv estagio
# Saída esperada: dev
```

### 6. Inspecionar logs do nginx

```bash
docker logs webserver01
```
### 7. Testar a política restart

```bash
docker exec webserver01 pkill nginx
``` 

---

## Limpeza

```bash
# Parar o container
docker stop webserver01

# Remover o container
docker rm webserver01

# Remover a imagem
docker rmi teste
```

