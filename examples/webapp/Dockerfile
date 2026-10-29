FROM nginx:alpine

# Template da página inicial e script de entrada
COPY index.html.template /usr/share/nginx/html/index.html.template
COPY docker-entrypoint.sh /docker-entrypoint.sh

RUN chmod +x /docker-entrypoint.sh

EXPOSE 80

# Ao subir o container, gera a página com o hostname atual e inicia o nginx
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
