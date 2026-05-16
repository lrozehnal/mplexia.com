+++
date = '2026-05-16T14:00:00+02:00'
draft = false
title = 'Making my life easier - updating github workflow'
description = "How to run 'hugo build' as part of the github workflow" 
tags = ["beginning", "gitops", "hugo", "markup","github-actions", "ci/cd", "automation"]
+++

## Why?

Easy answer - to make my life easier :) 
My current workflow is that I would 
1) make changes on my webside
2) run `hugo build` locally to generate the static files
3) commit and push the changes to github
4) github workflow would then run and deploy the changes to AWS S3
5) I would check if the changes are live on the website

And what keeps happening is that I forget to run `hugo build` before pushing the changes, which results in the website not being updated until I realize the mistake and push again after running `hugo build`. 
I am no content creator and this is a very manual process, so I want to automate it as much as possible and make it easier for myself.

## How?

I just need to update the github workflow to run `hugo build` as part of the workflow before deploying the changes to AWS S3.

This is the current workflow file:

```yaml
name: Deploy to S3

on:
  push:
    branches: [ main ]
  workflow_dispatch:

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: eu-west-1

      - name: Deploy to S3
        run: |
          aws s3 sync ./public s3://mplexia.com --delete

```

and I just need to add the `hugo build` command before the `aws s3 sync` command:

```yaml
name: Deploy to S3

on:
  push:
    branches: [ main ]
  workflow_dispatch:

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
          submodules: true

      - name: Setup Hugo
        uses: peaceiris/actions-hugo@v2
        with:
          hugo-version: '0.161.1'   
          extended: true

      - name: Build with Hugo
        run: hugo --minify

      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: eu-west-1

      - name: Deploy to S3
        run: |
          aws s3 sync ./public s3://mplexia.com --delete

```

and after that I just need to commit and push the changes to github and the workflow will run and deploy the changes to AWS S3, and I can check if the changes are live on the website.

Isn't that much easier? Automation is great, it saves time and reduces the chances of human error. Now I can focus on creating content and let the workflow take care of the rest. 