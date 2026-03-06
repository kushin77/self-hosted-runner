Title: Containerize services and publish immutable images
Status: in-progress
Assignee: TBD

Description:
- Created `Dockerfile` for `provisioner-worker`, `managed-auth`, and `vault-shim`.
- Continue containerizing remaining services and add CI to build/push images.
- Add CI job to build, scan, sign and push images to private registry.
- Replace local `nohup node` start with container-based systemd unit or compose file.

Acceptance criteria:
- Images built by CI and available in registry.
- Deploy script updated to pull and run images rather than copying raw code.
