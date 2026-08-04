#!/bin/bash
echo "---Iniciando instalação do docker---"
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
echo "---Configurando permissões para o usuário ubuntu---"
usermod -aG docker ubuntu
sudo newgrp  docker
echo "---Habilitando e iniciando o serviço do Docker---"
sudo systemctl enable docker
sudo systemctl start docker