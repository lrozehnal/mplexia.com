resource "aws_s3_bucket" "website" {
  provider = aws.eu-west-1
  bucket = local.aws_config_env.name
  tags = merge(local.tags, {
    Name        = local.aws_config_env.name
  })    
}

/* JUST ONCE 
import {
  to = aws_s3_bucket.website
  id = local.aws_config_env.name
}
*/



resource "aws_s3_bucket_website_configuration" "website" {
  bucket = aws_s3_bucket.website.id
  provider = aws.eu-west-1

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "404.html"
  }
}


/* # I don't think I need versioning
resource "aws_s3_bucket_versioning" "website" {
  bucket = aws_s3_bucket.website.id
  versioning_configuration {
    status = "Enabled"
  }
}
*/


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

data "aws_route53_zone" "dnszone" {
   provider = aws.eu-west-1
   name = local.aws_config_env.name
   private_zone = false
}


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

resource "aws_acm_certificate_validation" "website" {
  provider                = aws.us-east-1
  certificate_arn         = aws_acm_certificate.website.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}



resource "aws_cloudfront_origin_access_control" "website" {
  name                              = "mplexia-com-oac"
  description                       = "Origin Access Control for mplexia.com S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
  provider = aws.eu-west-1
}


# =============================================================================
# CloudFront Distribution
# =============================================================================

resource "aws_cloudfront_distribution" "website" {
  provider = aws.eu-west-1
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "mplexia.com - Hugo Static Website"
  default_root_object = "index.html"
  price_class         = "PriceClass_All"        # Use PriceClass_100 to save money

  # Your custom domains
  aliases = ["mplexia.com", "www.mplexia.com"]

  # ======================
  # S3 Origin (connected to OAC)
  # ======================
  origin {
    domain_name              = aws_s3_bucket.website.bucket_regional_domain_name
    origin_id                = "s3-origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.website.id
  }

  # ======================
  # Default Cache Behavior (HTML pages, etc.)
  # ======================
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

  # ======================
  # Long cache for static assets (better performance)
  # ======================
  ordered_cache_behavior {
    path_pattern     = "/assets/*"          # Adjust if your Hugo assets folder is different
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

  tags = {
    Name        = "mplexia.com"
    Environment = "production"
  }
}

resource "aws_route53_record" "apex" {
  provider = aws.eu-west-1
  zone_id = data.aws_route53_zone.dnszone.id
  name    = local.aws_config_env.name
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.website.domain_name
    zone_id                = aws_cloudfront_distribution.website.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "www" {
  provider = aws.eu-west-1
  zone_id = data.aws_route53_zone.dnszone.id
  name    = "www.${local.aws_config_env.name}"
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.website.domain_name
    zone_id                = aws_cloudfront_distribution.website.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "apex_ipv6" {
  provider = aws.eu-west-1
  zone_id = data.aws_route53_zone.dnszone.id
  name    = local.aws_config_env.name
  type    = "AAAA"
  alias {
    name                   = aws_cloudfront_distribution.website.domain_name
    zone_id                = aws_cloudfront_distribution.website.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "www_ipv6" {
  provider = aws.eu-west-1
  zone_id = data.aws_route53_zone.dnszone.id
  name    = "www.${local.aws_config_env.name}"
  type    = "AAAA"
  alias {
    name                   = aws_cloudfront_distribution.website.domain_name
    zone_id                = aws_cloudfront_distribution.website.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "ipv6_ipv6" {
  provider = aws.eu-west-1
  zone_id = data.aws_route53_zone.dnszone.id
  name    = "ipv6.${local.aws_config_env.name}"
  type    = "AAAA"
  alias {
    name                   = aws_cloudfront_distribution.website.domain_name
    zone_id                = aws_cloudfront_distribution.website.hosted_zone_id
    evaluate_target_health = false
  }
}

## THIS WAS A RECOMENDATION - ANNOYINGLY MY KNOWLEDGE OF BEST PRACTICES OF CLOUDFRONT / CDN IS NOT THE BEST
resource "aws_cloudfront_function" "www_redirect" {
  name    = "www-to-apex-redirect"
  runtime = "cloudfront-js-2.0"
  comment = "Redirect www.mplexia.com to mplexia.com"
  publish = true

  code = <<-EOF
function handler(event) {
    var request = event.request;
    var host = request.headers.host.value;

    // If the request comes to www.mplexia.com, redirect to apex
    if (host === 'www.mplexia.com' || host === 'www.mplexia.com:443') {
        var response = {
            statusCode: 301,
            statusDescription: 'Moved Permanently',
            headers: {
                'location': { 
                    value: 'https://mplexia.com' + request.uri 
                }
            }
        };
        return response;
    }

    return request;
}
EOF
}