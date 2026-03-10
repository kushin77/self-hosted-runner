"use strict";

// Optional OTEL initialization for managed-auth service.
// Follows same pattern as provisioner-worker; safe when packages missing.

let tracer = null;
let meter = null;

function init() {
  if (process.env.ENABLE_OTEL !== 'true') return;
  try {
    const { NodeTracerProvider } = require('@opentelemetry/sdk-trace-node');
    const { SimpleSpanProcessor } = require('@opentelemetry/sdk-trace-base');
    const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');
    const { MeterProvider } = require('@opentelemetry/sdk-metrics');

    const exporterType = (process.env.OTEL_EXPORTER || 'otlp').toLowerCase();
    let exporterUrl = process.env.OTEL_EXPORTER_OTLP_ENDPOINT || 'http://localhost:4318/v1/traces';
    let exporterOptions = { url: exporterUrl };
    if (exporterType === 'datadog') {
      exporterOptions.headers = { 'DD-API-KEY': process.env.DATADOG_API_KEY || '' };
    } else if (exporterType === 'splunk') {
      exporterOptions.headers = { 'Splunk': process.env.SPLUNK_HEC_TOKEN || '' };
    }

    const provider = new NodeTracerProvider();
    const exporter = new OTLPTraceExporter(exporterOptions);
    provider.addSpanProcessor(new SimpleSpanProcessor(exporter));
    provider.register();
    tracer = provider.getTracer('managed-auth');

    const meterProvider = new MeterProvider();
    meter = meterProvider.getMeter('managed-auth');
    console.info('managed-auth: OpenTelemetry initialized (exporter=' + exporterType + ')');
  } catch (e) {
    console.warn('managed-auth: OTEL init failed, continuing without telemetry', e.message);
  }
}

function getTracer() { return tracer; }
function getMeter() { return meter; }

module.exports = { init, getTracer, getMeter };
