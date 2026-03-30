FROM python:3.11-slim

WORKDIR /app

# Security: non-root user
RUN groupadd -r trading && useradd -r -g trading trading

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

RUN chown -R trading:trading /app
USER trading

# Default: paper mode
ENV PAPER_MODE=true
ENV SINGLE_CYCLE=false

CMD ["python", "main.py"]
