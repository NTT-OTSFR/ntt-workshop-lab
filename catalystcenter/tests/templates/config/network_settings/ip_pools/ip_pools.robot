*** Settings ***
Documentation   Verify Network Settings IP Pools
Suite Setup     Login CatalystCenter
Resource        ../../../catalyst_center_common.resource
Default Tags    config   catalyst_center   network_settings   ip_pools

*** Test Cases ***

Get IP Pools
    ${r}=   GET With Rate Limit Retry   /api/v2/ippool
    Log   Response Status Code: ${r.status_code}
    Set Suite Variable   ${r}
    Log   Response: ${r.json()}

{% for ip_pool in catalyst_center.network_settings.ip_pools | default([]) %}
Verify IP Pool {{ ip_pool.name }}
    ${pool_info}=   Get Value From Json   ${r.json()}   $.response[?(@.ipPoolName=='{{ ip_pool.name }}')]
    log  ${pool_info}
    Should Be Equal Value Json String   ${pool_info[0]}   $.ipPoolName   {{ ip_pool.name }}
    Should Be Equal Value Json String   ${pool_info[0]}   $.ipPoolType   {{ ip_pool.type | default(defaults.catalyst_center.network_settings.ip_pools.type) | lower }}
    ${rec_dhcp_servers_list}=    Get Value From Json    ${pool_info[0]}    $.dhcpServerIps
    ${exp_dhcp_servers_list}=    Create List    {{ ip_pool.dhcp_servers | default([]) | join('   ') }}
    Lists Should Be Equal    ${rec_dhcp_servers_list[0]}    ${exp_dhcp_servers_list}    ignore_order=True    msg=dhcp servers
    ${rec_dns_servers_list}=    Get Value From Json    ${pool_info[0]}    $.dnsServerIps
    ${exp_dns_servers_list}=    Create List    {{ ip_pool.dns_servers | default([]) | join('   ') }}
    Lists Should Be Equal    ${rec_dns_servers_list[0]}    ${exp_dns_servers_list}    ignore_order=True    msg=dns servers
    Should Be Equal Value Json String   ${pool_info[0]}   $.gateway   {{ ip_pool.gateway | default(defaults.catalyst_center.network_settings.ip_pools.gateway) | default('') }}
    Should Be Equal Value Json String   ${pool_info[0]}   $.ipPoolCidr   {{ ip_pool.ip_pool_cidr }}
{% endfor %}