variable "domain_name" {
  description = "Public DNS zone name, lab.mohammedsayed.com."
  type        = string
}

variable "tags" {
  description = "Tags applied to DNS resources."
  type        = map(string)
  default     = {}
}
