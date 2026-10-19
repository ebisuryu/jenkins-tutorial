FROM python:3.8 AS runtime

WORKDIR /app
RUN apt-get update \
    && apt-get install -y --no-install-recommends libgomp1 \
    && rm -rf /var/lib/apt/lists/*
COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir wheel 'cmake<4' \
    && pip install --no-cache-dir -r requirements.txt

RUN useradd --create-home --uid 10001 appuser
COPY app/main.py /app/main.py
COPY models /app/models
ENV MODEL_PATH=/app/models/model.pkl
EXPOSE 30000
USER appuser
HEALTHCHECK --interval=5s --timeout=3s --start-period=20s --retries=6 \
    CMD python -c "import json, urllib.request; d=json.load(urllib.request.urlopen('http://127.0.0.1:30000/health', timeout=2)); assert d['status']=='ok' and d['model_loaded']"
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "30000"]

FROM runtime AS test
USER root
COPY app /app/app
COPY tests /app/tests
COPY scripts /app/scripts
COPY ruff.toml /app/ruff.toml
COPY pytest.ini /app/pytest.ini
USER appuser
CMD ["sh", "-c", "ruff check --no-cache app tests scripts && python -m pytest -q --junitxml=/tmp/reports/junit.xml"]

FROM runtime AS production
