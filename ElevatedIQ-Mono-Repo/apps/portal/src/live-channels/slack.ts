// Slack adapter skeleton: events & commands handling

export interface SlackAdapterOptions {
  signingSecretName?: string; // name of secret in store
  path?: string;
}

import type { Express } from 'express';

export default function SlackAdapter(opts: SlackAdapterOptions = {}) {
  const path = opts.path || '/slack/events';

  return {
    name: 'slack',
    mountPath: path,
    async init(app: Express) {
      void app;
      // app.post(path, express.json(), verifySlackSignatureMiddleware, (req,res)=>{})
    },
    async handleEvent(payload: any) {
      void payload;
      // handle event callbacks
    },
    async handleCommand(command: any) {
      void command;
      // handle slash commands
    },
    async shutdown() {
      // cleanup resources
    },
  };
}
