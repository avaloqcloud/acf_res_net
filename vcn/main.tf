locals {
  subnets_in_vcn = flatten([
    for each_vcn in var.vcns : [
      for each_subnet in each_vcn["subnets"] : {
        cidr_block                 = each_subnet.cidr_block
        vcn_name                   = each_vcn.vcn_name
        vcn_display_name           = each_vcn.display_name
        display_name               = each_subnet.display_name != "" ? each_subnet.display_name : "subnet_${each_subnet.cidr_block}"
        subnet_is_create           = each_subnet.is_create
        dns_label                  = each_subnet.dns_label
        prohibit_internet_ingress  = each_subnet.prohibit_internet_ingress
        prohibit_public_ip_on_vnic = each_subnet.prohibit_public_ip_on_vnic
        is_create_dns_forwarder    = each_subnet.is_create_dns_forwarder
        route_rules                = each_subnet["route_rules"]
        traffic_rules              = each_subnet["traffic_rules"]
        dynamic_routing_gateway    = each_vcn["dynamic_routing_gateway"]
        dns                        = each_subnet["dns"]
      }
    ]
  ])
  default_security_list_opt = {
    display_name   = "unnamed"
    compartment_id = null
    ingress_rules  = []
    egress_rules   = []
  }
}

# Provides the list of Services in OCI
data "oci_core_services" "all_services" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

# Create VCNs
resource "oci_core_vcn" "these" {
  for_each = { for vcn in var.vcns : vcn.vcn_name => vcn }

  #Required
  compartment_id = var.compartment_id
  #Optional
  display_name = each.value.display_name
  dns_label    = each.value.dns_label
  cidr_blocks  = each.value.cidr_blocks
}

# Create subnets
resource "oci_core_subnet" "these" {
  for_each = { for subnet in local.subnets_in_vcn : "${subnet.vcn_name}_${subnet.dns_label}" => subnet if subnet.subnet_is_create == true }

  #Required
  compartment_id = var.compartment_id
  cidr_block     = each.value.cidr_block
  vcn_id         = lookup(oci_core_vcn.these, each.value.vcn_name).id
  #Optional
  display_name               = each.value.display_name
  dns_label                  = each.value.dns_label
  prohibit_internet_ingress  = each.value.prohibit_internet_ingress
  prohibit_public_ip_on_vnic = each.value.prohibit_public_ip_on_vnic
  #route_table_id             = oci_core_route_table.vcn_route_table.id
  security_list_ids = [lookup(oci_core_security_list.these, "${each.value.vcn_name}_${each.value.dns_label}").id]
}

# Create Internet Gateway
resource "oci_core_internet_gateway" "these" {
  for_each = { for internet_gateway in var.vcns : "${internet_gateway.vcn_name}-igw" => internet_gateway if internet_gateway.internet_gateway.is_create == true }

  #Required
  compartment_id = var.compartment_id
  vcn_id         = lookup(oci_core_vcn.these, each.value.vcn_name).id
  #Optional
  display_name = "${each.value.vcn_name}_internet_gateway"
  enabled      = each.value.internet_gateway.enabled
}

# Create NAT Gateway
resource "oci_core_nat_gateway" "these" {
  for_each = { for nat_gateway in var.vcns : "${nat_gateway.vcn_name}-ngw" => nat_gateway if nat_gateway.nat_gateway.is_create == true }

  #Required
  compartment_id = var.compartment_id
  vcn_id         = lookup(oci_core_vcn.these, each.value.vcn_name).id
  #Optional
  display_name  = "${each.value.vcn_name}_nat_gateway"
  block_traffic = each.value.nat_gateway.block_traffic
}

# Create Service Gateway
resource "oci_core_service_gateway" "these" {
  for_each = { for service_gateway in var.vcns : "${service_gateway.vcn_name}-sgw" => service_gateway if service_gateway.service_gateway.is_create == true }

  #Required
  compartment_id = var.compartment_id
  vcn_id         = lookup(oci_core_vcn.these, each.value.vcn_name).id
  services {
    service_id = data.oci_core_services.all_services.services[0].id
  }
  #Optional
  display_name = data.oci_core_services.all_services.services[0].name
}

# Create Dynamic Routing Gateway
resource "oci_core_drg" "these" {
  for_each = { for drg in var.vcns : "${drg.vcn_name}-drg" => drg if drg.dynamic_routing_gateway.drg_id == "" && drg.dynamic_routing_gateway.is_attach == true }

  #Required
  compartment_id = var.compartment_id
  #Optional
  display_name = "${each.value.vcn_name}_dynamic_routing_gateway"
}

# DRG attachment to VCN
resource "oci_core_drg_attachment" "these" {
  for_each = { for drg in var.vcns : "${drg.vcn_name}-drg-attachment" => drg if drg.dynamic_routing_gateway.is_attach == true }

  #Required
  drg_id       = length(oci_core_drg.these) > 0 ? lookup(oci_core_drg.these, "${each.value.vcn_name}-drg").id : each.value.dynamic_routing_gateway.drg_id
  vcn_id       = lookup(oci_core_vcn.these, each.value.vcn_name).id
  display_name = "${each.value.vcn_name}_drg_attachment"
}

# Create Local Peering Gateway
resource "oci_core_local_peering_gateway" "these" {
  for_each = { for local_peering_gateway in var.vcns : "${local_peering_gateway.vcn_name}-lpg" => local_peering_gateway if local_peering_gateway.local_peering_gateway.is_create == true }

  #Required
  compartment_id = var.compartment_id
  vcn_id         = lookup(oci_core_vcn.these, each.value.vcn_name).id
  #Optional
  display_name = "${each.value.vcn_name}_local_peering_gateway"
  peer_id = each.value.local_peering_gateway.peer_id == "" ? null : each.value.local_peering_gateway.peer_id
}

## Route tables
resource "oci_core_route_table" "these" {
  for_each = { for route_table in local.subnets_in_vcn : "${route_table.vcn_name}_${route_table.dns_label}-route_table" => route_table }

  display_name   = each.value.subnet_is_create == true ? "${each.value.display_name}_route_table" : "ava_default_route_table"
  vcn_id         = lookup(oci_core_vcn.these, each.value.vcn_name).id
  compartment_id = var.compartment_id
  dynamic "route_rules" {
    iterator = rule
    for_each = [for route_rule in each.value.route_rules : {
      destination : route_rule.target != "sgw" ? route_rule.destination : data.oci_core_services.all_services.services[0].cidr_block
      destination_type : route_rule.target != "sgw" ? route_rule.destination_type : "SERVICE_CIDR_BLOCK"
      network_entity_id : route_rule.target == "igw" ? lookup(oci_core_internet_gateway.these, "${each.value.vcn_name}-igw").id : route_rule.target == "ngw" ? lookup(oci_core_nat_gateway.these, "${each.value.vcn_name}-ngw").id : route_rule.target == "lpg" ? lookup(oci_core_local_peering_gateway.these, "${each.value.vcn_name}-lpg").id : route_rule.target == "sgw" ? lookup(oci_core_service_gateway.these, "${each.value.vcn_name}-sgw").id : route_rule.target == "drg" ? length(oci_core_drg.these) > 0 ? lookup(oci_core_drg.these, "${each.value.vcn_name}-drg").id : each.value.dynamic_routing_gateway.drg_id : ""
      description : route_rule.description
    } if route_rule.is_create == true]

    content {
      destination       = rule.value.destination
      destination_type  = rule.value.destination_type
      network_entity_id = rule.value.network_entity_id
      description       = rule.value.description
    }
  }
}

# Route Table Attachments
resource "oci_core_route_table_attachment" "these" {
  for_each       = { for subnet in local.subnets_in_vcn : "${subnet.vcn_name}_${subnet.dns_label}-route_table_attachment" => subnet if subnet.subnet_is_create == true }
  subnet_id      = lookup(oci_core_subnet.these, "${each.value.vcn_name}_${each.value.dns_label}").id
  route_table_id = lookup(oci_core_route_table.these, "${each.value.vcn_name}_${each.value.dns_label}-route_table").id
}

#### Security ####
resource "oci_core_security_list" "these" {
  for_each = { for traffic_rule in local.subnets_in_vcn : "${traffic_rule.vcn_name}_${traffic_rule.dns_label}" => traffic_rule }

  #  display_name   = "${each.value.vcn_display_name}_${each.value.display_name}_security_list"
  display_name   = each.value.subnet_is_create == true ? "${each.value.vcn_display_name}_${each.value.display_name}_security_list" : "ava_default_security_list"
  vcn_id         = lookup(oci_core_vcn.these, each.value.vcn_name).id
  compartment_id = var.compartment_id


  #  egress, proto: TCP  - no src port, no dst port
  dynamic "egress_security_rules" {
    iterator = rule
    for_each = [
      for x in each.value.traffic_rules["egress"] != null ? each.value.traffic_rules["egress"] : local.default_security_list_opt.egress_rules :
      {
        proto : x.protocol
        dst : x.dst
        dst_type : x.dst_type
        stateless : x.stateless
        description : x.description
      } if x.protocol == "6" && x.src_port == null && x.dst_port == null
    ]

    content {
      protocol         = rule.value.proto
      destination      = rule.value.dst
      destination_type = rule.value.dst_type
      stateless        = rule.value.stateless
      description      = rule.value.description
    }
  }

  #  egress, proto: TCP  - src port, no dst port
  dynamic "egress_security_rules" {
    iterator = rule
    for_each = [
      for x in each.value.traffic_rules["egress"] != null ? each.value.traffic_rules["egress"] : local.default_security_list_opt.egress_rules :
      {
        proto : x.protocol
        dst : x.dst
        dst_type : x.dst_type
        stateless : x.stateless
        src_port_min : x.src_port.min
        src_port_max : x.src_port.max
        description : x.description
      } if x.protocol == "6" && x.src_port != null && x.dst_port == null
    ]

    content {
      protocol         = rule.value.proto
      destination      = rule.value.dst
      destination_type = rule.value.dst_type
      stateless        = rule.value.stateless
      description      = rule.value.description

      tcp_options {
        source_port_range {
          max = rule.value.src_port_max
          min = rule.value.src_port_min
        }
      }
    }
  }

  #  egress, proto: TCP  - no src port, dst port
  dynamic "egress_security_rules" {
    iterator = rule
    for_each = [
      for x in each.value.traffic_rules["egress"] != null ? each.value.traffic_rules["egress"] : local.default_security_list_opt.egress_rules :
      {
        proto : x.protocol
        dst : x.dst
        dst_type : x.dst_type
        stateless : x.stateless
        dst_port_min : x.dst_port.min
        dst_port_max : x.dst_port.max
        description : x.description
      } if x.protocol == "6" && x.src_port == null && x.dst_port != null
    ]

    content {
      protocol         = rule.value.proto
      destination      = rule.value.dst
      destination_type = rule.value.dst_type
      stateless        = rule.value.stateless
      description      = rule.value.description

      tcp_options {
        max = rule.value.dst_port_max
        min = rule.value.dst_port_min
      }
    }
  }

  #  egress, proto: TCP  - src port, dst port
  dynamic "egress_security_rules" {
    iterator = rule
    for_each = [
      for x in each.value.traffic_rules["egress"] != null ? each.value.traffic_rules["egress"] : local.default_security_list_opt.egress_rules :
      {
        proto : x.protocol
        dst : x.dst
        dst_type : x.dst_type
        stateless : x.stateless
        src_port_min : x.src_port.min
        src_port_max : x.src_port.max
        dst_port_min : x.dst_port.min
        dst_port_max : x.dst_port.max
        description : x.description
      } if x.protocol == "6" && x.src_port != null && x.dst_port != null
    ]

    content {
      protocol         = rule.value.proto
      destination      = rule.value.dst
      destination_type = rule.value.dst_type
      stateless        = rule.value.stateless
      description      = rule.value.description

      tcp_options {
        max = rule.value.dst_port_max
        min = rule.value.dst_port_min

        source_port_range {
          max = rule.value.src_port_max
          min = rule.value.src_port_min
        }
      }
    }
  }

  #  egress, proto: UDP  - no src port, no dst port
  dynamic "egress_security_rules" {
    iterator = rule
    for_each = [
      for x in each.value.traffic_rules["egress"] != null ? each.value.traffic_rules["egress"] : local.default_security_list_opt.egress_rules :
      {
        proto : x.protocol
        dst : x.dst
        dst_type : x.dst_type
        stateless : x.stateless
        description : x.description
      } if x.protocol == "17" && x.src_port == null && x.dst_port == null
    ]

    content {
      protocol         = rule.value.proto
      destination      = rule.value.dst
      destination_type = rule.value.dst_type
      stateless        = rule.value.stateless
      description      = rule.value.description
    }
  }

  #  egress, proto: UDP  - src port, no dst port
  dynamic "egress_security_rules" {
    iterator = rule
    for_each = [
      for x in each.value.traffic_rules["egress"] != null ? each.value.traffic_rules["egress"] : local.default_security_list_opt.egress_rules :
      {
        proto : x.protocol
        dst : x.dst
        dst_type : x.dst_type
        stateless : x.stateless
        src_port_min : x.src_port.min
        src_port_max : x.src_port.max
        description : x.description
      } if x.protocol == "17" && x.src_port != null && x.dst_port == null
    ]

    content {
      protocol         = rule.value.proto
      destination      = rule.value.dst
      destination_type = rule.value.dst_type
      stateless        = rule.value.stateless
      description      = rule.value.description

      udp_options {
        source_port_range {
          max = rule.value.src_port_max
          min = rule.value.src_port_min
        }
      }
    }
  }

  #  egress, proto: UDP  - no src port, dst port
  dynamic "egress_security_rules" {
    iterator = rule
    for_each = [
      for x in each.value.traffic_rules["egress"] != null ? each.value.traffic_rules["egress"] : local.default_security_list_opt.egress_rules :
      {
        proto : x.protocol
        dst : x.dst
        dst_type : x.dst_type
        stateless : x.stateless
        dst_port_min : x.dst_port.min
        dst_port_max : x.dst_port.max
        description : x.description
      } if x.protocol == "17" && x.src_port == null && x.dst_port != null
    ]

    content {
      protocol         = rule.value.proto
      destination      = rule.value.dst
      destination_type = rule.value.dst_type
      stateless        = rule.value.stateless
      description      = rule.value.description

      udp_options {
        max = rule.value.dst_port_max
        min = rule.value.dst_port_min
      }
    }
  }

  #  egress, proto: UDP  - src port, dst port
  dynamic "egress_security_rules" {
    iterator = rule
    for_each = [
      for x in each.value.traffic_rules["egress"] != null ? each.value.traffic_rules["egress"] : local.default_security_list_opt.egress_rules :
      {
        proto : x.protocol
        dst : x.dst
        dst_type : x.dst_type
        stateless : x.stateless
        src_port_min : x.src_port.min
        src_port_max : x.src_port.max
        dst_port_min : x.dst_port.min
        dst_port_max : x.dst_port.max
        description : x.description
      } if x.protocol == "17" && x.src_port != null && x.dst_port != null
    ]

    content {
      protocol         = rule.value.proto
      destination      = rule.value.dst
      destination_type = rule.value.dst_type
      stateless        = rule.value.stateless
      description      = rule.value.description

      udp_options {
        max = rule.value.dst_port_max
        min = rule.value.dst_port_min

        source_port_range {
          max = rule.value.src_port_max
          min = rule.value.src_port_min
        }
      }
    }
  }

  #  egress, proto: ICMP  - no type, no code
  dynamic "egress_security_rules" {
    iterator = rule
    for_each = [
      for x in each.value.traffic_rules["egress"] != null ? each.value.traffic_rules["egress"] : local.default_security_list_opt.egress_rules :
      {
        proto : x.protocol
        dst : x.dst
        dst_type : x.dst_type
        stateless : x.stateless
        description : x.description
      } if x.protocol == "1" && x.icmp_type == null && x.icmp_code == null
    ]

    content {
      protocol         = rule.value.proto
      destination      = rule.value.dst
      destination_type = rule.value.dst_type
      stateless        = rule.value.stateless
      description      = rule.value.description
    }
  }

  #  egress, proto: ICMP  - type, no code
  dynamic "egress_security_rules" {
    iterator = rule
    for_each = [
      for x in each.value.traffic_rules["egress"] != null ? each.value.traffic_rules["egress"] : local.default_security_list_opt.egress_rules :
      {
        proto : x.protocol
        dst : x.dst
        dst_type : x.dst_type
        stateless : x.stateless
        type : x.icmp_type
        description : x.description
      } if x.protocol == "1" && x.icmp_type != null && x.icmp_code == null
    ]

    content {
      protocol         = rule.value.proto
      destination      = rule.value.dst
      destination_type = rule.value.dst_type
      stateless        = rule.value.stateless
      description      = rule.value.description

      icmp_options {
        type = rule.value.type
      }
    }
  }

  #  egress, proto: ICMP  - type, code
  dynamic "egress_security_rules" {
    iterator = rule
    for_each = [
      for x in each.value.traffic_rules["egress"] != null ? each.value.traffic_rules["egress"] : local.default_security_list_opt.egress_rules :
      {
        proto : x.protocol
        dst : x.dst
        dst_type : x.dst_type
        stateless : x.stateless
        type : x.icmp_type
        code : x.icmp_code
        description : x.description
      } if x.protocol == "1" && x.icmp_type != null && x.icmp_code != null
    ]

    content {
      protocol         = rule.value.proto
      destination      = rule.value.dst
      destination_type = rule.value.dst_type
      stateless        = rule.value.stateless
      description      = rule.value.description

      icmp_options {
        type = rule.value.type
        code = rule.value.code
      }
    }
  }

  #  egress, proto: other (non-TCP, UDP or ICMP)
  dynamic "egress_security_rules" {
    iterator = rule
    for_each = [
      for x in each.value.traffic_rules["egress"] != null ? each.value.traffic_rules["egress"] : local.default_security_list_opt.egress_rules :
      {
        proto : x.protocol
        dst : x.dst
        dst_type : x.dst_type
        stateless : x.stateless
        description : x.description
      } if x.protocol != "1" && x.protocol != "6" && x.protocol != "17"
    ]

    content {
      protocol         = rule.value.proto
      destination      = rule.value.dst
      destination_type = rule.value.dst_type
      stateless        = rule.value.stateless
      description      = rule.value.description
    }
  }

  #   ingress, proto: TCP  - no src port, no dst port
  dynamic "ingress_security_rules" {
    iterator = rule
    for_each = [
      for x in each.value.traffic_rules["ingress"] != null ? each.value.traffic_rules["ingress"] : local.default_security_list_opt.ingress_rules :
      {
        proto : x.protocol
        src : x.src
        src_type : x.src_type
        stateless : x.stateless
        description : x.description
      } if x.protocol == "6" && x.src_port == null && x.dst_port == null
    ]

    content {
      protocol    = rule.value.proto
      source      = rule.value.src
      source_type = rule.value.src_type
      stateless   = rule.value.stateless
      description = rule.value.description
    }
  }

  # ingress, proto: TCP  - src port, no dst port
  dynamic "ingress_security_rules" {
    iterator = rule
    for_each = [
      for x in each.value.traffic_rules["ingress"] != null ? each.value.traffic_rules["ingress"] : local.default_security_list_opt.ingress_rules :
      {
        proto : x.protocol
        src : x.src
        src_type : x.src_type
        stateless : x.stateless
        src_port_min : x.src_port.min
        src_port_max : x.src_port.max
        description : x.description
      } if x.protocol == "6" && x.src_port != null && x.dst_port == null
    ]

    content {
      protocol    = rule.value.proto
      source      = rule.value.src
      source_type = rule.value.src_type
      stateless   = rule.value.stateless
      description = rule.value.description

      tcp_options {
        source_port_range {
          max = rule.value.src_port_max
          min = rule.value.src_port_min
        }
      }
    }
  }

  # ingress, proto: TCP  - no src port, dst port
  dynamic "ingress_security_rules" {
    iterator = rule
    for_each = [
      for x in each.value.traffic_rules["ingress"] != null ? each.value.traffic_rules["ingress"] : local.default_security_list_opt.ingress_rules :
      {
        proto : x.protocol
        src : x.src
        src_type : x.src_type
        stateless : x.stateless
        dst_port_min : x.dst_port.min
        dst_port_max : x.dst_port.max
        description : x.description
      }
      if x.protocol == "6" && x.src_port == null && x.dst_port != null ? x.src != var.anywhere_cidr || x.src == var.anywhere_cidr && length(setintersection(range(x.dst_port.min, x.dst_port.max + 1), var.ports_not_allowed_from_anywhere_cidr)) == 0 : false ? true : false
    ]

    content {
      protocol    = rule.value.proto
      source      = rule.value.src
      source_type = rule.value.src_type
      stateless   = rule.value.stateless
      description = rule.value.description
      tcp_options {
        max = rule.value.dst_port_max
        min = rule.value.dst_port_min
      }
    }
  }

  # ingress, proto: TCP  - src port, dst port
  dynamic "ingress_security_rules" {
    iterator = rule
    for_each = [
      for x in each.value.traffic_rules["ingress"] != null ? each.value.traffic_rules["ingress"] : local.default_security_list_opt.ingress_rules :
      {
        proto : x.protocol
        src : x.src
        src_type : x.src_type
        stateless : x.stateless
        src_port_min : x.src_port.min
        src_port_max : x.src_port.max
        dst_port_min : x.dst_port.min
        dst_port_max : x.dst_port.max
        description : x.description
      }
      if x.protocol == "6" && x.src_port != null && x.dst_port != null ? x.src != var.anywhere_cidr || x.src == var.anywhere_cidr && length(setintersection(range(x.dst_port.min, x.dst_port.max + 1), var.ports_not_allowed_from_anywhere_cidr)) == 0 : false ? true : false
    ]

    content {
      protocol    = rule.value.proto
      source      = rule.value.src
      source_type = rule.value.src_type
      stateless   = rule.value.stateless
      description = rule.value.description

      tcp_options {
        max = rule.value.dst_port_max
        min = rule.value.dst_port_min

        source_port_range {
          max = rule.value.src_port_max
          min = rule.value.src_port_min
        }
      }
    }
  }

  # ingress, proto: UDP  - no src port, no dst port
  dynamic "ingress_security_rules" {
    iterator = rule
    for_each = [
      for x in each.value.traffic_rules["ingress"] != null ? each.value.traffic_rules["ingress"] : local.default_security_list_opt.ingress_rules :
      {
        proto : x.protocol
        dst : x.dst
        dst_type : x.dst_type
        stateless : x.stateless
        description : x.description
      } if x.protocol == "17" && x.src_port == null && x.dst_port == null
    ]

    content {
      protocol    = rule.value.proto
      source      = rule.value.src
      source_type = rule.value.src_type
      stateless   = rule.value.stateless
      description = rule.value.description
    }
  }

  # ingress, proto: UDP  - src port, no dst port
  dynamic "ingress_security_rules" {
    iterator = rule
    for_each = [
      for x in each.value.traffic_rules["ingress"] != null ? each.value.traffic_rules["ingress"] : local.default_security_list_opt.ingress_rules :
      {
        proto : x.protocol
        src : x.src
        src_type : x.src_type
        stateless : x.stateless
        src_port_min : x.src_port.min
        src_port_max : x.src_port.max
        description : x.description
      } if x.protocol == "17" && x.src_port != null && x.dst_port == null
    ]

    content {
      protocol    = rule.value.proto
      source      = rule.value.src
      source_type = rule.value.src_type
      stateless   = rule.value.stateless
      description = rule.value.description

      udp_options {
        source_port_range {
          max = rule.value.src_port_max
          min = rule.value.src_port_min
        }
      }
    }
  }

  # ingress, proto: UDP  - no src port, dst port
  dynamic "ingress_security_rules" {
    iterator = rule
    for_each = [
      for x in each.value.traffic_rules["ingress"] != null ? each.value.traffic_rules["ingress"] : local.default_security_list_opt.ingress_rules :
      {
        proto : x.protocol
        src : x.src
        src_type : x.src_type
        stateless : x.stateless
        dst_port_min : x.dst_port.min
        dst_port_max : x.dst_port.max
        description : x.description
      } if x.protocol == "17" && x.src_port == null && x.dst_port != null
    ]

    content {
      protocol    = rule.value.proto
      source      = rule.value.src
      source_type = rule.value.src_type
      stateless   = rule.value.stateless
      description = rule.value.description

      udp_options {
        max = rule.value.dst_port_max
        min = rule.value.dst_port_min
      }
    }
  }

  # ingress, proto: UDP  - src port, dst port
  dynamic "ingress_security_rules" {
    iterator = rule
    for_each = [
      for x in each.value.traffic_rules["ingress"] != null ? each.value.traffic_rules["ingress"] : local.default_security_list_opt.ingress_rules :
      {
        proto : x.protocol
        src : x.src
        src_type : x.src_type
        stateless : x.stateless
        src_port_min : x.src_port.min
        src_port_max : x.src_port.max
        dst_port_min : x.dst_port.min
        dst_port_max : x.dst_port.max
        description : x.description
      } if x.protocol == "17" && x.src_port != null && x.dst_port != null
    ]

    content {
      protocol    = rule.value.proto
      source      = rule.value.src
      source_type = rule.value.src_type
      stateless   = rule.value.stateless
      description = rule.value.description

      udp_options {
        max = rule.value.dst_port_max
        min = rule.value.dst_port_min

        source_port_range {
          max = rule.value.src_port_max
          min = rule.value.src_port_min
        }
      }
    }
  }

  # ingress, proto: ICMP  - no type, no code
  dynamic "ingress_security_rules" {
    iterator = rule
    for_each = [
      for x in each.value.traffic_rules["ingress"] != null ? each.value.traffic_rules["ingress"] : local.default_security_list_opt.ingress_rules :
      {
        proto : x.protocol
        src : x.src
        src_type : x.src_type
        stateless : x.stateless
        description : x.description
      } if x.protocol == "1" && x.icmp_type == null && x.icmp_code == null
    ]

    content {
      protocol    = rule.value.proto
      source      = rule.value.src
      source_type = rule.value.src_type
      stateless   = rule.value.stateless
      description = rule.value.description
    }
  }

  # ingress, proto: ICMP  - type, no code
  dynamic "ingress_security_rules" {
    iterator = rule
    for_each = [
      for x in each.value.traffic_rules["ingress"] != null ? each.value.traffic_rules["ingress"] : local.default_security_list_opt.ingress_rules :
      {
        proto : x.protocol
        src : x.src
        src_type : x.src_type
        stateless : x.stateless
        type : x.icmp_type
        description : x.description
      } if x.protocol == "1" && x.icmp_type != null && x.icmp_code == null
    ]

    content {
      protocol    = rule.value.proto
      source      = rule.value.src
      source_type = rule.value.src_type
      stateless   = rule.value.stateless
      description = rule.value.description

      icmp_options {
        type = rule.value.type
      }
    }
  }

  # ingress, proto: ICMP  - type, code
  dynamic "ingress_security_rules" {
    iterator = rule
    for_each = [
      for x in each.value.traffic_rules["ingress"] != null ? each.value.traffic_rules["ingress"] : local.default_security_list_opt.ingress_rules :
      {
        proto : x.protocol
        src : x.src
        src_type : x.src_type
        stateless : x.stateless
        type : x.icmp_type
        code : x.icmp_code
        description : x.description
      } if x.protocol == "1" && x.icmp_type != null && x.icmp_code != null
    ]

    content {
      protocol    = rule.value.proto
      source      = rule.value.src
      source_type = rule.value.src_type
      stateless   = rule.value.stateless
      description = rule.value.description

      icmp_options {
        type = rule.value.type
        code = rule.value.code
      }
    }
  }

  # ingress, proto: other (non-TCP, UDP or ICMP)
  dynamic "ingress_security_rules" {
    iterator = rule
    for_each = [
      for x in each.value.traffic_rules["ingress"] != null ? each.value.traffic_rules["ingress"] : local.default_security_list_opt.ingress_rules :
      {
        proto : x.protocol
        src : x.src
        src_type : x.src_type
        stateless : x.stateless
        description : x.description
      } if x.protocol != "1" && x.protocol != "6" && x.protocol != "17"
    ]

    content {
      protocol    = rule.value.proto
      source      = rule.value.src
      source_type = rule.value.src_type
      stateless   = rule.value.stateless
      description = rule.value.description
    }
  }

  # egress, proto: tcp (creates the security rule for OCI SGW)
  dynamic "egress_security_rules" {
    iterator = sgw_target
    for_each = [
      for sgw_target in each.value.route_rules :
      {
        description : "${sgw_target.target}_security_rule"
      } if sgw_target.is_create == true && sgw_target.target == "sgw"
    ]

    content {
      description      = sgw_target.value.description
      stateless        = false
      destination_type = "SERVICE_CIDR_BLOCK"
      destination      = "all-zrh-services-in-oracle-services-network" #TODO: Get value from resource
      protocol         = "6"

      tcp_options {
        min = 443
        max = 443
      }
    }
  }

  ## DNS
  #   egress, proto: tcp (dns forwarder security rule)
  dynamic "egress_security_rules" {
    iterator = dns_forwarder
    for_each = [
      for x in each.value.dns["forwarders"] :
      {
        description : x.domain_names
        destination : x.dns_server_ips
      } if x.is_create == true
    ]

    content {
      description      = "tcp_forwarder_rule_for: ${join(", ", [for s in dns_forwarder.value.description : format("%s", s)])}"
      stateless        = false
      destination_type = "CIDR_BLOCK"
      destination      = join(",", [for s in dns_forwarder.value.destination : format("%s/32", s)])
      protocol         = "6"
      tcp_options {
        min = 53
        max = 53
      }
    }
  }

  #   egress, proto: udp (dns forwarder security rule)
  dynamic "egress_security_rules" {
    iterator = dns_forwarder
    for_each = [
      for x in each.value.dns["forwarders"] :
      {
        description : x.domain_names
        destination : x.dns_server_ips
      } if x.is_create == true
    ]

    content {
      description      = "udp_forwarder_rule_for: ${join(", ", [for s in dns_forwarder.value.description : format("%s", s)])}"
      stateless        = false
      destination_type = "CIDR_BLOCK"
      destination      = join(",", [for s in dns_forwarder.value.destination : format("%s/32", s)])
      protocol         = "17"
      udp_options {
        min = 53
        max = 53
      }
    }
  }
}

#### DNS ####
resource "oci_dns_view" "these" {
  for_each = { for dns_view in local.subnets_in_vcn : "${dns_view.vcn_name}_${dns_view.dns_label}" => dns_view }

  #Required
  compartment_id = var.compartment_id
  #Optional
  scope        = "PRIVATE"
  display_name = "${each.value.vcn_name}_dns_view"
}

resource "oci_dns_resolver" "these" {
  for_each = {
    for dns_resolver in local.subnets_in_vcn : "${dns_resolver.vcn_name}_${dns_resolver.dns_label}" => dns_resolver
  }
  resolver_id = lookup(data.oci_core_vcn_dns_resolver_association.dns_resolver_association, "${each.value.vcn_name}_${each.value.dns_label}").dns_resolver_id
  scope       = "PRIVATE"
     dynamic "attached_views" {
      iterator = views
      for_each = [
        for x in [var.dns_resolver_view] : 
        {
          view_id = x
        } if x != ""
      ]
      content {
        view_id = views.value.view_id
      }
     }
  display_name = "${each.value.vcn_name}_dns_resolver"
  dynamic "rules" {
    iterator = domain_names
    for_each = [
      for x in each.value.dns["forwarders"] :
      {
        qname_cover_conditions : x.domain_names
        destination_address : x.dns_server_ips
      } if x.is_create == true
    ]

    content {
      qname_cover_conditions = domain_names.value.qname_cover_conditions
      action                 = "FORWARD"
      destination_addresses  = domain_names.value.destination_address
      source_endpoint_name   = "${each.value.vcn_name}_${each.value.dns_label}_dns_forwarder"
    }
  }
}

# Provides the DNS view
data "oci_dns_views" "these" {
  compartment_id = var.compartment_id
  scope          = "PRIVATE"
}

# Provides the VCN DNS resolver association
data "oci_core_vcn_dns_resolver_association" "dns_resolver_association" {
  for_each = { for subnet_dns_resolver in local.subnets_in_vcn : "${subnet_dns_resolver.vcn_name}_${subnet_dns_resolver.dns_label}" => subnet_dns_resolver }
  vcn_id   = lookup(oci_core_vcn.these, each.value.vcn_name).id
}

resource "oci_dns_resolver_endpoint" "dns_forwarder" {
  # Forwarder endpoint needs to be deployed before we assing any resolver rule to it. Therefor following expression needs to be true 'is_create_dns_forwarder == true && dns_forwarder.subnet_is_create == true'
  for_each = { for dns_forwarder in local.subnets_in_vcn : "${dns_forwarder.vcn_name}_${dns_forwarder.dns_label}-dns_forwarder" => dns_forwarder if dns_forwarder.is_create_dns_forwarder == true && dns_forwarder.subnet_is_create == true }

  #Required
  resolver_id   = lookup(oci_dns_resolver.these, "${each.value.vcn_name}_${each.value.dns_label}").id
  scope         = "PRIVATE"
  is_forwarding = true
  is_listening  = false
  name          = "${each.value.vcn_name}_${each.value.dns_label}_dns_forwarder"
  subnet_id     = lookup(oci_core_subnet.these, "${each.value.vcn_name}_${each.value.dns_label}").id
  #Optional
  forwarding_address = cidrhost(lookup(oci_core_subnet.these, "${each.value.vcn_name}_${each.value.dns_label}").cidr_block, "10")

}

resource "oci_dns_resolver_endpoint" "dns_listener" {
  for_each = { for dns_listener in local.subnets_in_vcn : "${dns_listener.vcn_name}_${dns_listener.dns_label}-dns_listener" => dns_listener if dns_listener.dns.listener.is_create == true }

  #Required
  resolver_id   = lookup(oci_dns_resolver.these, "${each.value.vcn_name}_${each.value.dns_label}").id
  scope         = "PRIVATE"
  is_forwarding = false
  is_listening  = true
  name          = "${each.value.vcn_name}_${each.value.dns_label}_dns_listener"
  subnet_id     = lookup(oci_core_subnet.these, "${each.value.vcn_name}_${each.value.dns_label}").id
  #Optional
  listening_address = cidrhost(lookup(oci_core_subnet.these, "${each.value.vcn_name}_${each.value.dns_label}").cidr_block, "11")
}
