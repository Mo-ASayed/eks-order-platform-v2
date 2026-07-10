# Use currently available AZs so the dev stack is not tied to fixed zone names.
data "aws_availability_zones" "available" {
  state = "available"
}
