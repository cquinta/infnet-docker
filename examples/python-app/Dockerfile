FROM python:3.13-slim
#FROM dhi.io/python:3.12
#RUN apt-get update && apt-get upgrade -y gzip perl libacl1
RUN groupadd -r appuser && useradd -r -g appuser appuser
WORKDIR /app
WORKDIR /app
RUN python3 -m venv /venv
ENV PATH="/venv/bin:$PATH"
COPY . .
RUN pip install -r requirements.txt
RUN chown -R appuser:appuser /app
USER appuser
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000" ]