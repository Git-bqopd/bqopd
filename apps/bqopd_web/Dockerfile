# ==========================================
# STAGE 1: Build the Jaspr Application
# ==========================================
FROM dart:stable AS build

# Activate the Jaspr CLI globally to enable compilation
RUN dart pub global activate jaspr_cli

WORKDIR /app

# Copy the entire monorepo workspace to resolve package dependencies
COPY . .

# Clean override configurations and purge lingering build caches
RUN rm -f pubspec_overrides.yaml
RUN rm -rf .dart_tool apps/bqopd_web/.dart_tool packages/bqopd_core/.dart_tool apps/bqopd_web/build

# Resolve dependencies for the shared core package
WORKDIR /app/packages/bqopd_core
RUN dart pub get

# Navigate into the Web App, resolve packages, and upgrade build daemon dependencies
WORKDIR /app/apps/bqopd_web
RUN dart pub get && dart pub upgrade build_daemon build_runner
RUN dart pub global run jaspr_cli:jaspr build --verbose

# ==========================================
# STAGE 2: Lightweight Production Runtime
# ==========================================
FROM debian:bookworm-slim

# Install system certificates for secure HTTPS requests
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy the compiled native server executable
COPY --from=build /app/apps/bqopd_web/build/jaspr/app /app/server

# Copy static web assets
COPY --from=build /app/apps/bqopd_web/build/jaspr/web /app/web

# Cloud Run defaults to port 8080 and handles proxy routing
EXPOSE 8080

# Configure execution bindings
ENV HOST=0.0.0.0
ENV PORT=8080

# Execute server-side pre-rendering engine
CMD ["/app/server"]