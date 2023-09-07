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
    cidr           = string,
  })
  description = "Configuration parameter from the active oci account"
}

# Create VCNs
resource "oci_core_vcn" "these" {
  compartment_id = var.settings.compartment_id
  display_name   = var.settings.name
  dns_label      = var.settings.name
  cidr           = var.settings.cidr
  
  depends_on = [ module.configuration ]
}
