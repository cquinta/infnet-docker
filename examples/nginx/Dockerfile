FROM ubuntu:22.04
RUN apt-get update -y && apt-get install nginx -y
ENV estagio=dev
COPY index.html /var/www/html/index.html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"] 
