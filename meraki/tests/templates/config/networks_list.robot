
*** Settings ***
Library    String
Library    ../myutils.py

*** Test Cases ***
{% for domain in meraki.domains | default([], true) %}
{% for organization in domain.organizations | default([], true) %}
{% for network in organization.networks | default([], true) %}

# Note: id is not checked, as it is only included in the response,
#       but not in the OpenAPI request, hence not in the .nac.yaml schema.
# Note: organizationId is not checked, as it is only included in the response,
#       but not in the OpenAPI request, hence not in the .nac.yaml schema.
{% if network.name is defined %}
Verify {{ organization.name }}/networks/{{ network.name }}//name
    [Setup]   Get Meraki Data   /networks/{networkId}   ['{{ organization.name }}', '{{ network.name }}']   network
    Should Be Equal As Strings   ${network}[name]   {{ network.name }}

{% endif %}
{% if network.product_types is defined %}
Verify {{ organization.name }}/networks/{{ network.name }}//product_types
    [Setup]   Get Meraki Data   /networks/{networkId}   ['{{ organization.name }}', '{{ network.name }}']   network
    ${evaluated}=    Evaluate    {{ network.product_types }}
    ${validated}=    Validate Subset     ${network}[productTypes]    ${evaluated}
    Should Be True   ${validated}

{% endif %}
{% if network.time_zone is defined %}
Verify {{ organization.name }}/networks/{{ network.name }}//time_zone
    [Setup]   Get Meraki Data   /networks/{networkId}   ['{{ organization.name }}', '{{ network.name }}']   network
    Should Be Equal As Strings   ${network}[timeZone]   {{ network.time_zone }}

{% endif %}
{% if network.tags is defined %}
Verify {{ organization.name }}/networks/{{ network.name }}//tags
    [Setup]   Get Meraki Data   /networks/{networkId}   ['{{ organization.name }}', '{{ network.name }}']   network
    ${evaluated}=    Evaluate    {{ network.tags }}
    ${validated}=    Validate Subset     ${network}[tags]    ${evaluated}
    Should Be True   ${validated}
{% endif %}


{% endfor %}

{% endfor %}
{% endfor %}
