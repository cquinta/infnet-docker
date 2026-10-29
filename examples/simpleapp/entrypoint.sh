#!/bin/sh

# Gera o index.html com o hostname atual do container
cat <<EOF > /usr/share/nginx/html/index.html
<!DOCTYPE html>
<html lang="pt-br">
<head>
    <meta charset="UTF-8">
    <title>Nginx Hostname</title>
    <style>
        body { font-family: sans-serif; text-align: center; margin-top: 50px; background: #f0f0f0; }
        .card { background: white; padding: 20px; border-radius: 8px; display: inline-block; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
    </style>
</head>
<body>
    <div class="card">
        <h1>Servidor Nginx</h1>
        <p>Hostname do Container:</p>
        <h2>$(hostname)</h2>
    </div>
</body>
</html>
EOF

# Inicia o Nginx em primeiro plano
exec "$@"