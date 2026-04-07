# F5 Distributed Cloud API Resource Index

Complete index of 149 CRUD-capable resources derived from the official OpenAPI specifications.
All paths are relative to the `F5XC_API_URL` base URL.

## How to use

```bash
# List all resources of a type
curl -s "${F5XC_API_URL}<list_path>" -H "Authorization: APIToken ${F5XC_API_TOKEN}" | jq .

# Get a specific resource
curl -s "${F5XC_API_URL}<get_path>" -H "Authorization: APIToken ${F5XC_API_TOKEN}" | jq .
# Replace {namespace} with your namespace and {name} with the resource name
```

## API Security

| Resource | List (GET) | Get/Delete | Create (POST) | Replace (PUT) |
|----------|-----------|------------|---------------|---------------|
| `api_sec.api_crawler` | `.../{namespace}/api_crawlers` | `.../{namespace}/api_crawlers/{name}` | `.../{metadata.namespace}/api_crawlers` | `.../{metadata.namespace}/api_crawlers/{metadata.name}` |
| `api_sec.api_discovery` | `.../{namespace}/api_discoverys` | `.../{namespace}/api_discoverys/{name}` | `.../{metadata.namespace}/api_discoverys` | `.../{metadata.namespace}/api_discoverys/{metadata.name}` |
| `api_sec.api_testing` | `.../{namespace}/api_testings` | `.../{namespace}/api_testings/{name}` | `.../{metadata.namespace}/api_testings` | `.../{metadata.namespace}/api_testings/{metadata.name}` |
| `api_sec.code_base_integration` | `.../{namespace}/code_base_integrations` | `.../{namespace}/code_base_integrations/{name}` | `.../{metadata.namespace}/code_base_integrations` | `.../{metadata.namespace}/code_base_integrations/{metadata.name}` |
| `api_sec.rule_suggestion` | `—` | `—` | `.../{namespace}/api_sec/rule_suggestion/rate_limit` | `—` |
| `views.api_definition` | `.../{namespace}/api_definitions_without_shared` | `.../{namespace}/api_definitions/{name}/loadbalancers` | `.../{metadata.namespace}/api_definitions` | `.../{metadata.namespace}/api_definitions/{metadata.name}` |
| `views.app_api_group` | `.../{namespace}/app_api_groups` | `.../{namespace}/app_api_groups/{name}` | `.../{metadata.namespace}/app_api_groups` | `.../{metadata.namespace}/app_api_groups/{metadata.name}` |

## Access Control & Certificates

| Resource | List (GET) | Get/Delete | Create (POST) | Replace (PUT) |
|----------|-----------|------------|---------------|---------------|
| `authentication` | `.../{namespace}/authentications` | `.../{namespace}/authentications/{name}` | `.../{metadata.namespace}/authentications` | `.../{metadata.namespace}/authentications/{metadata.name}` |
| `authorization_server` | `.../{namespace}/authorization_servers` | `.../{namespace}/authorization_servers/{name}` | `.../{metadata.namespace}/authorization_servers` | `.../{metadata.namespace}/authorization_servers/{metadata.name}` |
| `certificate` | `.../{namespace}/certificates` | `.../{namespace}/certificates/{name}` | `.../{metadata.namespace}/certificates` | `.../{metadata.namespace}/certificates/{metadata.name}` |
| `certificate_chain` | `.../{namespace}/certificate_chains` | `.../{namespace}/certificate_chains/{name}` | `.../{metadata.namespace}/certificate_chains` | `.../{metadata.namespace}/certificate_chains/{metadata.name}` |
| `crl` | `.../{namespace}/crls` | `.../{namespace}/crls/{name}` | `.../{metadata.namespace}/crls` | `.../{metadata.namespace}/crls/{metadata.name}` |
| `namespace` | `.../{namespace}/fast_acls_for_internet_vips` | `—` | `.../{namespace}/fast_acls_for_internet_vips` | `—` |
| `secret_management_access` | `.../{namespace}/secret_management_accesss` | `.../{namespace}/secret_management_accesss/{name}` | `.../{metadata.namespace}/secret_management_accesss` | `.../{metadata.namespace}/secret_management_accesss/{metadata.name}` |
| `tenant` | `/api/config/tenants/{tenant}/summary` | `—` | `—` | `—` |
| `trusted_ca_list` | `.../{namespace}/trusted_ca_lists` | `.../{namespace}/trusted_ca_lists/{name}` | `.../{metadata.namespace}/trusted_ca_lists` | `.../{metadata.namespace}/trusted_ca_lists/{metadata.name}` |
| `views.tenant_configuration` | `.../{namespace}/tenant_configurations` | `.../{namespace}/tenant_configurations/{name}` | `.../{metadata.namespace}/tenant_configurations` | `.../{metadata.namespace}/tenant_configurations/{metadata.name}` |

## BIG-IP

| Resource | List (GET) | Get/Delete | Create (POST) | Replace (PUT) |
|----------|-----------|------------|---------------|---------------|
| `bigcne.application_profiles` | `.../{namespace}/application_profiless` | `.../{namespace}/application_profiless/{name}` | `.../{metadata.namespace}/application_profiless` | `.../{metadata.namespace}/application_profiless/{metadata.name}` |
| `bigcne.data_group` | `.../{namespace}/data_groups` | `.../{namespace}/data_groups/{name}` | `.../{metadata.namespace}/data_groups` | `.../{metadata.namespace}/data_groups/{metadata.name}` |
| `bigcne.irule` | `.../{namespace}/irules` | `.../{namespace}/irules/{name}` | `.../{metadata.namespace}/irules` | `.../{metadata.namespace}/irules/{metadata.name}` |
| `views.bigip_http_proxy` | `.../{namespace}/bigip_http_proxys` | `.../{namespace}/bigip_http_proxys/{name}` | `.../{metadata.namespace}/bigip_http_proxys` | `.../{metadata.namespace}/bigip_http_proxys/{metadata.name}` |
| `views.bigip_virtual_server` | `.../{namespace}/bigip_virtual_servers` | `.../{namespace}/bigip_virtual_servers/{name}` | `.../{namespace}/bigip_virtual_servers/get_security_config` | `.../{metadata.namespace}/bigip_virtual_servers/{metadata.name}` |

## CDN

| Resource | List (GET) | Get/Delete | Create (POST) | Replace (PUT) |
|----------|-----------|------------|---------------|---------------|
| `cdn_cache_rule` | `.../{namespace}/cdn_cache_rules` | `.../{namespace}/cdn_cache_rules/{name}` | `.../{metadata.namespace}/cdn_cache_rules` | `.../{metadata.namespace}/cdn_cache_rules/{metadata.name}` |
| `cdn_purge_command` | `.../{namespace}/cdn_purge_commands` | `.../{namespace}/cdn_purge_commands/{name}` | `.../{metadata.namespace}/cdn_purge_commands` | `—` |

## Cloud Sites & Infrastructure

| Resource | List (GET) | Get/Delete | Create (POST) | Replace (PUT) |
|----------|-----------|------------|---------------|---------------|
| `certified_hardware` | `.../{namespace}/certified_hardwares` | `.../{namespace}/certified_hardwares/{name}` | `—` | `—` |
| `cloud_connect` | `.../{namespace}/cloud_connects` | `.../{namespace}/cloud_connects/{name}` | `.../{metadata.namespace}/cloud_connects` | `.../{metadata.namespace}/cloud_connects/{metadata.name}` |
| `cloud_credentials` | `.../{namespace}/cloud_credentialss` | `.../{namespace}/cloud_credentialss/{name}` | `.../{metadata.namespace}/cloud_credentialss` | `.../{metadata.namespace}/cloud_credentialss/{metadata.name}` |
| `cloud_elastic_ip` | `.../{namespace}/cloud_elastic_ips` | `.../{namespace}/cloud_elastic_ips/{name}` | `.../{metadata.namespace}/cloud_elastic_ips` | `.../{metadata.namespace}/cloud_elastic_ips/{metadata.name}` |
| `cloud_link` | `.../{namespace}/cloud_links` | `.../{namespace}/cloud_links/{name}` | `.../{metadata.namespace}/cloud_links` | `.../{metadata.namespace}/cloud_links/{metadata.name}` |
| `cloud_region` | `.../{namespace}/cloud_regions` | `.../{namespace}/cloud_regions/{name}` | `—` | `.../{metadata.namespace}/cloud_regions/{metadata.name}` |
| `fleet` | `.../{namespace}/fleets` | `.../{namespace}/fleets/{name}` | `.../{metadata.namespace}/fleets` | `.../{metadata.namespace}/fleets/{metadata.name}` |
| `nfv_service` | `.../{namespace}/nfv_services` | `.../{namespace}/nfv_services/{name}` | `.../{metadata.namespace}/nfv_services` | `.../{metadata.namespace}/nfv_services/{metadata.name}` |
| `site` | `.../{namespace}/sites/{site}/segments` | `.../{namespace}/sites/{name}/local-kubeconfigs` | `—` | `.../{metadata.namespace}/sites/{metadata.name}` |
| `site_mesh_group` | `.../{namespace}/site_mesh_groups` | `.../{namespace}/site_mesh_groups/{name}` | `.../{metadata.namespace}/site_mesh_groups` | `.../{metadata.namespace}/site_mesh_groups/{metadata.name}` |
| `views.aws_tgw_site` | `.../{namespace}/aws_tgw_sites` | `.../{namespace}/aws_tgw_sites/{name}` | `.../{metadata.namespace}/aws_tgw_sites` | `.../{metadata.namespace}/aws_tgw_sites/{metadata.name}` |
| `views.aws_vpc_site` | `.../{namespace}/aws_vpc_sites` | `.../{namespace}/aws_vpc_sites/{name}` | `.../{metadata.namespace}/aws_vpc_sites` | `.../{metadata.namespace}/aws_vpc_sites/{metadata.name}` |
| `views.azure_vnet_site` | `.../{namespace}/azure_vnet_sites` | `.../{namespace}/azure_vnet_sites/{name}` | `.../{metadata.namespace}/azure_vnet_sites` | `.../{metadata.namespace}/azure_vnet_sites/{metadata.name}` |
| `views.gcp_vpc_site` | `.../{namespace}/gcp_vpc_sites` | `.../{namespace}/gcp_vpc_sites/{name}` | `.../{metadata.namespace}/gcp_vpc_sites` | `.../{metadata.namespace}/gcp_vpc_sites/{metadata.name}` |
| `views.securemesh_site` | `.../{namespace}/securemesh_sites` | `.../{namespace}/securemesh_sites/{name}` | `.../{metadata.namespace}/securemesh_sites` | `.../{metadata.namespace}/securemesh_sites/{metadata.name}` |
| `views.securemesh_site_v2` | `.../{namespace}/securemesh_site_v2s` | `.../{namespace}/securemesh_site_v2s/{name}` | `.../{metadata.namespace}/securemesh_site_v2s` | `.../{metadata.namespace}/securemesh_site_v2s/{metadata.name}` |
| `views.voltstack_site` | `.../{namespace}/voltstack_sites` | `.../{namespace}/voltstack_sites/{name}` | `.../{metadata.namespace}/voltstack_sites` | `.../{metadata.namespace}/voltstack_sites/{metadata.name}` |
| `virtual_site` | `.../{namespace}/virtual_sites` | `.../{namespace}/virtual_sites/{name}/selectees` | `.../{metadata.namespace}/virtual_sites` | `.../{metadata.namespace}/virtual_sites/{metadata.name}` |

## DNS

| Resource | List (GET) | Get/Delete | Create (POST) | Replace (PUT) |
|----------|-----------|------------|---------------|---------------|
| `dns_compliance_checks` | `.../{namespace}/dns_compliance_checkss` | `.../{namespace}/dns_compliance_checkss/{name}` | `.../{metadata.namespace}/dns_compliance_checkss` | `.../{metadata.namespace}/dns_compliance_checkss/{metadata.name}` |
| `dns_domain` | `.../{namespace}/dns_domains` | `.../{namespace}/dns_domains/{name}` | `.../{metadata.namespace}/dns_domains` | `.../{metadata.namespace}/dns_domains/{metadata.name}` |
| `dns_lb_health_check` | `/api/config/dns/namespaces/{namespace}/dns_lb_health_checks` | `/api/config/dns/namespaces/{namespace}/dns_lb_health_checks/{name}` | `/api/config/dns/namespaces/{metadata.namespace}/dns_lb_health_checks` | `/api/config/dns/namespaces/{metadata.namespace}/dns_lb_health_checks/{metadata.name}` |
| `dns_lb_pool` | `/api/config/dns/namespaces/{namespace}/dns_lb_pools` | `/api/config/dns/namespaces/{namespace}/dns_lb_pools/{name}` | `/api/config/dns/namespaces/{metadata.namespace}/dns_lb_pools` | `/api/config/dns/namespaces/{metadata.namespace}/dns_lb_pools/{metadata.name}` |
| `dns_load_balancer` | `/api/config/dns/namespaces/{namespace}/dns_load_balancers` | `/api/config/dns/namespaces/{namespace}/dns_load_balancers/{name}` | `/api/config/dns/namespaces/{metadata.namespace}/dns_load_balancers` | `/api/config/dns/namespaces/{metadata.namespace}/dns_load_balancers/{metadata.name}` |
| `dns_proxy` | `.../{namespace}/dns_proxys` | `.../{namespace}/dns_proxys/{name}` | `.../{metadata.namespace}/dns_proxys` | `.../{metadata.namespace}/dns_proxys/{metadata.name}` |
| `dns_zone` | `/api/config/dns/namespaces/{namespace}/dns_zones` | `/api/config/dns/namespaces/{namespace}/dns_zones/{name}` | `/api/config/dns/namespaces/{metadata.namespace}/dns_zones` | `/api/config/dns/namespaces/{metadata.namespace}/dns_zones/{metadata.name}` |
| `dns_zone.rrset` | `/api/config/dns/namespaces/system/dns_zones/{dns_zone_name}/rrsets/{group_name}/{record_name}/{type}` | `—` | `/api/config/dns/namespaces/system/dns_zones/{dns_zone_name}/rrsets/{group_name}` | `—` |
| `dns_zone.subscription` | `—` | `—` | `/api/config/dns/namespaces/system/dns_management/addon/unsubscribe` | `—` |
| `geo_location_set` | `/api/config/dns/namespaces/{namespace}/geo_location_sets` | `/api/config/dns/namespaces/{namespace}/geo_location_sets/{name}` | `/api/config/dns/namespaces/{metadata.namespace}/geo_location_sets` | `/api/config/dns/namespaces/{metadata.namespace}/geo_location_sets/{metadata.name}` |

## Kubernetes & Workloads

| Resource | List (GET) | Get/Delete | Create (POST) | Replace (PUT) |
|----------|-----------|------------|---------------|---------------|
| `container_registry` | `.../{namespace}/container_registrys` | `.../{namespace}/container_registrys/{name}` | `.../{metadata.namespace}/container_registrys` | `.../{metadata.namespace}/container_registrys/{metadata.name}` |
| `discovery` | `.../{namespace}/discoverys` | `.../{namespace}/discoverys/{name}` | `.../{metadata.namespace}/discoverys` | `.../{metadata.namespace}/discoverys/{metadata.name}` |
| `endpoint` | `.../{namespace}/endpoints` | `.../{namespace}/endpoints/{name}` | `.../{metadata.namespace}/endpoints` | `.../{metadata.namespace}/endpoints/{metadata.name}` |
| `k8s_cluster` | `.../{namespace}/k8s_clusters` | `.../{namespace}/k8s_clusters/{name}` | `.../{metadata.namespace}/k8s_clusters` | `.../{metadata.namespace}/k8s_clusters/{metadata.name}` |
| `k8s_cluster_role` | `.../{namespace}/k8s_cluster_roles` | `.../{namespace}/k8s_cluster_roles/{name}` | `.../{metadata.namespace}/k8s_cluster_roles` | `.../{metadata.namespace}/k8s_cluster_roles/{metadata.name}` |
| `k8s_cluster_role_binding` | `.../{namespace}/k8s_cluster_role_bindings` | `.../{namespace}/k8s_cluster_role_bindings/{name}` | `.../{metadata.namespace}/k8s_cluster_role_bindings` | `.../{metadata.namespace}/k8s_cluster_role_bindings/{metadata.name}` |
| `k8s_pod_security_admission` | `.../{namespace}/k8s_pod_security_admissions` | `.../{namespace}/k8s_pod_security_admissions/{name}` | `.../{metadata.namespace}/k8s_pod_security_admissions` | `.../{metadata.namespace}/k8s_pod_security_admissions/{metadata.name}` |
| `k8s_pod_security_policy` | `.../{namespace}/k8s_pod_security_policys` | `.../{namespace}/k8s_pod_security_policys/{name}` | `.../{metadata.namespace}/k8s_pod_security_policys` | `.../{metadata.namespace}/k8s_pod_security_policys/{metadata.name}` |
| `nginx.one.nginx_service_discovery` | `.../{namespace}/nginx_service_discoverys` | `.../{namespace}/nginx_service_discoverys/{name}` | `.../{metadata.namespace}/nginx_service_discoverys` | `.../{metadata.namespace}/nginx_service_discoverys/{metadata.name}` |
| `views.workload` | `.../{namespace}/workloads` | `.../{namespace}/workloads/{name}` | `.../{metadata.namespace}/workloads` | `.../{metadata.namespace}/workloads/{metadata.name}` |
| `virtual_k8s` | `.../{namespace}/virtual_k8ss` | `.../{namespace}/virtual_k8ss/{name}` | `.../{metadata.namespace}/virtual_k8ss` | `.../{metadata.namespace}/virtual_k8ss/{metadata.name}` |
| `workload_flavor` | `.../{namespace}/workload_flavors` | `.../{namespace}/workload_flavors/{name}` | `.../{metadata.namespace}/workload_flavors` | `.../{metadata.namespace}/workload_flavors/{metadata.name}` |

## Load Balancing

| Resource | List (GET) | Get/Delete | Create (POST) | Replace (PUT) |
|----------|-----------|------------|---------------|---------------|
| `healthcheck` | `.../{namespace}/healthchecks` | `.../{namespace}/healthchecks/{name}` | `.../{metadata.namespace}/healthchecks` | `.../{metadata.namespace}/healthchecks/{metadata.name}` |
| `views.cdn_loadbalancer` | `.../{namespace}/cdn_loadbalancers` | `.../{namespace}/cdn_loadbalancers/{name}/dos_automitigation_rules` | `.../{namespace}/cdn_loadbalancers/get_security_config` | `.../{metadata.namespace}/cdn_loadbalancers/{metadata.name}` |
| `views.http_loadbalancer` | `.../{namespace}/http_loadbalancers` | `.../{namespace}/http_loadbalancers/{name}/get-dns-info` | `.../{namespace}/http_loadbalancers/get_security_config` | `.../{metadata.namespace}/http_loadbalancers/{metadata.name}` |
| `views.origin_pool` | `.../{namespace}/origin_pools` | `.../{namespace}/origin_pools/{name}` | `.../{metadata.namespace}/origin_pools` | `.../{metadata.namespace}/origin_pools/{metadata.name}` |
| `views.tcp_loadbalancer` | `.../{namespace}/tcp_loadbalancers` | `.../{namespace}/tcp_loadbalancers/{name}/get-dns-info` | `.../{metadata.namespace}/tcp_loadbalancers` | `.../{metadata.namespace}/tcp_loadbalancers/{metadata.name}` |
| `views.udp_loadbalancer` | `.../{namespace}/udp_loadbalancers` | `.../{namespace}/udp_loadbalancers/{name}/get-dns-info` | `.../{metadata.namespace}/udp_loadbalancers` | `.../{metadata.namespace}/udp_loadbalancers/{metadata.name}` |

## Monitoring & Observability

| Resource | List (GET) | Get/Delete | Create (POST) | Replace (PUT) |
|----------|-----------|------------|---------------|---------------|
| `alert_policy` | `.../{namespace}/alert_policys` | `.../{namespace}/alert_policys/{name}` | `.../{metadata.namespace}/alert_policys` | `.../{metadata.namespace}/alert_policys/{metadata.name}` |
| `alert_receiver` | `.../{namespace}/alert_receivers` | `.../{namespace}/alert_receivers/{name}` | `.../{metadata.namespace}/alert_receivers` | `.../{metadata.namespace}/alert_receivers/{metadata.name}` |
| `flow` | `.../system/flow-collection/addon/subscription-status` | `—` | `.../system/flow-collection/addon/unsubscribe` | `—` |
| `flow_anomaly` | `.../{namespace}/flow_anomalys` | `.../{namespace}/flow_anomalys/{name}` | `—` | `—` |
| `global_log_receiver` | `.../{namespace}/global_log_receivers` | `.../{namespace}/global_log_receivers/{name}` | `.../{metadata.namespace}/global_log_receivers` | `.../{metadata.namespace}/global_log_receivers/{metadata.name}` |
| `log_receiver` | `.../{namespace}/log_receivers` | `.../{namespace}/log_receivers/{name}` | `.../{metadata.namespace}/log_receivers` | `.../{metadata.namespace}/log_receivers/{metadata.name}` |
| `module_management` | `.../{namespace}/module_management/settings` | `—` | `—` | `—` |

## NGINX One

| Resource | List (GET) | Get/Delete | Create (POST) | Replace (PUT) |
|----------|-----------|------------|---------------|---------------|
| `nginx.one.nginx_csg` | `.../{namespace}/nginx_csgs` | `.../{namespace}/nginx_csgs/{name}` | `—` | `—` |
| `nginx.one.nginx_instance` | `.../{namespace}/nginx_instances` | `.../{namespace}/nginx_instances/{name}` | `—` | `—` |
| `nginx.one.nginx_server` | `.../{namespace}/nginx_servers` | `.../{namespace}/nginx_servers/{name}` | `.../{namespace}/nginx_dataplane_servers` | `—` |

## Networking

| Resource | List (GET) | Get/Delete | Create (POST) | Replace (PUT) |
|----------|-----------|------------|---------------|---------------|
| `bgp` | `.../{namespace}/bgpstatus/{view_name}` | `.../{namespace}/bgps/{name}` | `.../{metadata.namespace}/bgps` | `.../{metadata.namespace}/bgps/{metadata.name}` |
| `bgp_asn_set` | `.../{namespace}/bgp_asn_sets` | `.../{namespace}/bgp_asn_sets/{name}` | `.../{metadata.namespace}/bgp_asn_sets` | `.../{metadata.namespace}/bgp_asn_sets/{metadata.name}` |
| `bgp_routing_policy` | `.../{namespace}/bgp_routing_policys` | `.../{namespace}/bgp_routing_policys/{name}` | `.../{metadata.namespace}/bgp_routing_policys` | `.../{metadata.namespace}/bgp_routing_policys/{metadata.name}` |
| `enhanced_firewall_policy` | `.../{namespace}/enhanced_firewall_policys` | `.../{namespace}/enhanced_firewall_policys/{name}` | `.../{metadata.namespace}/enhanced_firewall_policys` | `.../{metadata.namespace}/enhanced_firewall_policys/{metadata.name}` |
| `forwarding_class` | `.../{namespace}/forwarding_classs` | `.../{namespace}/forwarding_classs/{name}` | `.../{metadata.namespace}/forwarding_classs` | `.../{metadata.namespace}/forwarding_classs/{metadata.name}` |
| `ike1` | `.../{namespace}/ike1s` | `.../{namespace}/ike1s/{name}` | `.../{metadata.namespace}/ike1s` | `.../{metadata.namespace}/ike1s/{metadata.name}` |
| `ike2` | `.../{namespace}/ike2s` | `.../{namespace}/ike2s/{name}` | `.../{metadata.namespace}/ike2s` | `.../{metadata.namespace}/ike2s/{metadata.name}` |
| `ip_prefix_set` | `.../{namespace}/ip_prefix_sets` | `.../{namespace}/ip_prefix_sets/{name}` | `.../{metadata.namespace}/ip_prefix_sets` | `.../{metadata.namespace}/ip_prefix_sets/{metadata.name}` |
| `nat_policy` | `.../{namespace}/nat_policys` | `.../{namespace}/nat_policys/{name}` | `.../{metadata.namespace}/nat_policys` | `.../{metadata.namespace}/nat_policys/{metadata.name}` |
| `network_connector` | `.../{namespace}/network_connectors` | `.../{namespace}/network_connectors/{name}` | `.../{metadata.namespace}/network_connectors` | `.../{metadata.namespace}/network_connectors/{metadata.name}` |
| `network_firewall` | `.../{namespace}/network_firewalls` | `.../{namespace}/network_firewalls/{name}` | `.../{metadata.namespace}/network_firewalls` | `.../{metadata.namespace}/network_firewalls/{metadata.name}` |
| `network_interface` | `.../{namespace}/network_interfaces` | `.../{namespace}/network_interfaces/{name}` | `.../{metadata.namespace}/network_interfaces` | `.../{metadata.namespace}/network_interfaces/{metadata.name}` |
| `network_policy` | `.../{namespace}/network_policys` | `.../{namespace}/network_policys/{name}` | `.../{metadata.namespace}/network_policys` | `.../{metadata.namespace}/network_policys/{metadata.name}` |
| `network_policy_rule` | `.../{namespace}/network_policy_rules` | `.../{namespace}/network_policy_rules/{name}` | `.../{metadata.namespace}/network_policy_rules` | `.../{metadata.namespace}/network_policy_rules/{metadata.name}` |
| `network_policy_set` | `.../{namespace}/network_policy_sets` | `.../{namespace}/network_policy_sets/{name}` | `—` | `—` |
| `policer` | `.../{namespace}/policers` | `.../{namespace}/policers/{name}` | `.../{metadata.namespace}/policers` | `.../{metadata.namespace}/policers/{metadata.name}` |
| `protocol_policer` | `.../{namespace}/protocol_policers` | `.../{namespace}/protocol_policers/{name}` | `.../{metadata.namespace}/protocol_policers` | `.../{metadata.namespace}/protocol_policers/{metadata.name}` |
| `route` | `.../{namespace}/routes` | `.../{namespace}/routes/{name}` | `.../{metadata.namespace}/routes` | `.../{metadata.namespace}/routes/{metadata.name}` |
| `segment` | `.../{namespace}/segments` | `.../{namespace}/segments/{name}` | `.../{metadata.namespace}/segments` | `.../{metadata.namespace}/segments/{metadata.name}` |
| `segment_connection` | `.../{namespace}/segment_connections` | `.../{namespace}/segment_connections/{name}` | `—` | `.../{metadata.namespace}/segment_connections/{metadata.name}` |
| `srv6_network_slice` | `.../{namespace}/srv6_network_slices` | `.../{namespace}/srv6_network_slices/{name}` | `.../{metadata.namespace}/srv6_network_slices` | `.../{metadata.namespace}/srv6_network_slices/{metadata.name}` |
| `subnet` | `.../{namespace}/subnets` | `.../{namespace}/subnets/{name}` | `.../{metadata.namespace}/subnets` | `.../{metadata.namespace}/subnets/{metadata.name}` |
| `tunnel` | `.../{namespace}/tunnels` | `.../{namespace}/tunnels/{name}` | `.../{metadata.namespace}/tunnels` | `.../{metadata.namespace}/tunnels/{metadata.name}` |
| `views.ike_phase1_profile` | `.../{namespace}/ike_phase1_profiles` | `.../{namespace}/ike_phase1_profiles/{name}` | `.../{metadata.namespace}/ike_phase1_profiles` | `.../{metadata.namespace}/ike_phase1_profiles/{metadata.name}` |
| `views.ike_phase2_profile` | `.../{namespace}/ike_phase2_profiles` | `.../{namespace}/ike_phase2_profiles/{name}` | `.../{metadata.namespace}/ike_phase2_profiles` | `.../{metadata.namespace}/ike_phase2_profiles/{metadata.name}` |
| `views.network_policy_view` | `.../{namespace}/network_policy_views` | `.../{namespace}/network_policy_views/{name}` | `.../{metadata.namespace}/network_policy_views` | `.../{metadata.namespace}/network_policy_views/{metadata.name}` |
| `views.policy_based_routing` | `.../{namespace}/policy_based_routings` | `.../{namespace}/policy_based_routings/{name}` | `.../{metadata.namespace}/policy_based_routings` | `.../{metadata.namespace}/policy_based_routings/{metadata.name}` |
| `virtual_network` | `.../{namespace}/virtual_networks` | `.../{namespace}/virtual_networks/{name}` | `.../{metadata.namespace}/virtual_networks` | `.../{metadata.namespace}/virtual_networks/{metadata.name}` |

## Other

| Resource | List (GET) | Get/Delete | Create (POST) | Replace (PUT) |
|----------|-----------|------------|---------------|---------------|
| `address_allocator` | `.../{namespace}/address_allocators` | `.../{namespace}/address_allocators/{name}` | `.../{metadata.namespace}/address_allocators` | `—` |
| `advertise_policy` | `.../{namespace}/advertise_policys` | `.../{namespace}/advertise_policys/{name}` | `.../{metadata.namespace}/advertise_policys` | `.../{metadata.namespace}/advertise_policys/{metadata.name}` |
| `app_setting` | `.../{namespace}/app_settings` | `.../{namespace}/app_settings/{name}` | `.../{metadata.namespace}/app_settings` | `.../{metadata.namespace}/app_settings/{metadata.name}` |
| `app_type` | `.../{namespace}/app_types` | `.../{namespace}/app_types/{name}` | `.../{metadata.namespace}/app_types` | `.../{metadata.namespace}/app_types/{metadata.name}` |
| `cluster` | `.../{namespace}/clusters` | `.../{namespace}/clusters/{name}` | `.../{metadata.namespace}/clusters` | `.../{metadata.namespace}/clusters/{metadata.name}` |
| `cminstance` | `.../{namespace}/cminstances` | `.../{namespace}/cminstances/{name}` | `.../{metadata.namespace}/cminstances` | `.../{metadata.namespace}/cminstances/{metadata.name}` |
| `data_privacy.geo_config` | `—` | `.../{namespace}/geo_configs/{name}` | `—` | `—` |
| `data_privacy.lma_region` | `.../{namespace}/lma_regions` | `.../{namespace}/lma_regions/{name}` | `—` | `—` |
| `data_type` | `.../{namespace}/data_types` | `.../{namespace}/data_types/{name}` | `.../{metadata.namespace}/data_types` | `.../{metadata.namespace}/data_types/{metadata.name}` |
| `dc_cluster_group` | `.../{namespace}/dc_cluster_groups` | `.../{namespace}/dc_cluster_groups/{name}` | `.../{metadata.namespace}/dc_cluster_groups` | `.../{metadata.namespace}/dc_cluster_groups/{metadata.name}` |
| `filter_set` | `.../{namespace}/filter_sets` | `.../{namespace}/filter_sets/{name}` | `.../{namespace}/filter_sets/find` | `.../{metadata.namespace}/filter_sets/{metadata.name}` |
| `implicit_label` | `.../system/implicit_labels` | `—` | `—` | `—` |
| `known_label` | `.../{namespace}/known_labels` | `—` | `.../{namespace}/known_label/delete` | `—` |
| `known_label_key` | `.../{namespace}/known_label_keys` | `—` | `.../{namespace}/known_label_key/delete` | `—` |
| `malware_protection.subscription` | `—` | `—` | `.../system/malware_protection/addon/unsubscribe` | `—` |
| `public_ip` | `.../{namespace}/public_ips` | `.../{namespace}/public_ips/{name}` | `—` | `.../{metadata.namespace}/public_ips/{metadata.name}` |
| `usb_policy` | `.../{namespace}/usb_policys` | `.../{namespace}/usb_policys/{name}` | `.../{metadata.namespace}/usb_policys` | `.../{metadata.namespace}/usb_policys/{metadata.name}` |
| `views.external_connector` | `.../{namespace}/external_connectors` | `.../{namespace}/external_connectors/{name}` | `.../{metadata.namespace}/external_connectors` | `.../{metadata.namespace}/external_connectors/{metadata.name}` |
| `views.forward_proxy_policy` | `.../{namespace}/forward_proxy_policys` | `.../{namespace}/forward_proxy_policys/{name}` | `.../{metadata.namespace}/forward_proxy_policys` | `.../{metadata.namespace}/forward_proxy_policys/{metadata.name}` |
| `views.proxy` | `.../{namespace}/proxys` | `.../{namespace}/proxys/{name}/ca_certificate` | `.../{metadata.namespace}/proxys` | `.../{metadata.namespace}/proxys/{metadata.name}` |
| `views.terraform_parameters` | `.../{namespace}/terraform_parameters/{view_kind}/{view_name}/status` | `—` | `—` | `—` |
| `views.third_party_application` | `.../{namespace}/third_party_applications` | `.../{namespace}/third_party_applications/{name}/generate_token` | `.../{namespace}/third_party_application/get_security_config` | `.../{metadata.namespace}/third_party_applications/{metadata.name}` |
| `views.view_internal` | `.../{namespace}/view_internal/{view_kind}/{view_name}` | `—` | `—` | `—` |
| `virtual_host` | `.../{namespace}/virtual_hosts` | `.../{namespace}/virtual_hosts/{name}/get-dns-info` | `.../{metadata.namespace}/virtual_hosts` | `.../{metadata.namespace}/virtual_hosts/{metadata.name}` |
| `was.user_token` | `.../system/was/user_token` | `—` | `—` | `—` |

## Security & WAF

| Resource | List (GET) | Get/Delete | Create (POST) | Replace (PUT) |
|----------|-----------|------------|---------------|---------------|
| `app_firewall` | `.../{namespace}/app_firewalls` | `.../{namespace}/app_firewalls/{name}` | `.../{metadata.namespace}/app_firewalls` | `.../{metadata.namespace}/app_firewalls/{metadata.name}` |
| `fast_acl` | `.../{namespace}/fast_acls` | `.../{namespace}/fast_acls/{name}` | `.../{metadata.namespace}/fast_acls` | `.../{metadata.namespace}/fast_acls/{metadata.name}` |
| `fast_acl_rule` | `.../{namespace}/fast_acl_rules` | `.../{namespace}/fast_acl_rules/{name}` | `.../{metadata.namespace}/fast_acl_rules` | `.../{metadata.namespace}/fast_acl_rules/{metadata.name}` |
| `malicious_user_mitigation` | `.../{namespace}/malicious_user_mitigations` | `.../{namespace}/malicious_user_mitigations/{name}` | `.../{metadata.namespace}/malicious_user_mitigations` | `.../{metadata.namespace}/malicious_user_mitigations/{metadata.name}` |
| `protocol_inspection` | `.../{namespace}/protocol_inspections` | `.../{namespace}/protocol_inspections/{name}` | `.../{metadata.namespace}/protocol_inspections` | `.../{metadata.namespace}/protocol_inspections/{metadata.name}` |
| `rate_limiter` | `.../{namespace}/rate_limiters` | `.../{namespace}/rate_limiters/{name}` | `.../{metadata.namespace}/rate_limiters` | `.../{metadata.namespace}/rate_limiters/{metadata.name}` |
| `sensitive_data_policy` | `.../{namespace}/sensitive_data_policys` | `.../{namespace}/sensitive_data_policys/{name}` | `.../{metadata.namespace}/sensitive_data_policys` | `.../{metadata.namespace}/sensitive_data_policys/{metadata.name}` |
| `service_policy` | `.../{namespace}/service_policys` | `.../{namespace}/service_policys/{name}` | `.../{metadata.namespace}/service_policys` | `.../{metadata.namespace}/service_policys/{metadata.name}` |
| `service_policy_rule` | `.../{namespace}/service_policy_rules` | `.../{namespace}/service_policy_rules/{name}` | `.../{metadata.namespace}/service_policy_rules` | `.../{metadata.namespace}/service_policy_rules/{metadata.name}` |
| `service_policy_set` | `.../{namespace}/service_policy_sets` | `.../{namespace}/service_policy_sets/{name}` | `—` | `—` |
| `shape_bot_defense_instance` | `.../{namespace}/shape_bot_defense_instances` | `.../{namespace}/shape_bot_defense_instances/{name}` | `—` | `—` |
| `user_identification` | `.../{namespace}/user_identifications` | `.../{namespace}/user_identifications/{name}` | `.../{metadata.namespace}/user_identifications` | `.../{metadata.namespace}/user_identifications/{metadata.name}` |
| `views.bot_defense_app_infrastructure` | `.../{namespace}/bot_defense_app_infrastructures` | `.../{namespace}/bot_defense_app_infrastructures/{name}` | `.../{metadata.namespace}/bot_defense_app_infrastructures` | `.../{metadata.namespace}/bot_defense_app_infrastructures/{metadata.name}` |
| `views.rate_limiter_policy` | `.../{namespace}/rate_limiter_policys` | `.../{namespace}/rate_limiter_policys/{name}` | `.../{metadata.namespace}/rate_limiter_policys` | `.../{metadata.namespace}/rate_limiter_policys/{metadata.name}` |
| `waf_exclusion_policy` | `.../{namespace}/waf_exclusion_policys` | `.../{namespace}/waf_exclusion_policys/{name}` | `.../{metadata.namespace}/waf_exclusion_policys` | `.../{metadata.namespace}/waf_exclusion_policys/{metadata.name}` |
| `waf_signatures_changelog` | `.../{namespace}/virtual_hosts/{vh_name}/released_signatures` | `—` | `—` | `—` |
