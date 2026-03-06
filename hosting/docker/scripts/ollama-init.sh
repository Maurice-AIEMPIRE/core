#!/bin/bash
set -e

echo "Starting Ollama server..."
ollama serve &
OLLAMA_PID=$!

echo "Waiting for Ollama server to be ready..."
for i in $(seq 1 30); do
  if curl -sf http://localhost:11434/api/tags > /dev/null 2>&1; then
    echo "Ollama server is ready!"
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "ERROR: Ollama server failed to start within 30 seconds"
    exit 1
  fi
  sleep 1
done

echo "Pulling mxbai-embed-large model..."
ollama pull mxbai-embed-large

echo "Model pulled successfully!"
echo "Ollama is ready to accept requests."

# Keep the Ollama server running
wait $OLLAMA_PID
