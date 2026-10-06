### THIS IS VERY DIRTY (ALL IN ONE) DEPLOYMNT FOR SQUID PROXY AS I'D NEED TO GET AN UK IP ADDDRESSS --- I WONDER IF THIS WILL WORK :) 


resource "aws_vpc" "eu-west-2" {
  provider         =  aws.eu-west-2
  cidr_block       = local.aws_config_env.vpc.eu-west-2.cidr
  tags = merge(local.tags, {
    Name = local.aws_config_env.vpc.eu-west-2.name
  })
}

data "aws_availability_zones" "eu_west_2" {
  provider = aws.eu-west-2
  state    = "available"
}

resource "aws_subnet" "eu-west-2" {
  provider         =  aws.eu-west-2
  for_each          = toset(data.aws_availability_zones.eu_west_2.names)
  vpc_id = aws_vpc.eu-west-2.id
  availability_zone = each.value
  cidr_block        = cidrsubnet(local.aws_config_env.vpc.eu-west-2.cidr,8,index(data.aws_availability_zones.eu_west_2.names, each.value))
  tags = merge(local.tags, {
    Name = "subnet-${each.value}"
  })
}

resource "aws_internet_gateway" "eu-west-2" {
  provider         =  aws.eu-west-2
  vpc_id = aws_vpc.eu-west-2.id
  tags = merge(local.tags, {
    Name = "IGW for eu-west-2"
  })
}

data "aws_route_table" "eu_west_2_main" {
  provider = aws.eu-west-2
  vpc_id   = aws_vpc.eu-west-2.id

  filter {
    name   = "association.main"
    values = ["true"]
  }
}

resource "aws_route" "eu_west_2_default" {
  provider               = aws.eu-west-2
  route_table_id         = data.aws_route_table.eu_west_2_main.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.eu-west-2.id
}

resource "aws_security_group" "eu_west_2" {
  provider    = aws.eu-west-2
  name        = "eu-west-2-app"
  description = "eu-west-2 app"
  vpc_id      = aws_vpc.eu-west-2.id

  tags = merge(local.tags, {
    Name = "eu-west-2-app"
  })
}

resource "aws_vpc_security_group_ingress_rule" "inbound_ssh" {
  provider          = aws.eu-west-2
  security_group_id = aws_security_group.eu_west_2.id
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = "0.0.0.0/0"
  description       = "ssh"
}


resource "aws_vpc_security_group_egress_rule" "outbound_all" {
  provider          = aws.eu-west-2
  security_group_id = aws_security_group.eu_west_2.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "all egress"
}

data "aws_ssm_parameter" "ec2_public_key" {
  name            = "/ec2/default/public-key"
  with_decryption = false
}

resource "aws_key_pair" "key-eu-west-2" {
  provider   = aws.eu-west-2
  key_name   = "ec2key-for-lab"   
  public_key = data.aws_ssm_parameter.ec2_public_key.value
  tags = merge(local.tags, {
    Name = "EC2 key for lab"
  })
}

data "aws_ami" "eu-west-2" {
  provider    = aws.eu-west-2
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-kernel-6.*-arm64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}





  resource "aws_instance" "uk-proxy" {
    provider    = aws.eu-west-2
    ami           = data.aws_ami.eu-west-2.id
    instance_type = "t4g.micro"
    key_name      = aws_key_pair.key-eu-west-2.key_name


    subnet_id                   = aws_subnet.eu-west-2["eu-west-2a"].id
    vpc_security_group_ids      = [aws_security_group.eu_west_2.id]
    associate_public_ip_address = true
    
    user_data = <<-EOF
                #!/bin/bash
                hostnamectl set-hostname uk-proxy.mplexia.com
                echo "127.0.0.1 uk-proxy.mplexia.com" >> /etc/hosts

                sudo dnf install -y amazon-ssm-agent  bind-utils socat telnet squid
                sudo systemctl enable --now amazon-ssm-agent          
                sudo systemctl enable --now squid
                EOF
    tags = merge(local.tags, {
      Name = "uk-proxy"
    })
  }


resource "aws_eip" "eu_west_2" {
  provider = aws.eu-west-2
  domain   = "vpc"
  instance = aws_instance.uk-proxy.id

  tags = merge(local.tags, {
    Name = "uk-proxy.mplexia.com"
  })
}





resource "aws_route53_record" "uk-proxy" {
  zone_id = aws_route53_zone.mplexia_com.zone_id
  name    = "uk-proxy.${local.aws_config_env.name}."
  type    = "A"
  ttl     = 300
  records = [aws_eip.eu_west_2.public_ip]
}


resource "aws_eip_domain_name" "eu_west_2" {
  provider      = aws.eu-west-2
  allocation_id = aws_eip.eu_west_2.allocation_id
  domain_name   = aws_route53_record.uk-proxy.fqdn
}