/**
 * Live Channels Loader
 * 
 * Registers and initializes enabled channel adapters from config.
 * Call this during portal app startup to wire up real-time connections.
 */

import type { Express } from 'express';

import WebSocketAdapter from './websocket';
import WebhookAdapter from './webhook';
import SlackAdapter from './slack';
import TeamsAdapter from './teams';

export interface ChannelConfig {
  name: string;
  enabled: boolean;
  options?: Record<string, any>;
}

export interface AdapterInstance {
  name: string;
  mountPath: string;
  init: (server: any) => Promise<void>;
  shutdown: () => Promise<void>;
}

const adapterFactories: Record<string, (opts: any) => AdapterInstance> = {
  websocket: WebSocketAdapter,
  webhook: WebhookAdapter,
  slack: SlackAdapter,
  teams: TeamsAdapter,
};

export async function loadChannels(
  app: Express,
  config: ChannelConfig[]
): Promise<AdapterInstance[]> {
  const activeAdapters: AdapterInstance[] = [];

  for (const channelConfig of config) {
    if (!channelConfig.enabled) {
      console.log(`[live-channels] Skipping disabled channel: ${channelConfig.name}`);
      continue;
    }

    const factory = adapterFactories[channelConfig.name];
    if (!factory) {
      console.warn(`[live-channels] Unknown channel type: ${channelConfig.name}`);
      continue;
    }

    try {
      const adapter = factory(channelConfig.options);
      await adapter.init(app);
      activeAdapters.push(adapter);
      console.log(`[live-channels] Initialized: ${adapter.name} at ${adapter.mountPath}`);
    } catch (err) {
      console.error(`[live-channels] Failed to initialize ${channelConfig.name}:`, err);
    }
  }

  return activeAdapters;
}

export async function shutdownChannels(adapters: AdapterInstance[]): Promise<void> {
  for (const adapter of adapters) {
    try {
      await adapter.shutdown();
      console.log(`[live-channels] Shutdown: ${adapter.name}`);
    } catch (err) {
      console.error(`[live-channels] Error shutting down ${adapter.name}:`, err);
    }
  }
}
