# INSTALACAO DO DOCKER COMPOSE - LINUX

## Ubuntu

Para instalar o Docker compose no Ubuntu, siga a [documentação oficial de instalação](https://docs.docker.com/compose/install/linux/#install-the-plugin-manually).

Para o curso vamos utilizar a instalação manual

```bash
DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
mkdir -p $DOCKER_CONFIG/cli-plugins
curl -SL https://github.com/docker/compose/releases/download/v5.1.2/docker-compose-linux-x86_64 -o $DOCKER_CONFIG/cli-plugins/docker-compose

```
### Tarefas Pós Instalação

#### Instalação para todos os usuáriosCriação de um grupo Unix chamado docker e adição dos susuários a ele. 

```bash
chmod +x $DOCKER_CONFIG/cli-plugins/docker-compose
sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
docker compose version

``` 

