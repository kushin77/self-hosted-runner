"use strict";

// OTEL initializer for vault-shim service (optional dependency pattern)

let tracer = null;
let meter = null;

function init() {
  if (process.env.ENABLE_OTEL !== 'true') return;
  try {
    const { NodeTracerProvider } = require('@opentelemetry/sdk-trace-node');
    const { SimpleSpanProcessor } = require('@opentelemetry/sdk-trace-base');
    const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');
    const { MeterProvider } = require('@opentelemetry/sdk-metrics');

    const tp = new NodeTracerProvider();
    const exp = new OTLPTraceExporter({ url: process.env.OTEL_EXPORTER_OTLP_ENDPOINT });
    tp.addSpanProcessor(new SimpleSpanProcessor(exp));
    tp.register();
    tracer = tp.getTracer('vault-shim');

    const mp = new MeterProvider();
    meter = mp.getMeter('vault-shim');
    console.info('vault-shim: OpenTelemetry initialized');
  } catch (e) {
    console.warn('vault-shim: OTEL init failed, continuing without telemetry', e.message);
  }
}

function getTracer() { return tracer; }
function getMeter() { return meter; }

module.exports = { init, getTracer, getMeter };
