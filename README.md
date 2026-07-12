# Symphony Docker

A reproducible, long-running Docker deployment of the experimental Elixir implementation of [OpenAI Symphony](https://github.com/openai/symphony) on a bare [Namespace compute instance](https://namespace.so/docs/architecture/compute). Pitchfork runs as PID 1 and supervises Symphony. Docker uses `--restart unless-stopped`, so the service returns after a process, Docker daemon, or compute-instance restart.

This deployment is separate from `symphony-k8s`. It runs one Docker container on one bare compute instance and does not require Kubernetes.

## Included software

- OpenAI Symphony pinned to `4cbe3a9699a73b862466c0b157ceca0c1985d6d7`
- Erlang 28.5 and Elixir 1.19.5-otp-28
- Codex CLI 0.144.1
- mise 2026.7.5
- fnox 1.28.0
- Pitchfork 2.15.0

The image contains no API keys, encrypted secret payloads, or private SSH keys. Symphony is preview software and its pinned `mix.lock` reports upstream security advisories, including denial-of-service risks in the dashboard stack. Keep the dashboard private and use this only for trusted repositories and issues.

## Prerequisites

Authenticate `nsc` and `gh`. The local fnox configuration must resolve `LINEAR_API_KEY` and `OPENAI_API_KEY` without printing them:

```sh
nsc auth status
gh auth status
fnox check
```

The GitHub token is transferred through a mode-0600 temporary file and installed as `/etc/symphony.env` on the instance. Secret values never appear in the image, build arguments, command arguments, or repository. Use narrowly scoped, revocable credentials dedicated to Symphony.

## Build and deploy

Build the pinned amd64 image in Namespace and push it to the workspace registry:

```sh
bin/build-image symphony-docker:latest
```

Set `SYMPHONY_IMAGE` to the resulting `nscr.io/...` image reference, then create the bare compute instance and persistent volume:

```sh
export SYMPHONY_IMAGE=nscr.io/WORKSPACE/symphony-docker:latest
export SYMPHONY_FNOX_CONFIG=/path/to/fnox.local.toml
bin/deploy-instance
```

The defaults are:

- machine: `linux/amd64:4x8`
- lease: three hours (the current tenant maximum)
- instance-local `/workspaces` storage
- unique instance tag: `arrusted-symphony`
- dashboard port: 4410

Override the compute defaults with `SYMPHONY_MACHINE_TYPE` or `SYMPHONY_INSTANCE_DURATION`. If persistent volumes are enabled for the Namespace tenant, set `SYMPHONY_PERSISTENT_VOLUME=true`; the volume defaults to the `arrusted-symphony` tag and 150 GB, configurable with `SYMPHONY_VOLUME_SIZE`. This tenant currently rejects persistent-volume attachments, so the live deployment uses instance-local storage. Symphony can recreate issue workspaces from GitHub after reprovisioning, but unpushed local work is lost if the lease expires.

Namespace compute is leased rather than indefinite. Renew it hourly from an external scheduler:

```sh
bin/maintain-instance INSTANCE_ID 2h
```

`maintain-instance` renews the lease and fails unless the container, restart policy, Pitchfork daemon, and dashboard are healthy. This tenant caps the deadline at three hours even when a longer duration is requested, so schedule it hourly outside the Namespace instance and alert on any nonzero exit. `renew-instance` is also available when renewal without health checks is explicitly desired. The external job can alert and reprovision if the instance disappears. With persistent volumes enabled, a replacement instance can reattach the same checkout and `.symphony/workspaces`; otherwise it starts from a fresh clone. Symphony issue branches must be pushed promptly and its Linear workpad remains the durable progress record.

The checked-in `Maintain Symphony compute` GitHub Actions workflow performs this control loop at minute 17 of every hour and supports manual dispatch. The official Namespace setup action exchanges GitHub's short-lived OIDC identity, so the workflow has no long-lived Namespace secret to rotate. The Namespace GitHub integration must authorize this repository.

## Operate and verify

Inspect the container without exposing its environment:

```sh
nsc ssh INSTANCE_ID --disable-pty -- docker ps --filter name=symphony
nsc ssh INSTANCE_ID --disable-pty -- docker logs --tail 100 symphony
nsc ssh INSTANCE_ID --disable-pty -- docker exec symphony pitchfork status
nsc ssh INSTANCE_ID --disable-pty -- docker exec symphony ps -p 1 -o pid=,comm=,args=
```

Forward the private dashboard locally:

```sh
nsc instance port-forward INSTANCE_ID --target_port 4410
```

The command prints the random localhost port it selected; open that URL. Do not expose this dashboard publicly: Symphony runs Codex without its usual guardrails and the dashboard is not an authentication boundary.

Test restart recovery:

```sh
nsc ssh INSTANCE_ID --disable-pty -- sh -c \
  'kill -9 "$(docker inspect -f {{.State.Pid}} symphony)"'
# Docker restores it automatically.
nsc ssh INSTANCE_ID --disable-pty -- docker ps --filter name=symphony
```

Pitchfork handles `SIGTERM` and `SIGINT`, gracefully shuts down Symphony, and reaps orphaned processes. fnox fails closed if any of `LINEAR_API_KEY`, `OPENAI_API_KEY`, or `GITHUB_TOKEN` is missing.

## Upgrade Symphony

Choose a reviewed upstream commit, update `SYMPHONY_COMMIT` in `Dockerfile`, rebuild the image, and recreate the container on the existing instance. Verify the dashboard and a non-destructive Linear query before removing the previous container image.
