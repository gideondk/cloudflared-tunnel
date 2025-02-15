# Build container
ARG GOVERSION=1.22.10
ARG ALPINEVERSION=3.21

FROM --platform=${BUILDPLATFORM} \
    golang:$GOVERSION-alpine${ALPINEVERSION} AS build

WORKDIR /src

RUN apk --no-cache add git build-base bash
# Use non-root user for building
RUN adduser -D build
USER build

ENV GO111MODULE=on \
    CGO_ENABLED=0

ARG VERSION=2025.2.0
RUN git clone https://github.com/cloudflare/cloudflared --depth=1 --branch ${VERSION} .
RUN bash -x .teamcity/install-cloudflare-go.sh

# From this point on, step(s) are duplicated per-architecture
ARG TARGETOS
ARG TARGETARCH
ARG TARGETVARIANT
# Fixes execution on linux/arm/v6 for devices that don't support armv7 binaries
RUN if [ "${TARGETVARIANT}" = "v6" ] && [ "${TARGETARCH}" = "arm" ]; then export GOARM=6; fi; \
    GOOS=${TARGETOS} GOARCH=${TARGETARCH} CONTAINER_BUILD=1 make LINK_FLAGS="-w -s" cloudflared 

# Use distroless as minimal base image
FROM gcr.io/distroless/static-debian12:nonroot
WORKDIR /

COPY --from=builder /src/cloudflared /cloudflared
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# Environment variable for the token
ENV TUNNEL_TOKEN=""

USER nonroot
# Start cloudflared using the token from environment variable
ENTRYPOINT ["/bin/sh", "-c","/cloudflared tunnel --no-autoupdate run --loglevel debug --token $TUNNEL_TOKEN"]
