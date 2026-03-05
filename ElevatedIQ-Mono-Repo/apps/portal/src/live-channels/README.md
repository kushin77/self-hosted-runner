Live Channels — Portal

This directory contains skeletons and examples for supported "live" channel integrations used by the Portal (real-time connections).

Purpose
- Provide minimal examples and configuration for each channel type so implementers can wire them into the portal easily.

Files
- `index.ts` — exports available channel adapters.
- `websocket.ts` — baseline WebSocket adapter.
- `webhook.ts` — inbound webhook adapter skeleton.
- `slack.ts` — Slack app adapter skeleton (events/commands).
- `teams.ts` — Microsoft Teams adapter skeleton.
- `channels.config.example.json` — example config for channel registration.

How to use
1. Implement adapter methods in the relevant file.
2. Register adapters in portal startup using `live-channels/index.ts`.
3. Add runtime config to `channels.config.json` (do not commit secrets).