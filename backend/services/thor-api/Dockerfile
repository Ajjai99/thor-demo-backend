FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY *.csproj .
RUN dotnet restore
COPY . .
RUN dotnet publish -c Release -o /app --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
# curl was deliberately removed from this base image starting with .NET 5.0 (security hardening) — installed back explicitly since the ECS container healthCheck in modules/ecs/services.tf depends on it being on PATH.
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*
WORKDIR /app

# Self-signed cert for the NLB -> ECS TLS re-encryption leg (dev only — see modules/ecs/nlb.tf's
# nlb_tls_enabled). The NLB never validates a target's certificate, so this stays valid
# indefinitely; baked in unconditionally since it's a no-op unless TLS_CERT_PFX_PATH is actually
# read by Program.cs (only happens when the env var is set).
RUN apt-get update && apt-get install -y --no-install-recommends openssl \
    && mkdir -p /app/certs \
    && openssl req -x509 -newkey rsa:2048 -nodes \
         -keyout /app/certs/server.key \
         -out /app/certs/server.crt \
         -days 825 \
         -subj "/CN=thor-api.internal" \
    && openssl pkcs12 -export \
         -out /app/certs/server.pfx \
         -inkey /app/certs/server.key \
         -in /app/certs/server.crt \
         -passout pass:thor-internal \
    && rm /app/certs/server.key /app/certs/server.crt \
    && apt-get purge -y --auto-remove openssl \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /app .
EXPOSE 8080
EXPOSE 8443
ENTRYPOINT ["dotnet", "Thor.Api.dll"]