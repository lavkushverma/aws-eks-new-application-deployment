FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

RUN addgroup --system app && adduser --system --ingroup app app

COPY requirements.txt .
RUN pip install --no-cache-dir --no-compile -r requirements.txt

COPY app/ ./app/

USER app

EXPOSE 8080

CMD ["python", "app/app.py"]
