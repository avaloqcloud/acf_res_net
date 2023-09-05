output "vcns" {
  description = "The VCNs, indexed by display_name."
  value       = { for v in oci_core_vcn.these : v.display_name => { id = v.id, cidr_block = v.cidr_block, dns_label = v.dns_label, default_security_list_id = v.default_security_list_id } }
}

output "subnets" {
  description = "The subnets, indexed by display_name."
  value       = { for s in oci_core_subnet.these : s.display_name => s }
}

output "internet_gateways" {
  description = "The Internet gateways, indexed by display_name."
  value       = { for g in oci_core_internet_gateway.these : g.vcn_id => g }
}
