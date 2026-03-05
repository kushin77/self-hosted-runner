// Minimal inbound webhook adapter skeleton

export interface WebhookAdapterOptions {
  path?: string;
  verifySecret?: string; // optional verification secret name or value
}

export default function WebhookAdapter(opts: WebhookAdapterOptions = {}) {
  const path = opts.path || '/hooks';

  return {
    name: 'webhook',
    mountPath: path,
    async init(app) {
      // Example Express route
      // app.post(path, express.json(), (req, res) => { /* verify, enqueue */ });
    },
    async handleRequest(req, res) {
      // validate and forward to portal processing
      res.status(200).send('ok');
    },
    async shutdown() {}
  };
}
