
*** Settings ***
Library    String
Library    ../myutils.py

*** Test Cases ***
{% for domain in meraki.domains | default([], true) %}
{% for organization in domain.organizations | default([], true) %}
{% for network in organization.networks | default([], true) %}
{% for wireless_ssid in network.wireless.ssids | default([], true) %}

{% if wireless_ssid.ssid_number is defined %}
Verify {{ organization.name }}/networks/{{ network.name }}/wireless.ssids/{{ wireless_ssid.name }}//number
    [Setup]   Get Meraki Data   /networks/{networkId}/wireless/ssids/{number}   ['{{ organization.name }}', '{{ network.name }}', '{{ wireless_ssid.name }}']   wireless_ssid
    Should Be Equal As Strings   ${wireless_ssid}[number]   {{ wireless_ssid.ssid_number }}

{% endif %}
{% if wireless_ssid.name is defined %}
Verify {{ organization.name }}/networks/{{ network.name }}/wireless.ssids/{{ wireless_ssid.name }}//name
    [Setup]   Get Meraki Data   /networks/{networkId}/wireless/ssids/{number}   ['{{ organization.name }}', '{{ network.name }}', '{{ wireless_ssid.name }}']   wireless_ssid
    Should Be Equal As Strings   ${wireless_ssid}[name]   {{ wireless_ssid.name }}

{% endif %}
{% if wireless_ssid.enabled is defined %}
Verify {{ organization.name }}/networks/{{ network.name }}/wireless.ssids/{{ wireless_ssid.name }}//enabled
    [Setup]   Get Meraki Data   /networks/{networkId}/wireless/ssids/{number}   ['{{ organization.name }}', '{{ network.name }}', '{{ wireless_ssid.name }}']   wireless_ssid
    Should Be Equal As Strings   ${wireless_ssid}[enabled]   {{ wireless_ssid.enabled }}
{% endif %}

{% endfor %}

{% endfor %}
{% endfor %}
{% endfor %}
