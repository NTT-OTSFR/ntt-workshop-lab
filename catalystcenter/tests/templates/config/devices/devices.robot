*** Settings ***
Documentation     Verify Device Inventory in Catalyst Center
Suite Setup       Login CatalystCenter
Resource          ../../catalyst_center_common.resource
Default Tags      config   catalyst_center   inventory   devices

*** Test Cases ***

Get Device Inventory
    ${r}=   Get Cached Network Devices Data
    Log     Response Status Code: ${r.status_code}
    Set Suite Variable   ${r}

Get Device Tags
    ${tags_response}=   GET With Rate Limit Retry   /dna/intent/api/v1/tags/networkDevices/membersAssociations
    Log   Response Status Code (Device Tags): ${tags_response.status_code}
    Set Suite Variable   ${DEVICE_TAGS_RESPONSE}   ${tags_response}

{% for device in catalyst_center.inventory.devices | default([]) %}
{# Escaped once and reused: two or more consecutive spaces are Robot's cell
   separator, so an unescaped value splits the cell it is interpolated into -
   silently truncating a test name, an asserted value or a JSONPath filter. #}
{% set device_site_esc = device.site | default('') | replace(' ', '\\ ') %}
Verify Device {{ device.name }}
    Run Keyword If   '{{ device.state | default('') }}' == 'PNP'   Pass Execution   Skipping further steps as device is in PNP process
    Run Keyword If   '{{ device.state | default('') }}' == 'INIT'   Pass Execution   Skipping further steps as device is in INIT state
{% if device.rma is defined %}
    Pass Execution   Skipping further steps as device has an active RMA (Return Material Authorization) replacement in progress
{% endif %}

    # Validate that the device exists in the API response
    ${device_data}=   Get Value From Json   ${r.json()}   $.response[?(@.name=='{{ device.name }}')]
    ${device_data}=   Run Keyword If   ${device_data} == []   Get Value From Json   ${r.json()}   $.response[?(@.name=='{{ device.fqdn_name }}')]   ELSE   Set Variable   ${device_data}

    Run Keyword If    not ${device_data}    Fail    Device {{ device.name }} or {{ device.fqdn_name }} not found in API response.

    # Extract the first matching device from the API response
    ${device_entry}=   Set Variable   ${device_data}[0]

    # Validate device attributes
    ${name_matches}=   Run Keyword And Return Status   Should Be Equal As Strings   ${device_entry['name']}   {{ device.name }}
    Run Keyword If   not ${name_matches}   Should Be Equal As Strings   ${device_entry['name']}   {{ device.fqdn_name }}
    # Validate management IP only when device_ip is defined in data model (e.g. APs may not have one)
    {% if device.device_ip is defined %}
    Should Be Equal As Strings   ${device_entry['managementIpAddress']}   {{ device.device_ip }}
    {% endif %}
    # Validate platform ID only when pid is defined in data model (e.g. APs may not have one)
    {% if device.pid is defined %}
    Should Be Equal As Strings   ${device_entry['platformId'].split(',')[0].strip()}    {{ device.pid }}
    {% endif %}
    Should Be Equal As Strings   ${device_entry['deviceRole']}   {{ device.device_role }}
    ${s}=   Get Cached Sites Data
    ${has_site_id}=   Run Keyword And Return Status   Dictionary Should Contain Key   ${device_entry}   siteId
    Run Keyword If   not ${has_site_id}   Fail   Device {{ device.name }} has no siteId in inventory - not assigned to site {{ device_site_esc }}
    ${site_data}=   Get Value From Json   ${s.json()}   $.response[?(@.id=='${device_entry['siteId']}')]
    Run Keyword If   not ${site_data}   Fail   Site with id ${device_entry['siteId']} not found for device {{ device.name }}
    ${site_entry}=   Set Variable   ${site_data}[0]

    Should Be Equal As Strings   ${site_entry['nameHierarchy']}   {{ device_site_esc }}

    # Validate device tags if defined in data model
    {% if device.tags is defined and device.tags | length > 0 %}
    ${device_id}=   Get From Dictionary   ${device_entry}   id
    ${device_tags_data}=   Get Value From Json   ${DEVICE_TAGS_RESPONSE.json()}   $.response[?(@.id=='${device_id}')]
    ${device_tags_count}=   Get Length   ${device_tags_data}
    Run Keyword If   ${device_tags_count} == 0   Fail   Expected tags {{ device.tags | string | replace(' ', '\\ ') }} but device {{ device.name }} has no tags in API response

    ${api_tags}=   Set Variable   ${device_tags_data[0].get('tags', [])}
    ${expected_tags}=   Create List{% for tag in device.tags %}   {{ tag | replace(' ', '\\ ') }}{% endfor %}

    FOR   ${expected_tag}   IN   @{expected_tags}
        ${tag_found}=   Set Variable   ${False}
        FOR   ${api_tag}   IN   @{api_tags}
            ${tag_name}=   Get From Dictionary   ${api_tag}   name
            ${match}=   Evaluate   '${tag_name}' == '${expected_tag}'
            IF   ${match}
                ${tag_found}=   Set Variable   ${True}
            END
        END
        Run Keyword If   not ${tag_found}   Fail   Tag '${expected_tag}' not found for device {{ device.name }}. API tags: ${api_tags}
    END
    {% endif %}

    # Validate managed AP locations on WLCs (covers 0.4.3 fix for WLCs configured with only secondary_managed_ap_locations)
    {% if device.primary_managed_ap_locations is defined or device.secondary_managed_ap_locations is defined or device.anchor_managed_ap_locations is defined %}
    ${wlc_id}=   Get From Dictionary   ${device_entry}   id

    {% if device.primary_managed_ap_locations is defined and device.primary_managed_ap_locations | length > 0 %}
    # ---- Primary managed AP locations ----
    ${primary_resp}=   GET With Rate Limit Retry   /dna/intent/api/v1/wirelessControllers/${wlc_id}/primaryManagedApLocations
    ${primary_actual_site_ids_result}=   Get Value From Json   ${primary_resp.json()}   $..siteId
    ${primary_actual_site_ids}=   Set Variable   ${primary_actual_site_ids_result}
    {% for site_path in device.primary_managed_ap_locations %}
    {% set site_path_esc = site_path | replace(' ', '\\ ') %}
    ${expected_site_data}=   Get Value From Json   ${s.json()}   $.response[?(@.nameHierarchy=='{{ site_path_esc }}')]
    Run Keyword If   not ${expected_site_data}   Fail   Expected primary managed AP location site '{{ site_path_esc }}' not found in Catalyst Center (not deployed?)
    ${expected_site_id}=   Get From Dictionary   ${expected_site_data[0]}   id
    Run Keyword And Continue On Failure   List Should Contain Value   ${primary_actual_site_ids}   ${expected_site_id}   msg=WLC {{ device.name }} primary managed AP location '{{ site_path_esc }}' (siteId=${expected_site_id}) not assigned on Catalyst Center
    {% endfor %}
    {% endif %}

    {% if device.secondary_managed_ap_locations is defined and device.secondary_managed_ap_locations | length > 0 %}
    # ---- Secondary managed AP locations (0.4.3 fix scenario) ----
    ${secondary_resp}=   GET With Rate Limit Retry   /dna/intent/api/v1/wirelessControllers/${wlc_id}/secondaryManagedApLocations
    ${secondary_actual_site_ids_result}=   Get Value From Json   ${secondary_resp.json()}   $..siteId
    ${secondary_actual_site_ids}=   Set Variable   ${secondary_actual_site_ids_result}
    {% for site_path in device.secondary_managed_ap_locations %}
    {% set site_path_esc = site_path | replace(' ', '\\ ') %}
    ${expected_site_data}=   Get Value From Json   ${s.json()}   $.response[?(@.nameHierarchy=='{{ site_path_esc }}')]
    Run Keyword If   not ${expected_site_data}   Fail   Expected secondary managed AP location site '{{ site_path_esc }}' not found in Catalyst Center (not deployed?)
    ${expected_site_id}=   Get From Dictionary   ${expected_site_data[0]}   id
    Run Keyword And Continue On Failure   List Should Contain Value   ${secondary_actual_site_ids}   ${expected_site_id}   msg=WLC {{ device.name }} secondary managed AP location '{{ site_path_esc }}' (siteId=${expected_site_id}) not assigned on Catalyst Center
    {% endfor %}
    {% endif %}

    {% if device.anchor_managed_ap_locations is defined and device.anchor_managed_ap_locations | length > 0 %}
    # ---- Anchor managed AP locations ----
    ${anchor_resp}=   GET With Rate Limit Retry   /dna/intent/api/v1/wirelessControllers/${wlc_id}/anchorManagedApLocations
    ${anchor_actual_site_ids_result}=   Get Value From Json   ${anchor_resp.json()}   $..siteId
    ${anchor_actual_site_ids}=   Set Variable   ${anchor_actual_site_ids_result}
    {% for site_path in device.anchor_managed_ap_locations %}
    {% set site_path_esc = site_path | replace(' ', '\\ ') %}
    ${expected_site_data}=   Get Value From Json   ${s.json()}   $.response[?(@.nameHierarchy=='{{ site_path_esc }}')]
    Run Keyword If   not ${expected_site_data}   Fail   Expected anchor managed AP location site '{{ site_path_esc }}' not found in Catalyst Center (not deployed?)
    ${expected_site_id}=   Get From Dictionary   ${expected_site_data[0]}   id
    Run Keyword And Continue On Failure   List Should Contain Value   ${anchor_actual_site_ids}   ${expected_site_id}   msg=WLC {{ device.name }} anchor managed AP location '{{ site_path_esc }}' (siteId=${expected_site_id}) not assigned on Catalyst Center
    {% endfor %}
    {% endif %}
    {% endif %}
{% endfor %}
