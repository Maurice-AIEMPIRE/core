FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY *.py .

# Health check: process is alive
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD python -c "import os; os.kill(1, 0)" || exit 1

CMD ["python", "bot_manager.py"]
