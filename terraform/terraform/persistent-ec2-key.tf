## this will create a permanent key which I can use everywhere else and I don't have to deal with it again. 
## I will store the private key in SSM Parameter Store as a SecureString and the public key as a String. 
## This way I can easily retrieve the keys when needed and I don't have to worry about losing them or changing it all the time


resource "tls_private_key" "main" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "main" {
  provider   = aws.eu-west-1
  key_name   = "ec2key"
  public_key = tls_private_key.main.public_key_openssh

  tags = merge(local.tags, {
    Name        = local.aws_config_env.name
  })
}

resource "aws_ssm_parameter" "private_key" {
  provider   = aws.eu-west-1
  name  = "/ec2/default/private-key"
  type  = "SecureString"
  value = tls_private_key.main.private_key_pem

  tags = merge(local.tags, {
    Name = " Default EC2 Private Key"
  })
}

resource "aws_ssm_parameter" "public_key" {
  provider   = aws.eu-west-1
  name  = "/ec2/default/public-key"
  type  = "String"
  value = tls_private_key.main.public_key_openssh
  tags = merge(local.tags, {
    Name = " Default EC2 Public Key"
  })
}

## IN THE OTHER TERRAFORM REPOSITORIES,  I CAN JUST EASILY READ IT 
## following section is commented out as it's an example how to use it somewhere else.... 
/*

# Read the private key
data "aws_ssm_parameter" "ec2_private_key" {
  name            = "/ec2/default/private-key"
  with_decryption = true
}

# Read the public key (optional but useful)
data "aws_ssm_parameter" "ec2_public_key" {
  name            = "/ec2/default/public-key"
  with_decryption = false
}

# Create the key pair in AWS (using the permanent public key)
resource "aws_key_pair" "key-eu-west-1" {
  provider   = aws.eu-west-1
  key_name   = "ec2key-for-lab"   # You can keep this name stable
  public_key = data.aws_ssm_parameter.ec2_public_key.value

  tags = merge(local.tags, {
    Name = "EC2 key for lab"
  })
}

# Create the key pair in AWS (using the permanent public key)
resource "aws_key_pair" "key-eu-west-2" {
  provider   = aws.eu-west-2
  key_name   = "ec2key-for-lab"   # You can keep this name stable
  public_key = data.aws_ssm_parameter.ec2_public_key.value

  tags = merge(local.tags, {
    Name = "EC2 key for lab"
  })
}
*/