*** Settings ***
Documentation     Verify Site Hierarchy Buildings
Suite Setup       Login CatalystCenter
Resource          ../../catalyst_center_common.resource
Default Tags      config   catalyst_center   site_hierarchy   sites   buildings   site_specific

*** Test Cases ***

Check Buildings Configuration in Data Model
    ${has_buildings}=   Evaluate   {{ 'True' if catalyst_center.sites is defined and catalyst_center.sites.buildings is defined and catalyst_center.sites.buildings | length > 0 else 'False' }}
    Pass Execution If   not ${has_buildings}   No buildings configured in data model, skipping building tests

{% for building in catalyst_center.sites.buildings | default([]) %}
Verify Building {{ (building.parent_name ~ '/' ~ building.name) | replace(' ', '\\ ') }}

    # Dynamically construct the nameHierarchy without a leading slash if building.parent_name is empty
    ${nameHierarchy}=   Evaluate   '{{ (building.parent_name ~ '/' ~ building.name) | replace(' ', '\\ ') }}' if '{{ building.parent_name | replace(' ', '\\ ') }}' else '{{ building.name | replace(' ', '\\ ') }}'

    # Check if this site should be skipped based on MANAGED_SITES
    ${should_skip}=   Should Skip Site Validation   ${nameHierarchy}
    Pass Execution If   ${should_skip}   Building ${nameHierarchy} not managed by this deployment state - skipping validation

    ${r}=   Get Cached Sites Data

    # Check if building exists in API response
    ${building_data}=   Get Value From Json   ${r.json()}   $.response[?(@.nameHierarchy=='${nameHierarchy}')]
    ${building_exists}=   Evaluate   len(${building_data}) > 0
    Run Keyword If   not ${building_exists}   Fail   Building ${nameHierarchy} not found in Catalyst Center - deployment issue

    ${building}=   Set Variable   $.response[?(@.nameHierarchy=='${nameHierarchy}')]
    Should Be Equal Value Json String   ${r.json()}   ${building}.name  {{ building.name | replace(' ', '\\ ') }}

    ${latitude}=   Get Value From Json   ${r.json()}   $.response[?(@.nameHierarchy=='${nameHierarchy}')].latitude
    ${longitude}=   Get Value From Json   ${r.json()}   $.response[?(@.nameHierarchy=='${nameHierarchy}')].longitude
    ${country}=   Get Value From Json   ${r.json()}   $.response[?(@.nameHierarchy=='${nameHierarchy}')].country
    {% if building.latitude | default(defaults.catalyst_center.sites.buildings.latitude) | default('') %}
    ${configured_latitude}=   Set Variable   {{ building.latitude | default(defaults.catalyst_center.sites.buildings.latitude) }}
    ${latitude_diff}=   Evaluate   abs(${latitude}[0] - ${configured_latitude})
    Should Be True   ${latitude_diff} < 0.00001   Latitude difference ${latitude_diff} exceeds tolerance
    {% endif %}

    {% if building.longitude | default(defaults.catalyst_center.sites.buildings.longitude) | default('') %}
    ${configured_longitude}=   Set Variable   {{ building.longitude | default(defaults.catalyst_center.sites.buildings.longitude) }}
    ${longitude_diff}=   Evaluate   abs(${longitude}[0] - ${configured_longitude})
    Should Be True   ${longitude_diff} < 0.00001   Longitude difference ${longitude_diff} exceeds tolerance
    {% endif %}

    Run Keyword If   '{{building.country | default(defaults.catalyst_center.sites.buildings.country) | default('') }}' != ''   Should Be Equal As Strings   ${country}[0]   {{ building.country | default(defaults.catalyst_center.sites.buildings.country) | default('') }}

    {% if building.address is defined %}
    # Validate building address (only compare when the API returns it)
    ${address}=   Get Value From Json   ${r.json()}   $.response[?(@.nameHierarchy=='${nameHierarchy}')].address
    ${expected_address}=   Set Variable   {{ building.address | replace(' ', '\\ ') }}
    Run Keyword If   ${address} and len(${address}) > 0   Should Be Equal As Strings   ${address}[0]   ${expected_address}   msg=Building address mismatch for ${nameHierarchy}
    {% endif %}

    # Retrieve the parent_id for the building
    ${parent_id}=   Get Value From Json   ${r.json()}   $.response[?(@.nameHierarchy=='${nameHierarchy}')].parentId
    # Validate parent site exists in cached sites data
    ${parent_site_data}=   Get Value From Json   ${r.json()}   $.response[?(@.id=='${parent_id}[0]')]
    # Use nameHierarchy if available, otherwise use name (for Global site)
    ${parent_hierarchy}=   Run Keyword And Return Status   Dictionary Should Contain Key   ${parent_site_data}[0]   nameHierarchy
    ${expected_parent}=   Set Variable   {{ building.parent_name | replace(' ', '\\ ') }}
    Run Keyword If   ${parent_site_data} and ${parent_hierarchy}   Should Be Equal As Strings   ${parent_site_data}[0][nameHierarchy]   ${expected_parent}
    Run Keyword If   ${parent_site_data} and not ${parent_hierarchy}   Should Be Equal As Strings   ${parent_site_data}[0][name]   ${expected_parent}
{% endfor %}
