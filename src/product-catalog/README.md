# Product Catalog Service

## Overview

The Product Catalog Service is the central product data backend for the OpenTelemetry demo e-commerce application. It exposes a gRPC API that other services use to list, retrieve, and search products. The service is instrumented with OpenTelemetry to emit distributed traces, metrics, and logs, and it includes a feature flag–driven failure mode used for chaos engineering and observability testing.

## Architecture

| Property | Value |
|---|---|
| Language | Go |
| Protocol | gRPC |
| Port | `3550` (set via `PRODUCT_CATALOG_PORT`) |
| Data source | JSON files in the `./products/` directory |
| Feature flags | [OpenFeature](https://openfeature.dev/) backed by [flagd](https://flagd.dev/) |

On startup, and periodically thereafter (controlled by `PRODUCT_CATALOG_RELOAD_INTERVAL`), the service reads all `.json` files from the `./products/` directory and unmarshals them into `Product` protobuf objects using `protojson`.

## gRPC API

The service implements the `ProductCatalogService` defined in `pb/demo.proto`.

| RPC | Request | Response | Description |
|---|---|---|---|
| `ListProducts` | `Empty` | `ListProductsResponse` | Returns the full product catalog. |
| `GetProduct` | `GetProductRequest` (id) | `Product` | Looks up a single product by ID. Returns `NOT_FOUND` if the product doesn't exist. |
| `SearchProducts` | `SearchProductsRequest` (query) | `SearchProductsResponse` | Case-insensitive text search across product `Name` and `Description` fields. |

### OTel span attributes set per RPC

| RPC | Span attribute | Type | Description |
|---|---|---|---|
| `ListProducts` | `app.products.count` | int | Number of products returned |
| `GetProduct` | `app.product.id` | string | ID of the requested product |
| `GetProduct` | `app.product.name` | string | Name of the found product |
| `SearchProducts` | `app.products_search.count` | int | Number of results matching the query |

## Configuration

| Environment variable | Required | Default | Description |
|---|---|---|---|
| `PRODUCT_CATALOG_PORT` | Yes | `3550` | Port the gRPC server listens on |
| `PRODUCT_CATALOG_RELOAD_INTERVAL` | No | `10` | Interval in seconds between product catalog reloads |
| `FLAGD_HOST` | No | `flagd` | Hostname of the flagd feature flag service |
| `FLAGD_PORT` | No | `8013` | Port of the flagd feature flag service |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | No | — | OTLP endpoint for traces, metrics, and logs |
| `OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE` | No | — | Metrics temporality preference (e.g. `cumulative`) |
| `OTEL_RESOURCE_ATTRIBUTES` | No | — | Additional OTel resource attributes (key=value pairs) |
| `OTEL_SERVICE_NAME` | No | `product-catalog` | OTel service name reported in telemetry |

## Observability

The service is fully instrumented with OpenTelemetry:

- **Traces** — exported via OTLP gRPC (`otlptracegrpc`). The gRPC server is instrumented with `otelgrpc.NewServerHandler()` so every inbound RPC automatically creates a span. Additional span attributes and events are set manually (see the table above).
- **Metrics** — exported via OTLP gRPC (`otlpmetricgrpc`) using a periodic reader. Go runtime metrics (memory, GC, goroutines) are collected via `go.opentelemetry.io/contrib/instrumentation/runtime`.
- **Logs** — exported via OTLP gRPC (`otlploggrpc`) using the `otelslog` bridge so structured log records are correlated with the active trace context.
- **Propagation** — W3C `TraceContext` and `Baggage` propagation formats are configured, enabling end-to-end distributed traces across services.

Span status is set to `Error` and a span event is added whenever `GetProduct` returns `NOT_FOUND` or triggers the feature-flag failure path.

## Feature Flags

| Flag name | Default | Description |
|---|---|---|
| `productCatalogFailure` | `false` | When enabled, `GetProduct` returns a gRPC `Internal` error for the product with ID `OLJCESPC7Z`. |

This flag is evaluated via [OpenFeature](https://openfeature.dev/) backed by flagd. It is used for **chaos engineering and resilience testing** — enabling it causes a realistic failure in the product lookup flow so you can observe how dependent services (e.g. frontend, checkout) handle downstream errors and inspect the resulting traces and alerts.

To enable the flag, update the flagd configuration (see `src/flagd/demo.flagd.json`) and set `productCatalogFailure` to `true`.

## Health Check

The service implements the standard [gRPC health checking protocol](https://grpc.io/docs/guides/health-checking/):

| Method | Behaviour |
|---|---|
| `Check` | Always returns `SERVING` |
| `Watch` | Returns `Unimplemented` |

## Local Development

### Build the service binary

```sh
go build -o /go/bin/product-catalog/
```

### Docker build

From the root directory, run:

```sh
docker compose build product-catalog
```

### Regenerate protos

To regenerate the protobuf bindings, run from the root directory:

```sh
make docker-generate-protobuf
```

### Bump dependencies

To upgrade all Go dependencies:

```sh
go get -u -t ./...
go mod tidy
```

## Dependencies

| Dependency | Purpose |
|---|---|
| `google.golang.org/grpc` | gRPC server and client |
| `google.golang.org/protobuf` | Protobuf serialization / `protojson` unmarshalling |
| `go.opentelemetry.io/contrib/instrumentation/google.golang.org/grpc/otelgrpc` | Automatic gRPC server/client instrumentation |
| `go.opentelemetry.io/contrib/instrumentation/runtime` | Go runtime metrics |
| `go.opentelemetry.io/contrib/bridges/otelslog` | Bridge between `log/slog` and OTel logs |
| `github.com/open-feature/go-sdk` | OpenFeature Go SDK for feature flag evaluation |
| `github.com/open-feature/go-sdk-contrib/providers/flagd` | flagd provider for OpenFeature |
| `github.com/open-feature/go-sdk-contrib/hooks/open-telemetry` | OTel tracing hooks for OpenFeature evaluations |
