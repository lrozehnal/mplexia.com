+++
date = '2026-05-21T11:53:14+02:00'
draft = false
title = 'More Professional'
description = "Quick write-up how I improved this website"
tags = ["beginning", "gitops", "aws", "s3", "cloudfront"]
+++

My personal site started as a quick static page to prove I exist. It worked, but it was missing basic professional touches: HTTPS, proper caching, and infrastructure-as-code. Here's how I fixed it with Terraform, CloudFront, and a bit of CloudFront Functions."

## Problems Identified

### There's no TLS/SSL

As this website used to be very simplistic webpage for me to 'show I exists' and a place where I can place my posts - [001-how-i-built-this-website] but since day one some - (Gonzalo) - were pointing to the obvious - there's no TLS/SSL - not that I don't want to but the underlying technology (static website published off the S3 bucket) doesn't support HTTPS natively. 

### Denial-of-wallet

I was aware of this thing in general - basically somebody will request the S3 object and I will be charged for that - and this somebody can request the object million of times and I will be 40p (!!) but I was not aware how much it can cost me  (and how quickly) and CloudFront can be used to mitigate this risk significantly. 

### My inner terraform tyrant

My biggest concern was about the fact that I had to maintain this website and updated it and added new posts and I did't want to do it manually - I wanted to do it with code and as terraform is my tool of choice: I created the domain manually, the S3 bucket manually, I didn't remember if I've alloweded versioning or not ... the regular problems of the clickops - something has been completed, and just two eye-blinks later, you don't remember how you did it and how to do it again. This is not how we do those things in this household! :) 


## Let's terraform it, shall we?

### S3 bucket

Ok, let's start with the bucket - I already have a bucket (there the website lives) and get it under terraform - so I am going to use a combination of 'statement' for the S3 bucket but at the same time, I am going to import existing resource into it! 

```hcl
/* JUST ONCE 
import {
  to = aws_s3_bucket.website
  id = local.aws_config_env.name
}
*/

resource "aws_s3_bucket" "website" {
  provider = aws.eu-west-1
  bucket = local.aws_config_env.name
  tags = merge(local.tags, {
    Name        = local.aws_config_env.name
  })    
}

```

When I apply this, terraform will see that the bucket already exists and it will import it into the state file - so now I can manage it with terraform and I can be sure that if I need to create another bucket for some reason, I will do it with terraform and not clickops. Also I can now comment out the 'import' statement as I only need to do it once.

### Certificate

Next step is to get the TLS/SSL certificate - I am going to use AWS Certificate Manager (ACM) for this and I am going to request a certificate for my domain - and I will do it in the us-east-1 region as CloudFront only accepts certificates from that region. (I think I can use certificate from other region but I don't want to risk it and I don't want to do it twice - once for the certificate and once for the CloudFront distribution - all these certificates and IAMs things are just safer to be created in us-east-1 ;

Also I am going to use multiple names for the certificate - I want to have www and ipv6 subdomains as well - so I will request a certificate for my domain and also for www and ipv6 subdomains - this way I can use the same certificate for all of them and I don't have to worry about it in the future. Also if I'd like to utilise anything else, I can - (easily?) add new names ... so far it's a manual list but... we will see in the future as this is potentially another candidate to improve

```hcl
resource "aws_acm_certificate" "website" {
  provider = aws.us-east-1   

  domain_name               = local.aws_config_env.name
  subject_alternative_names = ["www.${local.aws_config_env.name}","ipv6.${local.aws_config_env.name}"]
  validation_method         = "DNS"
  
  tags = merge(local.tags, {
    Name        = local.aws_config_env.name
  })    

  lifecycle {
    create_before_destroy = true
  }
}


```

### Certificate validation

This is one of those things why I fall in love with terraform & AWS combo... the general challange is that I can request whatever CN within my certificate - e.g. google.com - and AWS - as CA - needs to reach out to me to prove that I am the owner / in control of the domain - and the way to do it is to create a DNS record with specific name and value - historically this was BIG problem - but now we live in 2nd quater of 21st century - and all I need to do is to tell AWS I want to verify by DNS and AWS will request me to create certain 'random' DNS records to prove I am the owner of the domain and AWS will check if that record exists and if it has the correct value - if it does, it will issue the certificate - if it doesn't, it will not. This literally screams for automation :) 

```hcl
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.website.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }
  provider = aws.eu-west-1
  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.dnszone.id   # We'll define this
}
```
what the heck? :) Well it's not that complicated - when I created the certificate in previous section, I requested the certificate for three names  - "mplexia.com" - (domain.name) and another two - "www.mplexia.com" and "ipv6.mplexia.com" - (subject_alternative_names) - so AWS will ask me to create three DNS records to prove that I am the owner of the domain - and these three records will be different for each name - so I need to create three records with different names and values - but I don't want to do it manually - so I am using 'for_each' to loop through all the domain validation options that AWS provides me and I am creating a record for each of them - and I am using 'allow_overwrite' because if I need to re-validate the certificate, I can just run terraform apply again and it will update the existing records with new values - this way I don't have to worry about deleting old records or creating new ones - terraform will take care of it for me.
Isn't this awesome? :) 

Two notes here: 1) I am creating the records in the same Route53 zone where my domain is - so I need to define the data source for that zone - this zone is something - similarly like the s3 bucket - I created manually some time ago - this is wrong and I need to fix this - later. 2) Creating the records for validation is not enough , it has to be requested with AWS to validate. Now this seems to be obvious but when I started with terraform years ago, I didn't know and I remember I spent several hours on "WHY THE VALIDATION IS NOT WORKING?!??!" as I didn't do:
```hcl
resource "aws_acm_certificate_validation" "website" {
  provider                = aws.us-east-1
  certificate_arn         = aws_acm_certificate.website.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}
```
(now I know and will remember forever: if DNS validation is required, creating of those DNS in not enough, you need to ASK AWS to valida)

### CloudFront distribution

I will be honest, this could be difficult - in theory I know very well, how CDN/Cloudfront works but in practice, not really and this really looks intimidating: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_distribution 
After checking an alternative source of inspiration - https://github.com/terraform-aws-modules/terraform-aws-cloudfront ( this collection on github is an absolutely brilliant source of inspiration - highly recommened! )  and a brief consultation with grok, I come up with this:

```hcl
resource "aws_cloudfront_origin_access_control" "website" {
  name                              = "mplexia-com-oac"
  description                       = "Origin Access Control for mplexia.com S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
  provider = aws.eu-west-1
}

resource "aws_cloudfront_distribution" "website" {
  provider = aws.eu-west-1
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "mplexia.com - Hugo Static Website"
  default_root_object = "index.html"
  price_class         = "PriceClass_100"        # Use PriceClass_100 to save money or PriceClass_All

  aliases = ["mplexia.com", "www.mplexia.com", "ipv6.mplexia.com"]

  origin {
    domain_name              = aws_s3_bucket.website.bucket_regional_domain_name
    origin_id                = "s3-origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.website.id
  }


  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "s3-origin"

    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    min_ttl     = 0
    default_ttl = 3600      # 1 hour
    max_ttl     = 86400     # 24 hours

    
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.www_redirect.arn
    }    
  }

  ordered_cache_behavior {
    path_pattern     = "/assets/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "s3-origin"

    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    min_ttl     = 0
    default_ttl = 31536000   # 1 year
    max_ttl     = 31536000

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.website.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = merge(local.tags, {
    Name        = local.aws_config_env.name
  }) 
}

```
I had few problems but I quickly figured out there could be a function_association which would control (or alternate) the generic behavious: some basic redirecton from www to the main non-www site.
Second issue I had was that e.g. request for /post was sent directly to S3 bucket and S3 bucket doesn't know how to handle it - it doesn't know that it should serve index.html file - so I had to add default_root_object = "index.html" to the distribution configuration - this way, if somebody goes to mplexia.com/post, CloudFront will serve mplexia.com/post/index.html and it will work as expected.  and I guess more will come:

```hcl
resource "aws_cloudfront_function" "www_redirect" {
  name    = "www-to-apex-redirect"
  runtime = "cloudfront-js-2.0"
  comment = "Redirect www.mplexia.com to mplexia.com"
  publish = true

code = <<-EOF
function handler(event) {
    var request = event.request;
    var uri = request.uri;

    // 1. www → non-www redirect
    var host = request.headers.host.value;
    if (host === "www.mplexia.com" || host === "www.mplexia.com:443") {
        var newUrl = "https://mplexia.com" + uri;
        if (request.querystring && Object.keys(request.querystring).length > 0) {
            newUrl += "?" + new URLSearchParams(
                Object.keys(request.querystring).map(k => [k, request.querystring[k].value])
            ).toString();
        }
        return {
            statusCode: 301,
            statusDescription: "Moved Permanently",
            headers: { "location": { "value": newUrl } }
        };
    }

    // 2. Trailing slash → add index.html
    if (uri.endsWith("/")) {
        request.uri = uri + "index.html";
    }
    // 3. If no extension and doesn't end with /, add /index.html (optional but nice)
    else if (!uri.includes(".")) {
        request.uri = uri + "/index.html";
    }

    return request;
}
EOF
}
```
And later, I can add more logic/magic to this function - this is the beauty of CloudFront Functions - they are very lightweight and they can be easily modified and deployed without any downtime - so I can experiment with them and see what works best for my website.

### DNS Cutover

As mentioned earlier, I created the route53 zone of mplexia.com manually (maybe it was created on my behalf when I registered it?) and it's outside of terraform (hence I was using terraform data to look it up). Generally, that's suboptimal as I want it to be 'under' terraform - so very similarly how I did the already-existing S3 bucket:

```hcl
## I import the already existing zone here
 /* JUST ONCE 
data "aws_route53_zone" "dnszone" {
   provider = aws.eu-west-1
   name = local.aws_config_env.name
   private_zone = false
}
  

import {
  to = aws_route53_zone.mplexia_com
  id = data.aws_route53_zone.dnszone.id
}
*/


resource "aws_route53_zone" "mplexia_com" {
  name = local.aws_config_env.name

  tags = merge(local.tags, {
    Name        = local.aws_config_env.name
  })
}

```
Lookup the existing zone and import it into my resource - once done / run one-time, I can comment it out (it's already imported)

and just add the DNS names ... 
```hcl

resource "aws_route53_record" "apex" {
  provider = aws.eu-west-1
  #zone_id = data.aws_route53_zone.dnszone.id
  zone_id = aws_route53_zone.mplexia_com.id
  name    = local.aws_config_env.name
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.website.domain_name
    zone_id                = aws_cloudfront_distribution.website.hosted_zone_id
    evaluate_target_health = false
  }
}

## TWO MORE - ommitted 

resource "aws_route53_record" "ipv6_ipv6" {
  provider = aws.eu-west-1
  #zone_id = data.aws_route53_zone.dnszone.id
  zone_id = aws_route53_zone.mplexia_com.id
  name    = "ipv6.${local.aws_config_env.name}"
  type    = "AAAA"
  alias {
    name                   = aws_cloudfront_distribution.website.domain_name
    zone_id                = aws_cloudfront_distribution.website.hosted_zone_id
    evaluate_target_health = false
  }
}
```

oh this is getting pretty long - this should be done slightly differently too (likely a list and check 'for_each') but about that some time next...

## Conclusion & Next Steps

This was great. I really enjoyed it - it's something which has to completed for some time and now as I was working on it I really liked how it turned out - I have a nice and secure website with TLS/SSL, yesterday, I didn't really know CloudFront but now I have CloudFront distribution which will cache my content and serve it faster to my users and I have everything under terraform which means that I can easily manage it and update it in the future - I can add new posts, I can change the configuration, I can experiment with CloudFront Functions and see what works best for my website - this is really great and I'm looking forward to see how it evolves in the future as I also managed to get myself more stuff which I can improve!

As usually, the source code is here: https://github.com/lrozehnal/mplexia.com/tree/main/terraform 