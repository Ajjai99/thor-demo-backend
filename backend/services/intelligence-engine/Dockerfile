FROM python:3.13-alpine
# Debian-based slim/bookworm both carried 20+ CRITICAL/HIGH CVEs in base OS packages (perl, ncurses, util-linux, zlib, libssh2) unrelated to this app, unfixed on either release per Trivy. Alpine's base scans clean (0 CRITICAL/HIGH) since it doesn't ship that package set.
RUN apk add --no-cache curl
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 8080
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
