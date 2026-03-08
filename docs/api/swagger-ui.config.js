const SwaggerUIConfig = {
  urls: [
    {
      url: "/docs/api/auth/openapi.json",
      name: "Authentication Service"
    },
    {
      url: "/docs/api/api-gateway/openapi.json",
      name: "API Gateway"
    },
    {
      url: "/docs/api/data-processor/openapi.json",
      name: "Data Processor"
    },
    {
      url: "/docs/api/event-stream/openapi.json",
      name: "Event Stream"
    }
  ],
  layout: "BaseLayout",
  presets: [
    SwaggerUIBundle.presets.apis,
    SwaggerUIStandalonePreset
  ],
  plugins: [
    SwaggerUIBundle.plugins.DownloadUrl
  ],
  defaultModelsExpandDepth: 1,
  defaultModelExpandDepth: 1
}

window.onload = function() {
  window.ui = SwaggerUIBundle(SwaggerUIConfig)
}
