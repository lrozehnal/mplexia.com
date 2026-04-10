# mplexia.com

Static landing page for **Mplexia Limited** – an independent technology consultancy.

## Structure

```
mplexia.com/
├── index.html      # Main landing page
├── css/
│   └── style.css   # All styles (dark theme, responsive)
├── js/
│   └── main.js     # Scroll behaviour, mobile nav, reveal animations
└── README.md
```

## Local preview

Open `index.html` directly in a browser, or serve with any static file server:

```bash
# Python 3
python -m http.server 8080

# Node (npx)
npx serve .
```

## Deploy to AWS S3 (static website hosting)

1. **Create / configure the S3 bucket**

   ```bash
   aws s3 mb s3://mplexia.com --region eu-west-1
   aws s3 website s3://mplexia.com \
     --index-document index.html \
     --error-document index.html
   ```

2. **Set a public-read bucket policy** (replace `mplexia.com` with your bucket name):

   ```json
   {
     "Version": "2012-10-17",
     "Statement": [{
       "Sid": "PublicRead",
       "Effect": "Allow",
       "Principal": "*",
       "Action": "s3:GetObject",
       "Resource": "arn:aws:s3:::mplexia.com/*"
     }]
   }
   ```

   ```bash
   aws s3api put-bucket-policy \
     --bucket mplexia.com \
     --policy file://bucket-policy.json
   ```

3. **Upload the site**

   ```bash
   aws s3 sync . s3://mplexia.com \
     --exclude ".git/*" \
     --exclude "README.md" \
     --delete
   ```

4. **Point your domain** – In Route 53 (or your DNS provider) create an **A alias**
   record for `mplexia.com` pointing to the S3 website endpoint, e.g.
   `mplexia.com.s3-website-eu-west-1.amazonaws.com`.

   For HTTPS, front the bucket with **CloudFront** and attach an ACM certificate.

## Tip – CloudFront + HTTPS (recommended)

```bash
# Create a CloudFront distribution pointing to the S3 website origin
# and attach an ACM certificate for mplexia.com (must be in us-east-1).
# Then update your DNS to point to the CloudFront domain.
```

---
© Mplexia Limited. All rights reserved.