
*** Settings ***
Library    String
Library    ../myutils.py

*** Test Cases ***
{% for domain in meraki.domains | default([], true) %}
{% for organization in domain.organizations | default([], true) %}
{% for network in organization.networks | default([], true) %}

{% set switch_mtu = network.switch.mtu | default({}, true) %}
{% if switch_mtu.default_mtu_size is defined %}
Verify {{ organization.name }}/networks/{{ network.name }}/switch_mtu/default_mtu_size
    [Setup]   Get Meraki Data   /networks/{networkId}/switch/mtu   ['{{ organization.name }}', '{{ network.name }}']   switch_mtu
    Should Be Equal As Strings   ${switch_mtu}[defaultMtuSize]   {{ switch_mtu.default_mtu_size }}

{% endif %}
{% if switch_mtu.overrides is defined %}
Verify {{ organization.name }}/networks/{{ network.name }}/switch_mtu/overrides
    [Setup]   Get Meraki Data   /networks/{networkId}/switch/mtu   ['{{ organization.name }}', '{{ network.name }}']   switch_mtu
    ${evaluated}=    Evaluate    {{ switch_mtu.overrides }}
    ${validated}=    Validate Subset     ${switch_mtu}[overrides]    ${evaluated}
    Should Be True   ${validated}

{% endif %}


{% endfor %}
{% endfor %}
{% endfor %}
