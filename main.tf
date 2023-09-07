##Nested Modules
# module "vcn" {
#   # source         = "./vcn"
#   compartment_id = module.configuration.setting.compartment_id
#   display_name = lower("${moduel.configuration.setting.name}_vcn")
#   dns_label = lower("${moduel.configuration.setting.name}")
  
#   depends_on = [ module.configuration ]
# }s

variable "settings" {
  type = object({
    compartment_id = string,
    name           = string,
    description    = string,
    cidr_blocks    = list(sting),
  })
  description = "Configuration parameter from the active oci account"
}

# Create VCNs
resource "oci_core_vcn" "these" {
  compartment_id = var.settings.compartment_id
  display_name   = var.settings.name
  dns_label      = var.settings.name
  cidr_blocks    = var.settings.cidr_blocks
}
