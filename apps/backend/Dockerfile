# syntax=docker/dockerfile:1.7

FROM --platform=linux/amd64 golang:1.26-bookworm AS builder
WORKDIR /src/apps/backend

COPY apps/backend/go.mod apps/backend/go.sum ./
RUN go mod download

COPY apps/backend ./
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags='-s -w' -o /out/babyai-api ./cmd/api

FROM --platform=linux/amd64 node:20-bookworm-slim AS runtime
WORKDIR /app

COPY package.json package-lock.json ./
COPY packages/schema ./packages/schema
RUN npm ci --include=dev

COPY --from=builder /out/babyai-api /usr/local/bin/babyai-api

EXPOSE 8080
CMD ["babyai-api"]
