// Microsoft Teams adapter skeleton

export interface TeamsAdapterOptions {
  appIdName?: string; // secret name for app id / credentials
  path?: string;
}

export default function TeamsAdapter(opts: TeamsAdapterOptions = {}) {
  const path = opts.path || '/teams/events';

  return {
    name: 'teams',
    mountPath: path,
    async init(app) {
      // route for Teams messages
    },
    async handleActivity(activity) {
      // map to portal events
    },
    async shutdown() {}
  };
}
