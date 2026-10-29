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


:set mouse=
:set paste

https://labs.iximiuz.com/signup?return_to=/playgrounds/docker-swarm

dashboards

14282 cadvisor
1860 hosts
23120 swarm

# Install yum-utils for managing repositories
sudo dnf install -y yum-utils shadow-utils


# Add the official HashiCorp RPM repository
# AL2023 is compatible with the RHEL repository
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo

# Install Terraform
sudo dnf install -y terraform

https://developer.hashicorp.com/terraform/install#linux


services:
  web:
    image: nginx:latest
    ports:
      - "8080:80"
    networks:
      - minha-rede-overlay

networks:
  minha-rede-overlay:
    driver: overlay
    attachable: true