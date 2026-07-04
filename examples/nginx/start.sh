docker build -t teste .
docker run -d -p 80:80 --restart always --name webserver01 teste
docker exec webserver01 pkill nginx