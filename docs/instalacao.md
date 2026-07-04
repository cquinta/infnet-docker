# INSTALACAO DO DOCKER

## DOCKER DESKTOP

Para instalar o DOCKER DESTOP no windows siga a [documentação oficial de instalação](https://docs.docker.com/desktop/setup/install/windows-install)

## Ubuntu

Para instalar o Docker no Ubuntu, siga a [documentação oficial de instalação](https://docs.docker.com/engine/install/ubuntu/).

Para o curso vamos utilizar a instalação via script

```bash

curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh ./get-docker.sh --dry-run

```
### Tarefas Pós Instalação

#### Criação de um grupo Unix chamado docker e adição dos susuários a ele. 

Quando o daemon do Docker inicia, ele cria um socket Unix acessível pelos membros do grupo docker. Em algumas distribuições Linux, o sistema cria automaticamente esse grupo ao instalar o Docker Engine usando um gerenciador de pacotes. Nesse caso, não há necessidade de você criar o grupo manualmente.

```bash
sudo groupadd docker
sudo usermod -aG docker $USER
``` 
Execute o login novamente e teste o funcionamento

```bash
docker run hello-world
```

#### Configuração do Docker para iniciar automáticamente no boot com systemd

Muitas distribuições Linux modernas utilizam o systemd para gerenciar quais serviços iniciam quando o sistema é inicializado. 
Para iniciar automaticamente o Docker e o containerd na inicialização utilizando o systemd, execute os seguintes comandos:

```bash
sudo systemctl enable docker.service
sudo systemctl enable containerd.service
```


