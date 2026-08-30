FROM python:3.13-alpine
# Debian-based slim/bookworm both carried 20+ CRITICAL/HIGH CVEs in base OS packages (perl, ncurses, util-linux, zlib, libssh2) unrelated to this app, unfixed on either release per Trivy. Alpine's base scans clean (0 CRITICAL/HIGH) since it doesn't ship that package set.
RUN apk add --no-cache curl
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .

# Self-signed cert for internal TLS (see thor-api/Dockerfile for the same pattern, PFX there vs
# PEM here since uvicorn's --ssl-certfile/--ssl-keyfile take file paths, not PKCS12). Baked in
# unconditionally — a no-op unless TLS_CERT_PATH is set at runtime.
RUN apk add --no-cache --virtual .certgen openssl \
    && mkdir -p /app/certs \
    && openssl req -x509 -newkey rsa:2048 -nodes \
         -keyout /app/certs/server.key \
         -out /app/certs/server.crt \
         -days 825 \
         -subj "/CN=intelligence-engine.internal" \
    && apk del .certgen

EXPOSE 8080
EXPOSE 8443
CMD sh -c 'if [ -n "$TLS_CERT_PATH" ]; then exec uvicorn main:app --host 0.0.0.0 --port 8443 --ssl-certfile "$TLS_CERT_PATH" --ssl-keyfile "$TLS_CERT_KEY_PATH"; else exec uvicorn main:app --host 0.0.0.0 --port 8080; fi'
