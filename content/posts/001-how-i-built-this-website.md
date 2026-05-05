+++
date = '2026-05-05T15:56:09+02:00'
draft = false
title = 'How I Built This Website'
description = "Quick write-up how I built this to-be-awsome website using Hugo, and AWS S3 hosting utilising GitHub Actions for CI/CD automation."
tags = ["beginning", "gitops", "hugo", "markup", "aws", "s3", "github-actions", "aws cli", "ci/cd", "automation"]
+++

# How I Built This Website

... and just like that, here we go...

## WHY
Few months ago, I decided to quit my corporate job - for various reasons the 'whys' however is a topic for another time - and go fully remote and fully contractor to.... help others with connectivity I guess - my initial thinking was that as I met many other organization which experience certain difficulties with connectivity especially with hybrid cloud, there must be tons and tons of opportunities for me to resolve those issues, right? well, wrong... 
After my last day, I took two months of holiday (mainly dealing with other issues) and as April started, I (re)created my limited company, updated my CV, clicked 'Open to' on LinkedIn and ... nothing happened... I pinged several recruiters and many ex-colleagues got few very friendly calls but ... nothing really happened... I created multiple profiles on multiple specialized websites, and ... nothing happened... after quick consultation with AI, the obvious suspicion become  painfully clear - "the portfolio" - big fat ZERO... nobody out there cares about what cool stuff I've done behind closed door of corporations...  so, let's showoff a thing or two


## WEBSITE
I already have a private AWS account, so (manually) registering a new domain mplexia.com for my entrepreneurial adventure is super easy. I know that I can publish a static website website via S3 bucket and so as the second step I (manually) create S3 bucket and upload manually (uff) helloworld.html and after few click and pointing my DNS to the S3 bucket ... boom .. the magic happens, the hello world...  

![hello world](/images/posts/001-how-i-built-this-website/helloworld.png)

But I need a website, so .. 'hey grok' and few minutes later I am provided with single index.html about what I think how awesome I am - which - surprisingly - doesn't look bad at all. Another quick interaction with grok and the integration with calendly.com is in place... quick test ... and it's working like a charm...
Copying the index.html file via web GUI is terrible... I am sorry too old/lazy for click-ops.. 

![aws s3 cp](/images/posts/001-how-i-built-this-website/initialweb.png)

Fortunately there's this AWS CLI -  https://aws.amazon.com/cli/ - so instead of uploading the index.html via gui, let use the command-line - it's super easy and powerful:
I need to generate AWS access keys, update the awscli profile file (the awscli was already installed)  and here we go: 

![aws s3 cp](/images/posts/001-how-i-built-this-website/awscli s3 cp.png)

I am able to copy files from my local device directly into AWS S3 bucket and it's update the whole website... Something like this:

![initial workflow](/images/posts/001-how-i-built-this-website/001-how-i-built-this-webserver-pic1.png)

But... there's always some "but", right? ... but .. I'd like to add some other system which I can use to improve the workflow even more ... a) I'd like to add some kind of content-management-system (CMS), b) I don't want to rely solely on my laptop and c) I want to be future prove and so I'd need to add some git repository... ideally one which can do a bit of CI/CD... why ... well, I don't want to 'copy files around' I want .. the automation do it for me ... Let's use github - personal decision - I know gitlab ci/cd but I've never worked with Github's Actions so I will learn something new and I already have an account at github... So the would be the initial plan:

![introducing git](/images/posts/001-how-i-built-this-website/001-how-i-built-this-webserver-pic2.png)

And now I need to add the github action: whenever I update the code (single index.html for now) and do 'git push', I need github to update the file(s) in S3 as well...

![using git](/images/posts/001-how-i-built-this-website/001-how-i-built-this-webserver-pic3.png)

After few minutes, this is what I got to be added  as some.yaml to .github/workflow/

```
name: Deploy to S3

on:
  push:
    branches: [ main ]
  workflow_dispatch:

jobs:
  deploy:
    runs-on: ubuntu-latest
#    environment: production
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


And here my the worries come: I need to upload my AWS access key to github so github can access my S3 bucket to publish the changes .. in other words to make my key (semi) public. Technically ANYONE can see those???  Apparently not - I quickly tested those and I am going to trust the documentation - very nice read! https://docs.github.com/en/actions  unless those are leaked within the run GitHub Action -  Oh my, the individual workflows are fully PUBLIC!!! my corporate-tuned brain goes mad... at least people has to log in to see the logs... and the keys are not leaked within the logs... OIDC is definitely on the menu here ... later ...

So this is how the simple workflow looks like:

and this is how to logs from github action looks like - no AWS key leaks 

![git actions log](/images/posts/001-how-i-built-this-website/gitactionlogs.png)

## CMS
Now I need to publish this my very first articles - hence I need some CMS app ... however I really like to utilize S3-backed static website - so I need something like server-side-static CMS... ?  quick lookup and it seems there's something call 'hugo' - https://gohugo.io/  the installation is pretty easy, it's just a "sudo port install hugo" on my laptop and just follow https://gohugo.io/getting-started/quick-start/ 
It seems I need to use a theme for markup ... and I am getting out of my waters here .. but it's not that difficult - after quick consultation I decided to go with blowfish ... it's just a markup, right? https://www.markdownguide.org/basic-syntax/  
Anyway, after several minutes to original page is rewritten as a text in markup (oh my, that's so ugly now ) and ready to be publish ... let's try ...  oh my ... the magic is back - it just works, the gitops is amazing , it's just 'git add / commit / push' and ... it's done...

## This article
Ok, this is something I am failing, I don't know how to publish articles - with picture ... this - at least for now - is a bit of pain - but no pain no gain, right? Ultimately, I need to run hugo
```
lrozehnal@mplex mplexia.com % hugo new posts/001-how-i-built-this-website.md
WARN  deprecated: project config key languageCode was deprecated in Hugo v0.158.0 and will be removed in a future release. Use locale instead.
WARN  Module "blowfish" is not compatible with this Hugo version: 0.141.0/0.160.1 extended; run "hugo mod graph" for more information.
Content "/Users/lrozehnal/git/mplexia.com/content/posts/001-how-i-built-this-website.md" created
lrozehnal@mplex mplexia.com %
```
and re-write the prepared article in markup, and link pictures and job done?? (ok this is definitely I need to learn to be better as this took me the longest but ... here we are!!)


## Git repo
as some people would ask - show me your code - here you are: https://github.com/lrozehnal/mplexia.com 