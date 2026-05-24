# Render Free Deployment

This project can be deployed as one Docker-based Render Web Service. The single
service serves the browser UI and runs the Python-to-Julia computation endpoint.

## What Render Runs

- `Dockerfile` uses the official Julia image and installs `python3`.
- `server/compute_server.py` serves `web/` and handles `POST /api/compute`.
- `render.yaml` declares a free Docker web service.

## Public Demo Limits

The public service uses conservative limits so a free instance is less likely to
be exhausted by accidental large inputs:

- `MAX_NODES=80`
- `MAX_REQUEST_BYTES=1048576`
- `COMPUTE_TIMEOUT_SECONDS=120`

These values are environment variables and can be raised later if a paid
instance is used.

## Render Setup

1. Push this repository to GitHub.
2. In Render, create a new Blueprint from the GitHub repository.
3. Confirm the service is named `critical-bc-calculator`.
4. Keep the instance type as `Free`.
5. Deploy.

After deployment, Render gives the app a public URL such as:

```text
https://critical-bc-calculator.onrender.com/
```

Free services can spin down after inactivity. The first request after a spin-down
may be slow because Render needs to start the service and Julia needs to warm up.
