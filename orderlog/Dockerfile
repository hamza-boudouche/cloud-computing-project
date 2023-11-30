FROM golang:1.21.3-alpine@sha256:926f7f7e1ab8509b4e91d5ec6d5916ebb45155b0c8920291ba9f361d65385806 AS builder
RUN apk add --no-cache ca-certificates git
RUN apk add build-base

WORKDIR /src
# restore dependencies
COPY go.mod go.sum ./
RUN go mod download
COPY . .

# Skaffold passes in debug-oriented compiler flags
ARG SKAFFOLD_GO_GCFLAGS
RUN go build -gcflags="${SKAFFOLD_GO_GCFLAGS}" -o /orderlog ./log_server

FROM alpine:3.18.4@sha256:eece025e432126ce23f223450a0326fbebde39cdf496a85d8c016293fc851978
RUN apk add --no-cache ca-certificates

WORKDIR /src
COPY --from=builder /orderlog ./server

# Definition of this variable is used by 'skaffold debug' to identify a golang binary.
# Default behavior - a failure prints a stack trace for the current goroutine.
# See https://golang.org/pkg/runtime/
ENV GOTRACEBACK=single

EXPOSE 50051
ENTRYPOINT ["/src/server"]
