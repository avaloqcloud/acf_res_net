output "vcns" {
    description = "VCN Info"
    value = { for v in oci_core_vcn.these : v.display_name => { id = v.id}}
}
