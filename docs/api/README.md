# 10X Enterprise - API Documentation

Auto-generated OpenAPI documentation for all microservices.

## Services

### Authentication Service
- **Type:** Node.js/TypeScript
- **Language:** TypeScript
- **OpenAPI:** [auth/openapi.json](./auth/openapi.json)
- **Swagger UI:** [View Docs](./auth/)

### API Gateway
- **Type:** Node.js/TypeScript
- **Language:** TypeScript
- **OpenAPI:** [api-gateway/openapi.json](./api-gateway/openapi.json)
- **Swagger UI:** [View Docs](./api-gateway/)

### Data Processor
- **Type:** Node.js/TypeScript
- **Language:** TypeScript
- **OpenAPI:** [data-processor/openapi.json](./data-processor/openapi.json)
- **Swagger UI:** [View Docs](./data-processor/)

### Event Stream
- **Type:** Node.js/TypeScript
- **Language:** TypeScript
- **OpenAPI:** [event-stream/openapi.json](./event-stream/openapi.json)
- **Swagger UI:** [View Docs](./event-stream/)

### Go Services
- **Type:** Go Microservices
- **Language:** Go
- **OpenAPI:** [go/openapi.json](./go/openapi.json)

## Generation

This documentation is auto-generated from source code on each build.

**Last Updated:** $(date -u +'%Y-%m-%d %H:%M:%S UTC')

## Viewing Documentation

1. **Online:** [API Docs](https://docs.example.com/api/)
2. **Local:** Run `make docs-serve` and visit http://localhost:8080/api
3. **Swagger UI:** [Interactive Explorer](./swagger-ui.html)

## Contributing

When adding new APIs:
1. Use OpenAPI 3.0 spec comments in your code
2. Run `make docs-generate` to regenerate
3. Commit updated OpenAPI specs to version control

See [CONTRIBUTING.md](../../ElevatedIQ-Mono-Repo/apps/portal/node_modules/recharts/CONTRIBUTING.md) for details.
