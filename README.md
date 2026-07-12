# Symphony Docker

A reproducible, long-running Docker deployment of the experimental Elixir implementation of [OpenAI Symphony](https://github.com/openai/symphony) on a persistent Linux VM. The live deployment uses a DigitalOcean Droplet. Pitchfork runs as PID 1 and supervises Symphony. Docker uses `restart: unless-stopped`, so the service returns after a process, Docker daemon, or VM restart.

This deployment is separate from `symphony-k8s`. It runs one Docker container on one VM and does not require Kubernetes.

## Included software

- OpenAI Symphony pinned to `4cbe3a9699a73b862466c0b157ceca0c1985d6d7`
- Erlang 28.5 and Elixir 1.19.5-otp-28
- Codex CLI 0.144.1
- mise 2026.7.5
- fnox 1.28.0
- Pitchfork 2.15.0

The image contains no API keys, encrypted secret payloads, or private SSH keys. Symphony is preview software and its pinned `mix.lock` reports upstream security advisories, including denial-of-service risks in the dashboard stack. Keep the dashboard private and use this only for trusted repositories and issues.

## Prerequisites

Provision a persistent Linux VM with Docker and SSH access. The operator must have `gh` authentication and a secret source for `LINEAR_API_KEY` and `OPENAI_API_KEY`:

```sh
gh auth status
fnox check
```

Install the three credentials as `/etc/symphony/runtime.env`, owned by root and mode `0600`. Secret values must never appear in the image, build arguments, command arguments, logs, or repository. Use narrowly scoped, revocable credentials dedicated to Symphony.

## Build and deploy on a VM

Clone the repository on the VM and build the pinned image natively:

```sh
git clone https://github.com/jasonmorganson/symphony-docker.git /opt/symphony-docker
docker compose -f /opt/symphony-docker/compose.yaml build
```

Create durable workspace directories before starting the container. UID/GID 1001 is the image's non-root `devbox` user:

```sh
sudo install -d -m 0750 -o 1001 -g 1001 /srv/symphony/workspaces
sudo install -d -m 0750 -o 1001 -g 1001 /srv/symphony/workspaces/arrusted-development
sudo docker compose -f /opt/symphony-docker/compose.yaml up -d
```

The Compose deployment provides:

- a persistent `/srv/symphony/workspaces` checkout and agent workspace root
- automatic container restoration after Docker or VM restart
- bounded local Docker logs
- a health check for the dashboard
- dashboard port 4410 bound only to VM loopback

Back up `/srv/symphony/workspaces` using VM snapshots or a provider volume backup. Symphony issue branches should still be pushed promptly and its Linear workpad remains the durable progress record.

## Operate and verify

Inspect the container without exposing its environment:

```sh
ssh VM docker ps --filter name=symphony
ssh VM docker logs --tail 100 symphony
ssh VM docker exec symphony pitchfork status global/symphony
ssh VM docker exec symphony ps -p 1 -o pid=,comm=,args=
```

Forward the private dashboard locally:

```sh
ssh -N -L 4410:127.0.0.1:4410 VM
```

Open `http://127.0.0.1:4410`. Do not expose this dashboard publicly: Symphony runs Codex without its usual guardrails and the dashboard is not an authentication boundary.

Test restart recovery:

```sh
ssh VM sh -c \
  'kill -9 "$(docker inspect -f {{.State.Pid}} symphony)"'
# Docker restores it automatically.
ssh VM docker ps --filter name=symphony
```

Pitchfork handles `SIGTERM` and `SIGINT`, gracefully shuts down Symphony, and reaps orphaned processes. fnox fails closed if any of `LINEAR_API_KEY`, `OPENAI_API_KEY`, or `GITHUB_TOKEN` is missing.

## Upgrade Symphony

Choose a reviewed upstream commit, update `SYMPHONY_COMMIT` in `Dockerfile`, rebuild the image, and recreate the container on the existing instance. Verify the dashboard and a non-destructive Linear query before removing the previous container image.
