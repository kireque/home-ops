# locals {
#   switch_core_1_name       = "Switch - Core 1"
#   switch_core_2_name       = "Switch - Core 2"
#   switch_media_name        = "Switch - Media"
#   ap_attic_office_name     = "AP - Attic Office"
#   ap_hallway_name          = "AP - Hallway"
#   ap_upstairs_hallway_name = "AP - Upstairs Hallway"
#   ap_garage_name           = "AP - Garage"
# }

# resource "unifi_device" "switch_media" {
#   mac  = "f4:e2:c6:51:9a:04"
#   name = local.switch_media_name
#   site = unifi_site.default.name

#   port_override {
#     number          = 1
#     name            = local.switch_core_1_name
#     port_profile_id = data.unifi_port_profile.all.id
#   }
#   port_override {
#     number          = 2
#     name            = "laptop"
#     port_profile_id = unifi_port_profile.iot_poe_disabled.id
#   }
#   port_override {
#     number          = 3
#     name            = "talos_01"
#     port_profile_id = unifi_port_profile.iot_poe_disabled.id
#   }
#   port_override {
#     number          = 4
#     name            = "talos_02"
#     port_profile_id = data.unifi_port_profile.all.id
#   }
#   port_override {
#     number          = 5
#     name            = "talos_03"
#     port_profile_id = data.unifi_port_profile.all.id
#   }
# }

# # resource "unifi_device" "ap_hallway" {
# #   mac  = "44:d9:e7:fc:21:f9"
# #   name = local.ap_hallway_name
# #   site = unifi_site.default.name
# # }

# # resource "unifi_device" "ap_upstairs_hallway" {
# #   mac  = "e0:63:da:ac:d4:3e"
# #   name = local.ap_upstairs_hallway_name
# #   site = unifi_site.default.name
# # }

# # resource "unifi_device" "ap_garage" {
# #   mac  = "fc:ec:da:b6:27:87"
# #   name = local.ap_garage_name
# #   site = unifi_site.default.name
# # }

# resource "unifi_device" "ap_attic_office" {
#   mac  = "60:22:32:33:a3:08"
#   name = local.ap_attic_office_name
#   site = unifi_site.default.name
# }
