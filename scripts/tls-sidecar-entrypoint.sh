#!/bin/sh
set -eu

mkdir -p /etc/nginx/tls
# Leaf cert followed by the intermediate chain, in one file — API Gateway needs the intermediate to build the
# path from this cert up to Let's Encrypt's public root; ssl_certificate expects them concatenated in this order.
printf '%s\n%s' "$TLS_CERT_PEM" "$TLS_CHAIN_PEM" > /etc/nginx/tls/cert.pem
printf '%s' "$TLS_KEY_PEM" > /etc/nginx/tls/key.pem

cat > /etc/nginx/conf.d/default.conf <<EOF
server {
    listen ${LISTEN_PORT} ssl;
    ssl_certificate     /etc/nginx/tls/cert.pem;
    ssl_certificate_key /etc/nginx/tls/key.pem;

    location / {
        proxy_pass http://127.0.0.1:${APP_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
}
EOF

exec nginx -g 'daemon off;'
