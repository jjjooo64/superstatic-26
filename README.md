# superstatic

S3 + CloudFront static site skeleton.  
Bare `index.html` loads a `loader.js` from a URL you supply.  
All missing paths return that `index.html` with HTTP 200 (no redirect).

## Layout
```
grandparent/
  porkbun.json                 ← API credentials
  parent/
    state-and-config/
      config/                  ← user files (config.json, rootdomains.json)
      state/                   ← generated (index.html, cert-arns.json)
    superstatic/               ← this repo
      deploy.sh
      examples/
        state-and-config/      ← copy this folder up one level
        example-loader.js
      …
```

If the repo folder is named `state-and-config`, `./deploy` refuses to run.

## Setup
1. Copy the example state-and-config folder next to the repo:
   ```bash
   cp -r examples/state-and-config ../
   ```
2. Edit `../state-and-config/config/config.json`.
3. Place your Porkbun credentials at `../../porkbun.json`.
4. From the repo root: `./deploy`

## Notes
- `./deploy` is the single entry point.
- Certificate must be an exact SAN match for the domains in config.
- Generated files live under `state-and-config/state/`.
- You can back up the whole `state-and-config` folder independently of the repo.
- `porkbun.json` stays one level above everything else so it is harder to commit by accident.
