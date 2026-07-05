python3 -m venv .venv
 source .venv/bin/activate
 pip install -r requirements.txt
 uvicorn main:app --reload
 
 
 # Trivy
 trivy image --severity CRITICAL,HIGH teste

 trivy config Dockerfile

 trivy image --scanners vuln dhi.io/python:3.13

 trivy image --severity CRITICAL,HIGH --ignore-unfixed <NOME_DA_IMAGEM>