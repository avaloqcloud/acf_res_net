##Nested Modules
# module "vcn" {
#   # source         = "./vcn"
#   compartment_id = module.configuration.setting.compartment_id
#   display_name = lower("${moduel.configuration.setting.name}_vcn")
#   dns_label = lower("${moduel.configuration.setting.name}")
  
#   depends_on = [ module.configuration ]
# }s


# Create VCNs
resource "oci_core_vcn" "these" {
  compartment_id = module.configuration.setting.compartment_id
  display_name = lower("${moduel.configuration.setting.name}_vcn")
  dns_label = lower("${moduel.configuration.setting.name}")
  
  depends_on = [ module.configuration ]
}
