# syntax=docker/dockerfile:1

# Pinned, slim base. Not `python:3.12` (≈1GB of build tooling you never use)
# and not `latest` — the same manifest must build the same image next month.
FROM python:3.12-slim AS runtime

# Don't write .pyc files; don't buffer stdout, or logs arrive late in
# `kubectl logs` and you spend an hour debugging a phantom hang.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

# NOTE: build context is the REPO ROOT, not backend/, so the frontend can be
# copied in too:   docker build -f backend/Dockerfile -t <tag> .
#
# Dependencies before source, as a separate layer. Editing main.py then leaves
# the (slow) pip layer cached and only rebuilds the (fast) copies below it.
COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY backend/main.py .
COPY frontend/ ./static/

# Run as a non-root user with no login shell and no home directory to write to.
# Containers run as root by default, and root in a container is root on the
# host kernel — a container breakout lands you somewhere much worse. In M6 the
# Pod spec will *enforce* this with runAsNonRoot, so the cluster refuses to
# start the image even if someone rebuilds it carelessly.
RUN useradd --system --no-create-home --shell /usr/sbin/nologin --uid 10001 app \
    && chown -R app:app /app
USER 10001

# Documentation only, exactly like containerPort in a Pod spec. It opens nothing.
EXPOSE 8000

# 0.0.0.0, not 127.0.0.1 — the Pod's network namespace has its own interface,
# and binding to loopback would make the container unreachable from the Service.
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
