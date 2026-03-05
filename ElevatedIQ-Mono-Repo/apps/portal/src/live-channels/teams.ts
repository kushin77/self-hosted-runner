// Microsoft Teams adapter skeleton

export interface TeamsAdapterOptions {
  appIdName?: string; // secret name for app id / credentials
  path?: string;
}

import type { Express } from 'express';

export default function TeamsAdapter(opts: TeamsAdapterOptions = {}) {
  const path = opts.path || '/teams/events';

  return {
    name: 'teams',
    mountPath: path,
    async init(app: Express) {
      void app;
      // route for Teams messages
    },
    async handleActivity(activity: any) {
      void activity;
      // map to portal events
    },
    async shutdown() {
      // cleanup
    },
  };
}
