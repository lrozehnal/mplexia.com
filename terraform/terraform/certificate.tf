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


resource "aws_acm_certificate_validation" "website" {
  provider                = aws.us-east-1
  certificate_arn         = aws_acm_certificate.website.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}



