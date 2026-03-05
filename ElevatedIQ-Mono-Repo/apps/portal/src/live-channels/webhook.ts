// Minimal inbound webhook adapter skeleton

export interface WebhookAdapterOptions {
  path?: string;
  verifySecret?: string; // optional verification secret name or value
}

import type { Express } from 'express';

export default function WebhookAdapter(opts: WebhookAdapterOptions = {}) {
  const path = opts.path || '/hooks';

  return {
    name: 'webhook',
    mountPath: path,
    async init(app: Express) {
      void app;
      // Example Express route
      // app.post(path, express.json(), (req, res) => { /* verify, enqueue */ });
    },
    async handleRequest(req: any, res: any) {
      void req;
      // validate and forward to portal processing
      res.status(200).send('ok');
    },
    async shutdown() {
      // cleanup
    },
  };
}
