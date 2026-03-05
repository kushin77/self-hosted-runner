module "aws_spot_runner" {
  source = "../../modules/aws_spot_runner"

  vpc_id          = var.vpc_id
  subnet_ids      = var.subnet_ids
  instance_type   = var.instance_type
  desired_capacity = var.desired_capacity
  max_capacity    = var.max_capacity
  key_name        = var.key_name
}

output "asg_id" {
  value = module.aws_spot_runner.asg_id
}
