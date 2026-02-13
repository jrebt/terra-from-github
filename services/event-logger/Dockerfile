FROM golang:1.22-alpine AS builder

WORKDIR /app

COPY go.mod ./
COPY *.go ./
RUN go mod tidy
RUN CGO_ENABLED=0 GOOS=linux go build -o event-logger .

FROM alpine:3.19

RUN apk --no-cache add ca-certificates

WORKDIR /app
COPY --from=builder /app/event-logger .

EXPOSE 8080

ENTRYPOINT ["./event-logger"]
