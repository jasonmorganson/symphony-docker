# Symphony Docker

A reproducible [Namespace Devbox](https://namespace.so/docs/devbox/images) image for the experimental Elixir implementation of [OpenAI Symphony](https://github.com/openai/symphony). In a standard Docker container the image runs [Pitchfork](https://pitchfork.jdx.dev/guides/container-mode.html) as PID 1 and boots Symphony from the checked-out Arrusted workflow. Namespace replaces image entrypoints with its Devbox agent, so Pitchfork runs as a supervised child there.

## Included software

- OpenAI Symphony pinned to `4cbe3a9699a73b862466c0b157ceca0c1985d6d7`
- Erlang 28.5 and Elixir 1.19.5-otp-28
- Codex CLI 0.144.1
- mise 2026.7.5
- fnox 1.28.0
- Pitchfork 2.15.0

The image contains no API keys, encrypted secret payloads, or private SSH keys.

Symphony is preview software. Its pinned `mix.lock` currently reports upstream security advisories, including denial-of-service risks in the dashboard stack. Keep the dashboard behind Namespace's private port forward, use this image only for trusted repositories and issues, and review advisories whenever advancing the Symphony commit.

## Build the image

Install and authenticate the Namespace Devbox CLI, then build from the repository root:

```sh
devbox auth check-login
devbox image build . \
  --name arrusted/symphony \
  --description "OpenAI Symphony for Arrusted" \
  --optimize \
  --port_forward 4410 \
  --user devbox \
  --workspace_dir /workspaces \
  --persistency whole
```

Namespace optimizes the image after a successful build. Rebuilding with the same name updates the image used by new Devboxes; existing Devboxes retain the image version they were created with.

For a local smoke build on the host architecture:

```sh
docker build -t symphony-devbox:local .
```

The Namespace build is the authoritative amd64 proof. Running an amd64 Erlang image through Apple-Silicon emulation can fail in `prim_tty` even when the same image builds natively on Namespace.

## Configure secrets

Create `LINEAR_API_KEY` and `OPENAI_API_KEY` in Namespace Secrets. Enter values through Namespace's hidden-input or web UI flow; do not pass plaintext values as command-line arguments.

Export the resulting Namespace object IDs. The wrapper rejects missing or malformed IDs so the CLI cannot silently omit placeholder secret mappings:

```sh
export LINEAR_SECRET_ID=sec_...
export OPENAI_SECRET_ID=sec_...
```

The values are injected at boot. The bundled fnox configuration declares both names as required and resolves the already-present environment variables, so the daemon keeps the same `fnox exec -- symphony` launch boundary as local development. Use narrowly scoped, revocable credentials dedicated to this trusted Devbox: Symphony deliberately runs Codex without its usual guardrails, and both processes share the injected environment.

## Create and operate the Devbox

Create the persistent medium Devbox and connect to it. Do not pass `devbox.yaml` directly to `devbox create`; it is a template consumed by the validating wrapper. The spec creates a named `symphony` session automatically, clones the repository when the persistent checkout is absent, marks Symphony as ongoing Namespace work to prevent idle shutdown, and then starts Pitchfork.

```sh
bin/create-devbox
devbox ssh arrusted-symphony
```

Before allowing Symphony to dispatch work, confirm the Devbox checkout integration also authenticates the SSH clone used by Arrusted's `hooks.after_create`:

```sh
ssh -o BatchMode=yes -T git@github.com
```

If that check fails, configure the Devbox's GitHub access with Namespace before starting Symphony. Never bake a deploy key into this image.

Inspect Pitchfork and Symphony:

```sh
devbox session connect arrusted-symphony --session symphony
pitchfork status global/symphony
pitchfork logs global/symphony
ps -p 1 -o pid=,comm=,args=
```

Forward the Symphony dashboard to the local machine:

```sh
devbox port-forward arrusted-symphony --ports 4410
```

Then open <http://127.0.0.1:4410/>. Symphony remains loopback-only; the bundled `dashboard-proxy` daemon listens only on the Devbox interface and relays port 4410 so Namespace can forward it without exposing public ingress.

In ordinary Docker, Pitchfork's container mode handles `SIGTERM` and `SIGINT`, shuts down Symphony, and reaps orphaned processes. Namespace owns PID 1 and does not execute the image entrypoint; its declarative `symphony` session starts the entrypoint automatically whenever the Devbox starts. Pitchfork's `boot_start = true` then restores both configured daemons.

## Upgrade Symphony

Choose a reviewed upstream commit, then update `SYMPHONY_COMMIT` in `Dockerfile` and the pinned commit listed above. Rebuild the image, create a fresh Devbox, and verify the dashboard and a non-destructive Linear query before expiring the old Devbox.

## Verification

Without credentials, the container must fail closed before Symphony starts. With secret-backed environment variables present, verify:

```sh
mise --version
fnox --version
pitchfork --version
codex --version
symphony --help
test -w /workspaces/arrusted-development/.symphony/workspaces
```

Do not print the environment, run `set -x`, or include dashboard screenshots that might contain issue data or credentials during verification.
