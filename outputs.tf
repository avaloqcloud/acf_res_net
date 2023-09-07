output "vcns" {
    description = "VCN Info"
    value = {​​​​for vcn in oci_core_vcn.these : vcn.display_name
}
