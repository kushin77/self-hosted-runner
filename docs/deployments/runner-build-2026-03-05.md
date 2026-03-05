# Runner image build — 2026-03-05

Summary of the runner image build executed on the fullstack host (192.168.168.42).

- **Image:** `self-hosted-runner:prod-p2`
- **Digest/SHA:** `sha256:2bd04c83f142044d7d4ccbe29eceb80b4be76651b94222d257199f0a3b3436d3`
- **Approx size:** ~1.6 GB
- **Built on host:** `192.168.168.42` (user: `akushnir`)
- **Build context path on host:** `/home/akushnir/ElevatedIQ-Mono-Mono-Repo/ElevatedIQ-Mono-Repo`
- **Build command used:**
  - `docker build --network=host -t docker.io/self-hosted-runner:prod-p2 -f build/github-runner/Dockerfile --build-arg NODE_ENV=production --label git.commit=$(git rev-parse --short HEAD) --label build.date=$(date -u +"%Y-%m-%dT%H:%M:%SZ") .`
- **Full build log (captured by agent):** stored in workspace chat resources (contact agent to retrieve full log file)

Next steps (requires input):

- **Push image to registry:** not started — requires registry credentials or a push policy. Recommend pushing to the org registry and recording digest in deployment manifests.
- **Run stage2 (Vault AppRole):** not started — requires Vault credentials and access.

If you want me to push the image now, provide registry target and credentials (or confirm using Docker Hub and that `docker login` is configured on `192.168.168.42`).
