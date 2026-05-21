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




### Following statement are for validation of ACM certificate

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
  #zone_id         = data.aws_route53_zone.dnszone.id   # We'll define this
  zone_id = aws_route53_zone.mplexia_com.id
}

### Following statement are used for pointing regular DNS names to CloudFront distribution. We need to create both A and AAAA records for IPv4 and IPv6 support. Plus one ipv6 only for ipv6 only (testing)

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

resource "aws_route53_record" "www" {
  provider = aws.eu-west-1
  #zone_id = data.aws_route53_zone.dnszone.id
  zone_id = aws_route53_zone.mplexia_com.id
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
  #zone_id = data.aws_route53_zone.dnszone.id
  zone_id = aws_route53_zone.mplexia_com.id
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
  #zone_id = data.aws_route53_zone.dnszone.id
  zone_id = aws_route53_zone.mplexia_com.id
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