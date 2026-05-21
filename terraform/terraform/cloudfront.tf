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


## THIS WAS A RECOMENDATION - ANNOYINGLY MY KNOWLEDGE OF BEST PRACTICES OF CLOUDFRONT / CDN IS NOT THE BEST
## BUT THIS IS A POLICY WHICH REDIRECTS WWW TO APEX 
## AND ALSO ADDS TRAILING SLASH TO DIRECTORIES - AS IT WASN'T USING /post/index.html when redirected to /post
## I GUESS THERE WILL BE MORE LATER

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