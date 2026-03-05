"use strict";

// OpenTelemetry setup for provisioner-worker.
// Initialization is optional and safe to run even if OTEL packages are not installed.

let tracer = null;
let meter = null;

function init() {
  if (process.env.ENABLE_OTEL !== 'true') {
    return;
  }

  try {
    const { NodeTracerProvider } = require('@opentelemetry/sdk-trace-node');
    const { SimpleSpanProcessor } = require('@opentelemetry/sdk-trace-base');
    const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');
    const { MeterProvider } = require('@opentelemetry/sdk-metrics');

    const tracerProvider = new NodeTracerProvider();
    const traceExporter = new OTLPTraceExporter({
      url: process.env.OTEL_EXPORTER_OTLP_ENDPOINT || 'http://localhost:4318/v1/traces'
    });
    tracerProvider.addSpanProcessor(new SimpleSpanProcessor(traceExporter));
    tracerProvider.register();
    tracer = tracerProvider.getTracer('provisioner-worker');

    const meterProvider = new MeterProvider();
    meter = meterProvider.getMeter('provisioner-worker');

    console.info('OpenTelemetry initialized');
  } catch (e) {
    console.warn('OpenTelemetry initialization failed (continuing without OTEL):', e.message);
  }
}

function getTracer() {
  return tracer;
}

function getMeter() {
  return meter;
}

module.exports = { init, getTracer, getMeter };
