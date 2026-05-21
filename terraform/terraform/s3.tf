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

resource "aws_s3_bucket_versioning" "website" {
  bucket = aws_s3_bucket.website.id
  versioning_configuration {
    status = "Enabled"
  }
}

