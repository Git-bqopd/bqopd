# ==========================================
# STAGE 1: Build the Jaspr Application
# ==========================================
FROM dart:stable AS build

# Activate the Jaspr CLI globally to enable compilation
RUN dart pub global activate jaspr_cli

WORKDIR /app

# Copy the entire monorepo workspace to resolve package dependencies
COPY . .

# Clean override configurations and fetch dependencies for all workspace modules
RUN rm -f pubspec_overrides.yaml
RUN dart pub get

# Navigate into the Web Application subfolder and compile the server & client-side assets
WORKDIR /app/apps/bqopd_web
RUN dart pub global run jaspr_cli:jaspr build --verbose

# ==========================================
# STAGE 2: Lightweight Production Runtime
# ==========================================
FROM debian:bookworm-slim

# Install system certificates so that our Dart code can securely request Firebase/Google APIs via HTTPS
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy the compiled native server executable
COPY --from=build /app/apps/bqopd_web/build/jaspr/app /app/server

# Copy the static web assets directory containing the JS entrypoint and stylesheets
COPY --from=build /app/apps/bqopd_web/build/jaspr/web /app/web

# Cloud Run defaults to port 8080 and handles proxy routing
EXPOSE 8080

# Configure execution bindings
ENV HOST=0.0.0.0
ENV PORT=8080

# Execute our server-side pre-rendering engine
CMD ["/app/server"]