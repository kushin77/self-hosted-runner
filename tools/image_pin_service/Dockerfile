FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
ENV PORT=8080
EXPOSE 8080
# Use gunicorn if available; fall back to the built-in Flask server for reliable startup
CMD ["sh", "-c", "if command -v gunicorn >/dev/null 2>&1; then exec gunicorn --bind 0.0.0.0:${PORT} app:app --workers 2; else exec python -u app.py; fi"]
