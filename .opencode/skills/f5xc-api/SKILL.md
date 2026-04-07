---
name: f5xc-api
description: "F5 Distributed Cloud REST API operations — authenticate, list, create, read, update, delete F5 XC resources (load balancers, origin pools, WAF, DNS, sites, namespaces, app firewall, bot defense, service policies). Activate when user mentions F5 XC, Distributed Cloud, volterra, XC console, API token, load balancer CRUD, origin pool, WAF policy, or platform configuration management."
compatibility: opencode
metadata:
  model: devstral-24b
  port: "8002"
  specialization: function-calling
---

# F5 Distributed Cloud API Operations

Interact with the F5 XC platform through its REST API using curl and jq. This skill provides structured workflows for authentication, CRUD operations, and resource management across 150+ resource types.

## When to use

- Listing, creating, reading, updating, or deleting F5 XC resources
- Managing HTTP/TCP/UDP load balancers and origin pools
- Configuring WAF policies, bot defense, or API security
- Managing DNS zones and DNS load balancers
- Working with cloud sites (AWS, Azure, GCP)
- Checking namespace resources or tenant configuration
- Any REST API interaction with F5 Distributed Cloud / Volterra

## Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `F5XC_API_URL` | Console API base URL | `https://<tenant>.console.ves.volterra.io` |
| `F5XC_API_TOKEN` | API authentication token | (user-provided) |
| `F5XC_NAMESPACE` | Default namespace | (user-provided) |
| `F5XC_USERNAME` | Console username | (user-provided) |
| `F5XC_EMAIL` | Email for operations | (user-provided) |
| `F5XC_LB_NAME` | Default load balancer name | (user-provided) |
| `F5XC_DOMAINNAME` | Application domain | (user-provided) |
| `F5XC_ROOT_DOMAIN` | Root domain | (user-provided) |

## Authentication

```bash
# All requests use the APIToken header
curl -s "${F5XC_API_URL}/api/config/namespaces/${F5XC_NAMESPACE}/http_loadbalancers" \
  -H "Authorization: APIToken ${F5XC_API_TOKEN}" | jq .
```

## CRUD Operations

### List resources
```bash
curl -s "${F5XC_API_URL}/api/config/namespaces/${F5XC_NAMESPACE}/{resource_plural}" \
  -H "Authorization: APIToken ${F5XC_API_TOKEN}" | jq '.items[] | {name, namespace}'
```

### Get a specific resource
```bash
curl -s "${F5XC_API_URL}/api/config/namespaces/${F5XC_NAMESPACE}/{resource_plural}/{name}" \
  -H "Authorization: APIToken ${F5XC_API_TOKEN}" | jq .
```

### Create a resource
```bash
curl -s -X POST "${F5XC_API_URL}/api/config/namespaces/${F5XC_NAMESPACE}/{resource_plural}" \
  -H "Authorization: APIToken ${F5XC_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "metadata": {
      "name": "my-resource",
      "namespace": "'${F5XC_NAMESPACE}'",
      "description": "Created via API"
    },
    "spec": { ... }
  }' | jq .
```

### Replace (update) a resource
```bash
curl -s -X PUT "${F5XC_API_URL}/api/config/namespaces/${F5XC_NAMESPACE}/{resource_plural}/{name}" \
  -H "Authorization: APIToken ${F5XC_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "metadata": { "name": "my-resource", "namespace": "'${F5XC_NAMESPACE}'" },
    "spec": { ... }
  }' | jq .
```

### Delete a resource
```bash
curl -s -X DELETE "${F5XC_API_URL}/api/config/namespaces/${F5XC_NAMESPACE}/{resource_plural}/{name}" \
  -H "Authorization: APIToken ${F5XC_API_TOKEN}" | jq .
```

## Resource Quick Reference (Most Common)

| Resource | Plural (API path) | Category |
|----------|-------------------|----------|
| HTTP Load Balancer | `http_loadbalancers` | Load Balancing |
| TCP Load Balancer | `tcp_loadbalancers` | Load Balancing |
| UDP Load Balancer | `udp_loadbalancers` | Load Balancing |
| CDN Load Balancer | `cdn_loadbalancers` | Load Balancing |
| Origin Pool | `origin_pools` | Load Balancing |
| Health Check | `healthchecks` | Load Balancing |
| App Firewall (WAF) | `app_firewalls` | Security |
| Service Policy | `service_policys` | Security |
| Rate Limiter Policy | `rate_limiter_policys` | Security |
| Bot Defense | `shape_bot_defense_instances` | Security |
| API Definition | `api_definitions` | API Security |
| DNS Zone | `dns_zones` | DNS |
| DNS Load Balancer | `dns_load_balancers` (prefix: `/api/config/dns/`) | DNS |
| Certificate | `certificates` | Certificates |
| Namespace | `namespaces` (via `/api/web/namespaces`) | Admin |
| AWS VPC Site | `aws_vpc_sites` | Cloud Sites |
| Azure VNet Site | `azure_vnet_sites` | Cloud Sites |
| GCP VPC Site | `gcp_vpc_sites` | Cloud Sites |
| Virtual K8s | `virtual_k8ss` | Kubernetes |
| Network Policy | `network_policys` | Networking |

For the full 150-resource index, see `references/RESOURCE_INDEX.md`.

## Common Workflows

### Create HTTP Load Balancer with Origin Pool

1. Create the origin pool:
```bash
curl -s -X POST "${F5XC_API_URL}/api/config/namespaces/${F5XC_NAMESPACE}/origin_pools" \
  -H "Authorization: APIToken ${F5XC_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "metadata": { "name": "my-origin", "namespace": "'${F5XC_NAMESPACE}'" },
    "spec": {
      "origin_servers": [{
        "public_name": { "dns_name": "backend.example.com" },
        "labels": {}
      }],
      "port": 443,
      "use_tls": {
        "use_host_header_as_sni": {},
        "tls_config": { "default_security": {} },
        "skip_server_verification": {}
      },
      "loadbalancer_algorithm": "LB_OVERRIDE",
      "endpoint_selection": "LOCAL_PREFERRED"
    }
  }' | jq .
```

2. Create the HTTP load balancer referencing the origin pool:
```bash
curl -s -X POST "${F5XC_API_URL}/api/config/namespaces/${F5XC_NAMESPACE}/http_loadbalancers" \
  -H "Authorization: APIToken ${F5XC_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "metadata": { "name": "my-lb", "namespace": "'${F5XC_NAMESPACE}'" },
    "spec": {
      "domains": ["app.example.com"],
      "https_auto_cert": {
        "http_redirect": true,
        "add_hsts": false,
        "port": 443,
        "no_mtls": {},
        "default_header": {},
        "enable_path_normalize": {},
        "default_loadbalancer": {}
      },
      "default_route_pools": [{
        "pool": {
          "tenant": "",
          "namespace": "'${F5XC_NAMESPACE}'",
          "name": "my-origin"
        },
        "weight": 1
      }],
      "advertise_on_public_default_vip": {},
      "disable_rate_limit": {},
      "disable_waf": {},
      "round_robin": {},
      "no_challenge": {}
    }
  }' | jq .
```

## Error Handling

| HTTP Code | Meaning | Action |
|-----------|---------|--------|
| 200 | Success | Parse response |
| 401 | Not authorized | Check F5XC_API_TOKEN |
| 403 | No permission | Token lacks RBAC for this operation |
| 404 | Not found | Resource doesn't exist |
| 409 | Conflict | Resource already exists (for create) |
| 429 | Rate limited | Wait and retry |
| 500 | Server error | Retry or check resource spec validity |
