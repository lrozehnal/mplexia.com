locals {
  aws_config_env = yamldecode(file("../config/config.yaml"))
  tags = {
    terraform = "yes"
    github    = "https://github.com/lrozehnal/mplexia.com"
  }
}

