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

    const exporterType = (process.env.OTEL_EXPORTER || 'otlp').toLowerCase();
    let exporterUrl = process.env.OTEL_EXPORTER_OTLP_ENDPOINT || 'http://localhost:4318/v1/traces';
    let exporterOptions = { url: exporterUrl };
    if (exporterType === 'datadog') {
      exporterOptions.headers = { 'DD-API-KEY': process.env.DATADOG_API_KEY || '' };
    } else if (exporterType === 'splunk') {
      exporterOptions.headers = { 'Splunk': process.env.SPLUNK_HEC_TOKEN || '' };
    }

    const tp = new NodeTracerProvider();
    const exp = new OTLPTraceExporter(exporterOptions);
    tp.addSpanProcessor(new SimpleSpanProcessor(exp));
    tp.register();
    tracer = tp.getTracer('vault-shim');

    const mp = new MeterProvider();
    meter = mp.getMeter('vault-shim');
    console.info('vault-shim: OpenTelemetry initialized (exporter=' + exporterType + ')');
  } catch (e) {
    console.warn('vault-shim: OTEL init failed, continuing without telemetry', e.message);
  }
}

function getTracer() { return tracer; }
function getMeter() { return meter; }

module.exports = { init, getTracer, getMeter };
