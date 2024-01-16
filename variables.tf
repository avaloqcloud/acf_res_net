variable "compartment_id" {
  description = "Compartment where to deploy the resources to"
  type        = string
}

variable "dns_resolver_view" {
  description = "Attache DNS view to resolver"
  type        = string
}

variable "defined_tags" {
  type        = map(string)
  default     = {
    "CostTracking.avq-opr-resident"= "DEV",
    "CostTracking.avq-gov-costaccount-build"= "DEV",
    "CostTracking.avq-gov-costaccount-run"= "DEV",
    "CostTracking.avq-gov-purchase-order"= "DEV",
    "CostTracking.avq-opr-lfc-status"= "build",
    "CostTracking.avq-gov-legal-entity"= "DEV",
    "CostTracking.avq-opr-product"= "network",
    "CostTracking.avq-opr-stage"= "dev",
    "CostTracking.avq-opr-environment"= "1",
  }
  description = "Specify the tag for the OCI resources"
}

variable "vcns" {
  type = list(object({
    vcn_name     = string,
    display_name = string,
    dns_label    = string,
    cidr_blocks  = list(string),
    internet_gateway = object({
      is_create = bool,
      enabled   = bool
    }),
    nat_gateway = object({
      is_create     = bool,
      block_traffic = bool
    }),
    service_gateway = object({
      is_create = bool
    }),
    dynamic_routing_gateway = object({
      drg_id    = string,
      is_attach = bool
    }),
    local_peering_gateway = object({
      is_create = bool,
      peer_id   = string
    }),
    subnets = list(object({
      cidr_block                 = string,
      display_name               = string,
      dns_label                  = string,
      is_create                  = bool,
      prohibit_internet_ingress  = bool,
      prohibit_public_ip_on_vnic = bool,
      is_create_dns_forwarder = bool,
      dns = object({
        forwarders = list(object({
          domain_names   = list(string),
          dns_server_ips = list(string),
          is_create      = bool
        })),
        listener = object({
          is_create = bool
        }),
      }),
      route_rules = list(object({
        destination      = string,
        is_create        = bool,
        destination_type = string,
        description      = string,
        target           = string,
      })),
      traffic_rules = object({
        ingress = list(object({
          description = string,
          protocol    = string,
          stateless   = bool,
          src         = string,
          src_type    = string,
          src_port = object({
            min = number,
            max = number
          }),
          dst_port = object({
            min = number,
            max = number
          }),
          icmp_type = number,
          icmp_code = number
        })),
        egress = list(object({
          description = string,
          protocol    = string,
          stateless   = bool,
          dst         = string,
          dst_type    = string,
          src_port = object({
            min = number,
            max = number
          }),
          dst_port = object({
            min = number,
            max = number
          }),
          icmp_type = number,
          icmp_code = number
        })),
      }),
    }))
  }))
}
