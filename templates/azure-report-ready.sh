#!/bin/bash
# Based on https://learn.microsoft.com/en-us/azure/virtual-machines/linux/no-agent#add-required-code-to-the-vm
# The goal of this script is to report to Azure that this VM is up and running in the right way. The IP address is hardcoded because it is the API of the Azure, https://learn.microsoft.com/en-us/azure/virtual-network/what-is-ip-address-168-63-129-16, which also states that the IP address will not change.

# The original script uses curl for making HTTP requests, however, curl is not installed on our K8S-OS. Therefore the following HTTP request will have to be done in the old way of writing each line in the HTTP request manually.
# The below loop is about fetching the goalstate of the VM along with other basic information. It will attempt five times before exiting with a failed exitcode.
attempts=1
until ((attempts > 5)); do
    echo "obtaining goal state - attempt $attempts"
    exec 3<>/dev/tcp/168.63.129.16/80
    echo -e "GET /machine/?comp=goalstate HTTP/1.1\r
Host: 168.63.129.16\r
User-Agent: curl/7.86.0\r
Accept: */*\r
x-ms-agent-name: azure-vm-register\r
Content-Type: text/xml;charset=utf-8\r
x-ms-version: 2012-11-30\r
Connection: close\r
\r" >&3
    goalstate=$( timeout 1 cat <&3 )
    
    if (($? == 0)); then
       echo "successfully retrieved goal state"
       retrieved_goal_state=true
       break
    fi
    
    # Close
    exec 3<&-

    sleep 5
    attempts=$((attempts+1))
done

if [ "$retrieved_goal_state" != "true" ]; then
    echo "failed to obtain goal state - cannot register this VM"
    exit 1
fi

# Modify the XML to contain the necessary information required by the next HTTP request
container_id=$(grep ContainerId <<< "$goalstate" | sed 's/\s*<\/*ContainerId>//g' | sed 's/\r$//')
instance_id=$(grep InstanceId <<< "$goalstate" | sed 's/\s*<\/*InstanceId>//g' | sed 's/\r$//')

ready_doc=$(cat << EOF
<?xml version="1.0" encoding="utf-8"?>
<Health xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
  <GoalStateIncarnation>1</GoalStateIncarnation>
  <Container>
    <ContainerId>$container_id</ContainerId>
    <RoleInstanceList>
      <Role>
        <InstanceId>$instance_id</InstanceId>
        <Health>
          <State>Ready</State>
        </Health>
      </Role>
    </RoleInstanceList>
  </Container>
</Health>
EOF
)

# Attempt to POST the above XML content to Azure in order to report ready.
attempts=1
until ((attempts > 5)); do
    exec 3<>/dev/tcp/168.63.129.16/80
    echo -e "POST /machine/?comp=health HTTP/1.1\r
Host: 168.63.129.16\r
User-Agent: curl/7.86.0\r
Accept: */*\r
x-ms-agent-name: azure-vm-register\r
Content-Type: text/xml;charset=utf-8\r
x-ms-version: 2012-11-30\r
Connection: close\r
Content-Length: ${#ready_doc}\r
\r
$ready_doc\r
\r" >&3
    timeout 1 cat <&3
    
    if (($? == 0)); then
       echo "successfully register with Azure"
       break
    fi

    # Close
    exec 3<&-

    sleep 5 # sleep to prevent throttling from wire server
done
