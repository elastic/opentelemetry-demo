# Copyright The OpenTelemetry Authors
# SPDX-License-Identifier: Apache-2.0


FROM docker.io/library/node:22-slim AS builder

WORKDIR /usr/src/app/

COPY ./src/payment/package.json package.json
COPY ./src/payment/package-lock.json package-lock.json

RUN npm ci --omit=dev

# -----------------------------------------------------------------------------

FROM gcr.io/distroless/nodejs22-debian12:nonroot

WORKDIR /usr/src/app/

COPY --from=builder /usr/src/app/node_modules/ node_modules/

COPY ./pb/demo.proto demo.proto

COPY ./src/payment/charge.js charge.js
COPY ./src/payment/index.js index.js
COPY ./src/payment/logger.js logger.js

EXPOSE ${PAYMENT_PORT}

## The two steps below reproduce what "npm run start" would do, but using
## distroless we cannot use "npm" directly.
ENV OTEL_EXPORTER_OTLP_PROTOCOL=grpc

CMD [ "--import", "@elastic/opentelemetry-node", "index.js" ]
