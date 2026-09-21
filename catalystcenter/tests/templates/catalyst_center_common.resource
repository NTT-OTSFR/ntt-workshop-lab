*** Settings ***
Library   pabot.PabotLib
Library   RequestsLibrary
Library   JSONLibrary
Library   Collections
Library   OperatingSystem
Library   DateTime

*** Keywords ***
Get CatalystCenter Token
    [Documentation]   Fetch a fresh auth token, store it (and its expiry) in pabot shared state.
    ...               The token value is never returned or logged (Set Log Level NONE around it).
    ...               Expiry is tracked with CC_TOKEN_LIFETIME (seconds, default 3600) so the
    ...               token can be proactively refreshed before Catalyst Center invalidates it.
    ${cc_insecure}=   Get Environment Variable   CC_INSECURE   True
    ${verify}=   Set Variable If   '${cc_insecure}' == 'True' or '${cc_insecure}' == 'true'   False   True
    # NONE covers Create List (resolves CC_PASSWORD), the auth'd session, and the token
    # response so neither the password nor the token reaches log.html.
    ${log_level}=   Set Log Level   NONE
    ${auth}=   Create List   %{CC_USERNAME}   %{CC_PASSWORD}
    Create Session   login   %{CC_URL}   auth=${auth}   verify=${verify}   headers={"Accept": "application/json", "Content-Type": "application/json"}
    ${response}=   POST On Session   login   /api/system/v1/auth/token
    ${r_token}=   Get Value From Json   ${response.json()}   $.Token
    Set Parallel Value For Key   cc_token   ${r_token}[0]
    Set Log Level   ${log_level}
    ${token_lifetime}=   Get Environment Variable   CC_TOKEN_LIFETIME   3600
    ${created}=   Get Current Date   result_format=epoch
    ${expiry}=   Evaluate   ${created} + ${token_lifetime}
    Set Parallel Value For Key   cc_token_created   ${created}
    Set Parallel Value For Key   cc_token_expiry   ${expiry}

Check CatalystCenter Token Expiring
    [Documentation]   Returns True if the stored token is within the refresh buffer of expiry.
    ...               Buffer is CC_TOKEN_REFRESH_BUFFER seconds (default 120).
    ${current}=   Get Current Date   result_format=epoch
    ${expiry}=   Get Parallel Value For Key   cc_token_expiry
    ${buffer}=   Get Environment Variable   CC_TOKEN_REFRESH_BUFFER   120
    ${expiring}=   Evaluate   (${expiry} - ${current}) <= ${buffer}
    RETURN   ${expiring}

Verify CatalystCenter Token
    [Documentation]   Proactively refresh the shared token when close to expiry.
    ...               Lock-protected and double-checked so only one pabot worker refreshes.
    ${expiring}=   Check CatalystCenter Token Expiring
    IF   ${expiring}
        Acquire Lock   cc_token_refresh
        TRY
            ${expiring}=   Check CatalystCenter Token Expiring
            IF   ${expiring}
                Get CatalystCenter Token
            END
        EXCEPT
            Fatal Error   CatalystCenter Token Refresh Failed
        FINALLY
            Release Lock   cc_token_refresh
        END
    END

Refresh CatalystCenter Token On Unauthorized
    [Documentation]   Reactive safety net: force a token refresh after a 401, then rebuild
    ...               this worker's session. Guarded so parallel workers don't stampede on a
    ...               401 storm - if the token was refreshed in the last 15s, reuse it.
    Acquire Lock   cc_token_refresh
    TRY
        ${current}=   Get Current Date   result_format=epoch
        ${created}=   Get Parallel Value For Key   cc_token_created
        ${recently_refreshed}=   Evaluate   (${current} - ${created}) < 15
        IF   not ${recently_refreshed}
            Get CatalystCenter Token
        END
    EXCEPT
        Fatal Error   CatalystCenter Token Refresh Failed
    FINALLY
        Release Lock   cc_token_refresh
    END
    Create CatalystCenter Session

Create CatalystCenter Session
    [Documentation]   Create the worker-local CatalystCenter_Session using the current shared token.
    ...               Runs under Set Log Level NONE so the token never reaches log.html.
    ${cc_insecure}=   Get Environment Variable   CC_INSECURE   True
    ${verify}=   Set Variable If   '${cc_insecure}' == 'True' or '${cc_insecure}' == 'true'   False   True
    ${log_level}=   Set Log Level   NONE
    ${cc_token}=   Get Parallel Value For Key   cc_token
    ${headers}=   Create Dictionary   x-auth-token=${cc_token}
    Create Session   CatalystCenter_Session   %{CC_URL}   headers=${headers}   verify=${verify}
    Set Log Level   ${log_level}

Login CatalystCenter
    Run Only Once   Get CatalystCenter Token
    Verify CatalystCenter Token
    Create CatalystCenter Session

Should Be Equal Value Json String
    [Arguments]   ${json}   ${json_path}   ${value}=${EMPTY}
    ${r_value}=   Get Value From Json   ${json}   ${json_path}
    Run Keyword If   "${value}" != "${EMPTY}"   Should Be Equal As Strings   ${r_value}[0]   ${value}

Should Be Equal Value Json List
    [Arguments]   ${json}   ${json_path}   ${value}=${None}
    ${r_value}=   Get Value From Json   ${json}   ${json_path}
    Run Keyword If   "${value}" != "${None}"   Lists Should Be Equal   ${r_value}[0]   ${value}   ignore_order=True

Should Be Equal Value Json Boolean
    [Arguments]   ${json}   ${json_path}   ${value}=${EMPTY}
    ${r_value}=   Get Value From Json   ${json}   ${json_path}
    Run Keyword If   "${value}" != "${EMPTY}"   Should Be Equal As Strings   ${r_value}[0]   ${value}

Should Be Equal Value Json Number
    [Arguments]   ${json}   ${json_path}   ${value}=${EMPTY}
    ${r_value}=   Get Value From Json   ${json}   ${json_path}
    Run Keyword If   "${value}" != "${EMPTY}"   Should Be Equal As Numbers   ${r_value}[0]   ${value}

Get Sites Data

   ${count_response}=   GET With Rate Limit Retry   /dna/intent/api/v1/sites/count
   ${total_count}=   Get Value From Json   ${count_response.json()}   $.response.count
   ${count}=   Convert To Integer   ${total_count}[0]

   ${all_sites}=   Create List
   ${offset}=   Set Variable   ${1}
   ${limit}=   Set Variable   ${500}

   WHILE   ${offset} <= ${count}

       &{params}=   Create Dictionary   offset=${offset}   limit=${limit}
       ${s}=   GET With Rate Limit Retry   /dna/intent/api/v1/sites   params=${params}

       ${sites_batch}=   Get Value From Json   ${s.json()}   $.response

       FOR   ${site}   IN   @{sites_batch}[0]
           Append To List   ${all_sites}   ${site}
       END

       ${offset}=   Evaluate   ${offset} + ${limit}
   END

   ${total_fetched}=   Get Length   ${all_sites}

   ${complete_json}=   Create Dictionary   response=${all_sites}   version=1.0
   ${wrapper}=   Evaluate   (lambda d: type('Response', (), {'json': lambda s: d, 'status_code': 200})())(${complete_json})

   Set Global Variable   ${SITES_DATA}   ${wrapper}
   RETURN   ${wrapper}

Get Cached Sites Data
    # Check if sites data is already cached, if not fetch it
    ${sites_exists}=   Run Keyword And Return Status   Variable Should Exist   ${SITES_DATA}
    Run Keyword If   not ${sites_exists}   Get Sites Data
    RETURN   ${SITES_DATA}

Get Site Assignments Data
    [Documentation]   Fetch ALL site-assignment IDs for a network profile, following pagination.
    ...               The siteAssignments API defaults to 100 records per page
    [Arguments]   ${profile_id}
    ${all_ids}=   Create List
    ${offset}=   Set Variable   ${1}
    ${limit}=   Set Variable   ${500}
    ${more}=   Set Variable   ${True}
    WHILE   ${more}
        &{params}=   Create Dictionary   offset=${offset}   limit=${limit}
        ${a}=   GET With Rate Limit Retry   /dna/intent/api/v1/networkProfilesForSites/${profile_id}/siteAssignments   params=${params}
        ${batch}=   Get Value From Json   ${a.json()}   $.response
        ${batch_list}=   Set Variable   ${batch}[0]
        ${batch_len}=   Get Length   ${batch_list}
        FOR   ${item}   IN   @{batch_list}
            ${item_id}=   Get From Dictionary   ${item}   id
            Append To List   ${all_ids}   ${item_id}
        END
        ${more}=   Evaluate   ${batch_len} == ${limit}
        ${offset}=   Evaluate   ${offset} + ${limit}
    END
    RETURN   ${all_ids}

Get Cached Site Assignments
    [Documentation]   Return the fully-paginated site-assignment IDs for a profile, caching per profile ID.
    [Arguments]   ${profile_id}
    ${cache_exists}=   Run Keyword And Return Status   Variable Should Exist   ${SITE_ASSIGNMENTS_CACHE}
    IF   not ${cache_exists}
        ${new_cache}=   Create Dictionary
        Set Global Variable   ${SITE_ASSIGNMENTS_CACHE}   ${new_cache}
    END
    ${is_cached}=   Run Keyword And Return Status   Dictionary Should Contain Key   ${SITE_ASSIGNMENTS_CACHE}   ${profile_id}
    IF   not ${is_cached}
        ${assignments}=   Get Site Assignments Data   ${profile_id}
        Set To Dictionary   ${SITE_ASSIGNMENTS_CACHE}   ${profile_id}=${assignments}
    END
    ${cached}=   Get From Dictionary   ${SITE_ASSIGNMENTS_CACHE}   ${profile_id}
    RETURN   ${cached}

Get Fabric Sites Data
    ${f}=   GET With Rate Limit Retry   /dna/intent/api/v1/sda/fabricSites
    Log   Fabric Sites Response Status Code: ${f.status_code}
    Set Global Variable   ${FABRIC_SITES_DATA}   ${f}
    RETURN   ${f}

Get Cached Fabric Sites Data
    # Check if fabric sites data is already cached, if not fetch it
    ${fabric_sites_exists}=   Run Keyword And Return Status   Variable Should Exist   ${FABRIC_SITES_DATA}
    Run Keyword If   not ${fabric_sites_exists}   Get Fabric Sites Data
    RETURN   ${FABRIC_SITES_DATA}

Get Fabric Zones Data
    ${f}=   GET With Rate Limit Retry   /dna/intent/api/v1/sda/fabricZones
    Log   Fabric Zones Response Status Code: ${f.status_code}
    Set Global Variable   ${FABRIC_ZONES_DATA}   ${f}
    RETURN   ${f}

Get Cached Fabric Zones Data
    # Check if fabric zones data is already cached, if not fetch it
    ${fabric_zones_exists}=   Run Keyword And Return Status   Variable Should Exist   ${FABRIC_ZONES_DATA}
    Run Keyword If   not ${fabric_zones_exists}   Get Fabric Zones Data
    RETURN   ${FABRIC_ZONES_DATA}

Get All Network Devices
    # First, try to get the count of devices
    ${count_response}=   GET With Rate Limit Retry   /dna/data/api/v1/networkDevices/count
    ${total_count}=   Get Value From Json   ${count_response.json()}   $.response.count
    ${count}=   Convert To Integer   ${total_count}[0]

    ${all_devices}=   Create List
    ${offset}=   Set Variable   ${1}
    ${limit}=   Set Variable   ${500}

    WHILE   ${offset} <= ${count}

        &{params}=   Create Dictionary   offset=${offset}   limit=${limit}
        ${d}=   GET With Rate Limit Retry   /dna/data/api/v1/networkDevices   params=${params}

        ${devices_batch}=   Get Value From Json   ${d.json()}   $.response

        FOR   ${device}   IN   @{devices_batch}[0]
            Append To List   ${all_devices}   ${device}
        END

        ${offset}=   Evaluate   ${offset} + ${limit}
    END

    ${total_fetched}=   Get Length   ${all_devices}

    ${complete_json}=   Create Dictionary   response=${all_devices}   version=1.0
    ${wrapper}=   Evaluate   (lambda d: type('Response', (), {'json': lambda s: d, 'status_code': 200})())(${complete_json})

    Set Global Variable   ${NETWORK_DEVICES_DATA}   ${wrapper}
    RETURN   ${wrapper}

Get Cached Network Devices Data
    # Check if network devices data is already cached, if not fetch it
    ${devices_exists}=   Run Keyword And Return Status   Variable Should Exist   ${NETWORK_DEVICES_DATA}
    Run Keyword If   not ${devices_exists}   Get All Network Devices
    RETURN   ${NETWORK_DEVICES_DATA}

Should Skip Site Validation
    [Documentation]   Check if a site should be skipped based on MANAGED_SITES env var
    ...               Returns True if site should be skipped, False if it should be validated
    [Arguments]   ${site_name}

    # Get MANAGED_SITES env var (empty = validate all sites)
    ${managed_sites}=   Get Environment Variable   MANAGED_SITES   default=${EMPTY}

    # If MANAGED_SITES is empty, don't skip (validate all)
    ${should_validate_all}=   Evaluate   '${managed_sites}' == ''
    Return From Keyword If   ${should_validate_all}   ${False}

    # Get MANAGE_SPECIFIC_SITES_ONLY flag (default = false, meaning include children)
    ${manage_specific_only}=   Get Environment Variable   MANAGE_SPECIFIC_SITES_ONLY   default=false

    # Check if site_name is in managed_sites (comma-separated list)
    # If manage_specific_only = true: only exact matches
    # If manage_specific_only = false: exact matches OR children of managed sites
    ${site_is_managed}=   Evaluate   '${site_name}' in '${managed_sites}'.split(',') or ('${manage_specific_only}' == 'false' and any('${site_name}'.startswith(site + '/') for site in '${managed_sites}'.split(',')))

    # Return True if should skip (site NOT managed), False if should validate (site IS managed)
    ${should_skip}=   Evaluate   not ${site_is_managed}
    RETURN   ${should_skip}

GET With Rate Limit Retry
    [Documentation]   Performs GET request with automatic retry on 429 rate limit errors
    ...               and on 401 unauthorized (expired token) errors.
    ...               429: waits 60 seconds before retrying to allow the rate limit window to reset.
    ...               401: refreshes the auth token, rebuilds the session, and retries.
    ...               Max retries: 3 attempts (default)
    [Arguments]   ${url}   ${params}=${None}   ${max_retries}=${3}

    FOR   ${retry_count}   IN RANGE   ${max_retries}
        # Suppress RequestsLibrary auto-logging: it logs request headers (incl. the
        # x-auth-token) and full response bodies at INFO on every call. NONE hides both;
        # our own retry/failure messages below run at the restored level.
        ${log_level}=   Set Log Level   NONE
        ${status}   ${response}=   Run Keyword And Ignore Error
        ...   GET On Session   CatalystCenter_Session   url=${url}   params=${params}
        Set Log Level   ${log_level}

        Return From Keyword If   '${status}' == 'PASS'   ${response}

        # Classify the error by checking the error message for status codes
        ${is_rate_limit}=   Run Keyword And Return Status
        ...   Should Contain   ${response}   429
        ${is_unauthorized}=   Run Keyword And Return Status
        ...   Should Contain   ${response}   401

        ${attempts_remaining}=   Evaluate   ${max_retries} - ${retry_count} - 1

        # 401: token likely expired - refresh it, rebuild session, retry (does not sleep)
        IF   ${is_unauthorized}
            IF   ${attempts_remaining} > 0
                Log   Unauthorized (401) for ${url}. Refreshing token and retrying (${attempts_remaining} attempts remaining)...
                Refresh CatalystCenter Token On Unauthorized
            ELSE
                Fail   Unauthorized (401) after ${max_retries} attempts: ${response}
            END
        ELSE IF   ${is_rate_limit}
            IF   ${attempts_remaining} > 0
                Log   Rate limit (429) hit for ${url}. Waiting 60 seconds before retry (${attempts_remaining} attempts remaining)...
                Sleep   60s
            ELSE
                Fail   Rate limit exceeded after ${max_retries} attempts: ${response}
            END
        ELSE
            Fail   ${response}
        END
    END

    Fail   Failed to complete GET request after ${max_retries} retries
