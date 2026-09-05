FROM python:3.12-slim

RUN apt-get update \
    && apt-get install --no-install-recommends -y procps \
    && rm -rf /var/lib/apt/lists/*

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    RUNNERS_DASHBOARD_HOST=0.0.0.0 \
    RUNNERS_DASHBOARD_PORT=8765

WORKDIR /opt/actions-runners

COPY dashboard.py runners.sh prewarm-actions.sh runner-cache-env.sh ./
RUN chmod +x dashboard.py runners.sh prewarm-actions.sh

EXPOSE 8765

CMD ["python3", "dashboard.py"]