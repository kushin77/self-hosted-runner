// Slack adapter skeleton: events & commands handling

export interface SlackAdapterOptions {
  signingSecretName?: string; // name of secret in store
  path?: string;
}

export default function SlackAdapter(opts: SlackAdapterOptions = {}) {
  const path = opts.path || '/slack/events';

  return {
    name: 'slack',
    mountPath: path,
    async init(app) {
      // app.post(path, express.json(), verifySlackSignatureMiddleware, (req,res)=>{})
    },
    async handleEvent(payload) {
      // handle event callbacks
    },
    async handleCommand(command) {
      // handle slash commands
    },
    async shutdown() {}
  };
}
