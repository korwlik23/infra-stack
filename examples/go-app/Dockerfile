# syntax=docker/dockerfile:1
FROM golang:1.26-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/server .

# alpine (ไม่ใช่ scratch/distroless) — healthcheck + drain ของ infra-stack ต้องมี sh + wget
FROM alpine:3.22
RUN adduser -D -u 10001 app
WORKDIR /app
COPY --from=build /out/server /app/server
# seed ฝังใน binary แล้ว — copy ไว้ให้ deploy.sh จับว่าไฟล์ seed เปลี่ยน (DEPLOY_SEED_PATHS=seeds)
COPY seeds ./seeds
USER app
EXPOSE 8080
CMD ["/app/server"]
