# superstatic
The purpose of this repo is to serve as a tool for automated setup of infrastructure and configurations necessary to fully realize hosting of a skeleton index.html (containing tags referencing custom stylesheet and script urls) to be served in response to any path requested at any one of multiple custom domains (no 404, all paths are responded to by AWS with index.html and 200). The index.html is the minimalist scaffolding upon which an entire single page application can developed while it is already live. App behavior is infinitely customizable after AWS deployment, by editing client-side javascript code after setup, without needing to redeploy or change anything on AWS. This is about getting something running cheaply and easily, then continuing to edit it in a language you know, executing in a context you are familiar with, with outcomes you can taste and feel.

The hosting is realized through static site hosting via S3 + CloudFront and DNS settings live on Porkbun (nameservers must be porkbun, but registar need not be porkbun)




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
2. Edit `../state-and-config/config/config.json`. Make sure that all the domains in the domains array have their DNS settings editable in a Porkbun account you control, and that they each have API access enabled from the Porkbun dashboard. Make sure that you are able to host the stylesheets and/or scripts, such that they will be accessible at the urls you input. 
3.  Edit `../state-and-config/config/porkbun.json` with your API credentials.
4. Optionally edit `../state-and-config/config/rootdomains.json` if you use multi-part public suffixes.
5. From the repo root: `./deploy`
6. Follow instructions output, rerunning step 5 if prompted to do so.
7.  `./deploy` will attempt to make changes within your AWS and Porkbun accounts, automatically setting configurations and setting up infrastructure in order to fully realize hosting of a skeleton index.html (containing your tags referencing your stylesheets and scripts) to be served in response to any path requested at any of the domains listed in `../state-and-config/config/config.json`. Once the deployment completes successfully, you can control what requests to the domain(s) actually look like on the client side, by editing the stylesheets and/or javascript files referenced in `../state-and-config/config/config.json`. One approach is to have one or more of the javascript files be a loader that loads other javascript files, as exemplified in `examples/example-loader.js

## Notes

- Generated files live under `state-and-config/state/`, but this is just a cache for temporary files. The logical outcome of running the deploy is not affected if this folder or its contents are removed.
- You can back up the whole `state-and-config` folder independently of the repo and then remove both it and the repo from your cloudshell. If you want to take down the website or redeploy it later, you can download the repo and copy over your backed up state-and-config instead of getting it from the examples folder referenced in the setup above. The scripts in this repo will locate and run on the previously deployed stack which will be referenced by the contents of the state-and-config/config folder.
- `loader_urls` and `style_urls` are each an array; each entry in these arrays  becomes a `<script src="..." defer>` or `<link rel="stylesheet" href="...">` in the head of  generated `index.html` (in order).
