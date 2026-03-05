// Minimal socket event type stubs for the portal app.
// Extend these as the backend event contracts become formalized.

export type MetricsPayload = any;
export type JobEvent = any;
export type AlertPayload = any;

export type ServerToClientEvents = {
  'metrics:update': (payload: MetricsPayload) => void;
  'job:event': (event: JobEvent) => void;
  'alert:new': (alert: AlertPayload) => void;
};

export type ClientToServerEvents = {
  'job:subscribe'?: (id: string) => void;
  'job:unsubscribe'?: (id: string) => void;
};
