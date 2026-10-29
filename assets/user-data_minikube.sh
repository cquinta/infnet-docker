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

# Instalando o kubectl
echo "---Iniciando instalação do kubectl---"
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

   

# Instalando o minikube
echo "---Iniciando instalação do minikube---"
curl -LO https://github.com/kubernetes/minikube/releases/latest/download/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube && rm minikube-linux-amd64
