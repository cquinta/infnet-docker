#!/bin/sh
set -e

# Gera a página inicial substituindo o placeholder pelo hostname do container.
# Isso roda a cada start do container, garantindo o hostname correto.
sed "s/__HOSTNAME__/$(hostname)/g" \
    /usr/share/nginx/html/index.html.template \
    > /usr/share/nginx/html/index.html

# Executa o comando passado (por padrão, inicia o nginx em foreground)
exec "$@"
