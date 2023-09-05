##Nested Modules
module "vcn" {
  compartment_id = var.compartment_id
  source         = "./vcn"
  vcns           = var.vcns
}
