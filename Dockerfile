FROM julia:1.12.5-bookworm

RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY . .

ENV HOST=0.0.0.0 \
    PORT=8080 \
    JULIA_EXE=/usr/local/bin/julia \
    COMPUTE_TIMEOUT_SECONDS=120 \
    MAX_NODES=80 \
    MAX_REQUEST_BYTES=1048576 \
    PYTHONUNBUFFERED=1

EXPOSE 8080

CMD ["python3", "server/compute_server.py"]
