# Deployment

Production currently resolves to `43.173.94.85`, so the repo deploy workflow uses SSH to update the server directly.

## Normal Flow

1. Commit changes locally.
2. Push to `main`.
3. GitHub Actions connects to the server, pulls `origin/main`, restarts the app, and checks the public site.

## Required GitHub Secrets

Add these in GitHub repo settings:

`Settings` -> `Secrets and variables` -> `Actions` -> `New repository secret`

| Secret | Example | Notes |
| --- | --- | --- |
| `DEPLOY_HOST` | `43.173.94.85` | Use the server that `ai-sticker-maker.com` points to. |
| `DEPLOY_USER` | `ubuntu` | Server login user. |
| `DEPLOY_SSH_KEY` | private key text | Recommended over password deploys. |
| `DEPLOY_PORT` | `22` | Optional if SSH uses port 22. |
| `DEPLOY_APP_DIR` | `/opt/stickerbaker` | Absolute project path on the server. |
| `DEPLOY_RESTART_COMMAND` | `docker compose up -d --build` | Optional custom restart command. The workflow runs `/app/bin/migrate` afterward when a compose file is present. |
| `DEPLOY_HEALTH_URL` | `https://ai-sticker-maker.com/` | Optional health check URL. |

## Recommended SSH Key Setup

On your local machine or a secure admin machine:

```bash
ssh-keygen -t ed25519 -C "github-actions-ai-sticker-maker" -f github-actions-ai-sticker-maker
```

Add the public key to the server user's `~/.ssh/authorized_keys`.

Put the private key content into `DEPLOY_SSH_KEY`.

## Server Restart Detection

The workflow tries these in order:

1. `DEPLOY_RESTART_COMMAND`, if configured, followed by `/app/bin/migrate` and `docker compose up -d app` when a compose file exists.
2. `docker compose build app`, `/app/bin/migrate`, and `docker compose up -d app`, if a compose file exists.
3. `sudo systemctl restart sticker`, if `sticker.service` exists.

Set `DEPLOY_RESTART_COMMAND` when the server uses a custom command.

## Manual Deploy

You can still run the workflow manually from:

`Actions` -> `Server Deploy` -> `Run workflow`
