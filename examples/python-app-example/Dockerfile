FROM python:3.13-slim
RUN groupadd -r appuser && useradd -r -g appuser appuser

#RUN apt-get update && apt-get upgrade -y gzip perl libacl1
RUN apt-get update -y && apt-get install curl -y
WORKDIR /app
#RUN python3 -m venv /venv
#ENV PATH="/venv/bin:$PATH"
COPY . .
RUN pip install -r requirements.txt
RUN chown -R appuser:appuser /app
USER appuser
HEALTHCHECK --interval=10s --timeout=5s --start-period=5s --retries=3 CMD curl -f http://localhost:8000 || exit 1
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000" ]