*** Settings ***
Library    SSHLibrary

*** Variables ***
${TEST_HOST}    openobserve.ns8-ci.test
${CURL}         curl -ksS --resolve ${TEST_HOST}:443:127.0.0.1

*** Test Cases ***
Install OpenObserve
    ${output}    ${rc}=    Execute Command    add-module ${IMAGE_URL} 1    return_rc=True
    Should Be Equal As Integers    ${rc}    0
    ${result}=    Evaluate    ast.literal_eval($output)    modules=ast
    Set Suite Variable    ${module_id}    ${result}[module_id]

Configure OpenObserve
    ${rc}=    Execute Command    api-cli run module/${module_id}/configure-module --data '{"host":"${TEST_HOST}","lets_encrypt":false,"http2https":true}'    return_stdout=False    return_rc=True
    Should Be Equal As Integers    ${rc}    0

Check Endpoint Health
    Wait Until Keyword Succeeds    3 min    5 sec    Check Health

Get Configuration Does Not Leak Secrets
    ${output}    ${rc}=    Execute Command    api-cli run module/${module_id}/get-configuration    return_rc=True
    Should Be Equal As Integers    ${rc}    0
    Should Contain    ${output}    "root_credentials_set": true
    Should Contain    ${output}    ${TEST_HOST}
    Should Not Contain    ${output}    ZO_ROOT_USER_PASSWORD
    ${pw}    ${rc}=    Execute Command    runagent -m ${module_id} sed -n 's/^ZO_ROOT_USER_PASSWORD=//p' openobserve.env    return_rc=True
    Should Be Equal As Integers    ${rc}    0
    Should Not Be Empty    ${pw}
    Should Not Contain    ${output}    ${pw}

Credentials File Is Private
    ${mode}    ${rc}=    Execute Command    runagent -m ${module_id} stat -c %a openobserve.env    return_rc=True
    Should Be Equal As Integers    ${rc}    0
    Should Be Equal    ${mode.strip()}    600

Initial Credentials Command Works
    ${output}    ${rc}=    Execute Command    runagent -m ${module_id} openobserve-initial-credentials    return_rc=True
    Should Be Equal As Integers    ${rc}    0
    Should Contain    ${output}    Email:
    Should Contain    ${output}    Password:

Unauthenticated Ingestion Is Rejected
    ${code}    ${rc}=    Execute Command    ${CURL} -o /dev/null -w '\%{http_code}' -X POST -H 'Content-Type: application/json' -d '[{"message":"x"}]' https://${TEST_HOST}/api/default/ci_logs/_json    return_rc=True
    Should Be Equal As Integers    ${rc}    0
    Should Be Equal    ${code.strip()}    401

Ingest Log Record
    ${rc}=    Execute Command
    ...    runagent -m ${module_id} bash -ec 'set -a; . openobserve.env; curl -ksS -f --resolve ${TEST_HOST}:443:127.0.0.1 -u "$ZO_ROOT_USER_EMAIL:$ZO_ROOT_USER_PASSWORD" -H "Content-Type: application/json" -d "[{\\"level\\":\\"info\\",\\"message\\":\\"ci-sanity\\"}]" https://${TEST_HOST}/api/default/ci_logs/_json'
    ...    return_stdout=False    return_rc=True
    Should Be Equal As Integers    ${rc}    0

Backup And Restore Sanity
    ${rc}=    Execute Command    runagent -m ${module_id} module-dump-state    return_stdout=False    return_rc=True
    Should Be Equal As Integers    ${rc}    0
    Wait Until Keyword Succeeds    3 min    5 sec    Check Health
    ${rc}=    Execute Command
    ...    runagent -m ${module_id} bash -ec 'test -s openobserve-data.tar && systemctl --user stop openobserve.service && podman volume rm openobserve-data && "$AGENT_INSTALL_DIR/actions/restore-module/40restore_volume" && systemctl --user start openobserve.service'
    ...    return_stdout=False    return_rc=True
    Should Be Equal As Integers    ${rc}    0
    Wait Until Keyword Succeeds    5 min    5 sec    Check Health
    Wait Until Keyword Succeeds    2 min    5 sec    Stream Exists After Restore
    ${rc}=    Execute Command    runagent -m ${module_id} module-cleanup-state    return_stdout=False    return_rc=True
    Should Be Equal As Integers    ${rc}    0

Remove OpenObserve
    ${rc}=    Execute Command    remove-module --no-preserve ${module_id}    return_stdout=False    return_rc=True
    Should Be Equal As Integers    ${rc}    0

*** Keywords ***
Check Health
    ${rc}=    Execute Command    ${CURL} -f https://${TEST_HOST}/healthz >/dev/null    return_stdout=False    return_rc=True
    Should Be Equal As Integers    ${rc}    0

Stream Exists After Restore
    ${rc}=    Execute Command
    ...    runagent -m ${module_id} bash -ec 'set -a; . openobserve.env; curl -ksS -f --resolve ${TEST_HOST}:443:127.0.0.1 -u "$ZO_ROOT_USER_EMAIL:$ZO_ROOT_USER_PASSWORD" https://${TEST_HOST}/api/default/streams | grep -q ci_logs'
    ...    return_stdout=False    return_rc=True
    Should Be Equal As Integers    ${rc}    0
