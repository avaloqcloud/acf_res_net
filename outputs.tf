output "vcns" {
  description = "The VCNs, indexed by display_name."
  value       = module.vcn.vcns
}

output "subnets" {
  description = "The subnets, indexed by display_name."
  value       = module.vcn.subnets
}

output "internet_gateways" {
  description = "The Internet gateways, indexed by display_name."
  value       = module.vcn.internet_gateways
}
