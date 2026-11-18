# superstatic

S3 + CloudFront static site skeleton.  
Bare `index.html` loads one or more scripts from URLs you supply.  
All missing paths return that `index.html` with HTTP 200 (no redirect).

## Layout
```
parent/
  state-and-config/
    config/                  ← user files
      config.json
      porkbun.json
      rootdomains.json       ← optional
    state/                   ← generated
      index.html
      cert-arns.json
  superstatic/               ← this repo
    deploy.sh
    examples/
      state-and-config/      ← copy this folder up one level
      example-loader.js
    …
```



## Setup
The following setup steps assume the following are true:
  - This repository into your AWS cloudshell
  - You have cloudshell open and the working directory is the repo folder (the folder containing this readme)
  - The repo folder is not itself the root directory of your cloudshell (although it is ok for it to be in the root directory)
  - The folder containing the repo folder must not already contain a folder named `state-and-config`, and, by implication, the repo folder must not itself be named  `state-and-config` -  if the repo folder is named  `state-and-config` `./deploy` refuses to run. If another folder is  named  `state-and-config`, it will conflict with the name of the folder we will copy over and edit in the following steps
    
1. Copy the example state-and-config folder next to the repo:
   ```bash
   cp -r examples/state-and-config ../
   ```
2. Edit `../state-and-config/config/config.json`.
3. Edit `../state-and-config/config/porkbun.json` with your API credentials.
4. Optionally edit `../state-and-config/config/rootdomains.json` if you use multi-part public suffixes.
5. From the repo root: `./deploy`

## Notes
- `./deploy` is the single entry point.
- Certificate must be an exact SAN match for the domains in config.
- Generated files live under `state-and-config/state/`, but this is just a cache for temporary files. The logical outcome of running the program is not affected if this folder or its contents are removed.
- You can back up the whole `state-and-config` folder independently of the repo and then remove both it and the repo from your cloudshell. If you want to take down the website or redeploy it later, you can download the repo and copy over your backed up state-and-config instead of getting it from the examples folder referenced in the setup above. The program will locate and run on previously deployed stack which will be referenced by the contents of the state-and-config/config folder.
- `loader_urls` and `style_urls` are each an array; each entry in these arrays  becomes a `<script src="..." defer>` or `<link rel="stylesheet" href="...">` in the head of  generated `index.html` (in order).
