provider "aws" {
  region  = "${var.aws_region}"
  profile = "${var.aws_profile}"
}

terraform {
  backend "s3" {}
}

data "terraform_remote_state" "vpc" {
  backend = "s3"

  config {
    bucket         = "${var.tfstate_bucket}"
    key            = "${var.tfstate_key_vpc}"
    region         = "${var.tfstate_region}"
    profile        = "${var.tfstate_profile}"
    role_arn       = "${var.tfstate_arn}"
  }
}

data "aws_security_groups" "ec2" {
  tags  = "${merge(var.source_security_group_tags,map("Env", "${var.project_env}"))}"

  filter {
    name   = "vpc-id"
    values = ["${data.terraform_remote_state.vpc.vpc_id}"]
  }
}

data "aws_lb_target_group" "ec2" {
  count = "${length(var.target_group_arns) > 0 ? 0 : 1}"
  name  = "${var.lb_tg_name}"
}

locals {
  security_groups   = "${flatten(coalescelist(data.aws_security_groups.ec2.*.ids,list()))}"
  dynamic_subnets   = [ "${split(",", var.in_public ? join(",", data.terraform_remote_state.vpc.public_subnets) : join(",", data.terraform_remote_state.vpc.private_subnets))}" ]
  subnets           = [ "${split(",", length(var.vpc_zone_identifier) == 0 ? join(",", local.dynamic_subnets) : join(",", var.vpc_zone_identifier))}" ]
  tags              = "${concat(var.tags,list(map("key","Env", "value","${var.project_env}", "propagate_at_launch",true)))}"
  key_name          = "${var.key_name == "" ? data.terraform_remote_state.vpc.key_name : var.key_name }"
  target_group_arns = [ "${split(",", length(var.target_group_arns) == 0 ? join(",", data.aws_lb_target_group.ec2.*.arn) : join(",", var.target_group_arns))}" ]
}

module "asg" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "2.11.0"

  name    = "${var.name}"

  # Launch configuration
  lc_name = "${var.lc_name}"

  image_id                    = "${var.image_id}"
  instance_type               = "${var.instance_type}"
  security_groups             = ["${local.security_groups}"]
  iam_instance_profile        = "${var.iam_instance_profile}"
  key_name                    = "${local.key_name}"
  associate_public_ip_address = "${var.associate_public_ip_address}"
  user_data                   = "${var.user_data}"
  enable_monitoring           = "${var.enable_monitoring}"
  spot_price                  = "${var.spot_price}"
  placement_tenancy           = "${var.spot_price == "" ? var.placement_tenancy : ""}"
  ebs_optimized               = "${var.ebs_optimized}"
  ebs_block_device            = "${var.ebs_block_device}"
  ephemeral_block_device      = "${var.ephemeral_block_device}"
  root_block_device           = "${var.root_block_device}"

  # Auto scaling group
  asg_name                  = "${var.asg_name}"
  vpc_zone_identifier       = ["${local.subnets}"]
  health_check_type         = "${var.health_check_type}"
  min_size                  = "${var.min_size}"
  max_size                  = "${var.max_size}"
  desired_capacity          = "${var.desired_capacity}"

  load_balancers            = ["${var.load_balancers}"]
  health_check_grace_period = "${var.health_check_grace_period}"
  health_check_type         = "${var.health_check_type}"

  min_elb_capacity          = "${var.min_elb_capacity}"
  wait_for_elb_capacity     = "${var.wait_for_elb_capacity}"
  target_group_arns         = ["${local.target_group_arns}"]
  default_cooldown          = "${var.default_cooldown}"
  force_delete              = "${var.force_delete}"
  termination_policies      = "${var.termination_policies}"
  suspended_processes       = "${var.suspended_processes}"
  placement_group           = "${var.placement_group}"
  enabled_metrics           = ["${var.enabled_metrics}"]
  metrics_granularity       = "${var.metrics_granularity}"
  wait_for_capacity_timeout = "${var.wait_for_capacity_timeout}"
  protect_from_scale_in     = "${var.protect_from_scale_in}"

  tags        = ["${local.tags}"]
  tags_as_map = "${var.tags_as_map}"
}
