#!/bin/bash
# Install Initial Node of a Molecule
# Written for RHEL 7, RHEL 8, Ubuntu, and AWS Linux 2
# Based off of https://github.com/OfficialBoomi/boomicicd-cli

properties () {
    # Local References
    export LOCALBOOMI=/boomi/local
    # Local directory reference where temp, work and java will reside ... will be created as a part of the automation
    export LOCALWORKINGDIR=/boomi/local/work
    # Local Boomi working directory ... will be created as a part of the automation
    export LOCALTEMPDIR=/boomi/local/tmp
    # Local Container working directory used for local jar file copies... will be created as a part of the automation
    export LOCALCONTAINERDIR=/boomi/local/container
    # Local Boomi temp directory ... will be created as a part of the automation
    export LOCALJAVADIR=/apps/products/jdk
    # Local Boomi JDK directory ... will be created as a part of the automation
    export LOCALJREDIR=/apps/products/jdk/jre
    # Local Boomi JRE directory ... will be created as a part of the automation
    export INSTALL_DIR=/boomi/share/molecule
    # The Boomi Molecule will be installed at this directory
    export MOUNT=/boomi/share
    # Mount point which is used for sysctl
    export FILESHAREDNS=<efs-dns>.efs.us-east-1.amazonaws.com
    # DNS for EFS fileshare. Used to add to /etc/fstab
    export SERVICE_ACCOUNT=boomi
    # Service Account Name
    export SERVICE_ACCOUNT_PWD=ChangePassword1234
    # Service Account Password

    # Boomi Account Properties
    export accountId="<boomi-account-id>"
    # Your  Account ID to which the Molecule will be installed
    export authToken="BOOMI_TOKEN.<user-name>:<api-token>"
    # Parent Account Authorization (using an Atomsphere API Token)
    export baseURL=https://api.boomi.com/api/rest/v1/$accountId

    # Molecule Properties
    export atomType="MOLECULE"
    export atomName="molecule_test"
    # Name of the Molecule. Do not use dashes.
    export environmentId=<environment-id>
    # Environment to attach the Runtime to
    export classification=TEST
    # TEST or PROD environment classification
    export ATOM_HOME=$INSTALL_DIR/Molecule_$atomName
    export HEAP_SPACE=512m
    # Set heap space. eg. 512m or 4g

    # For shared web URL
    export sharedWebURL="https:\/\/helloworld.com"
    # Load Balancer URL for the parent cloud
    export apiType="advanced"
    # API Type of the Shared Web Server
    export apiAuth="basic"
    # API Auth of the Shared Web Server
    export httpPort=9090
    # Set to the port yoou would like Jetty to initialize on OOTB

    # Other Boomi properties
    export ATOM_HOME=${INSTALL_DIR}/Molecule_${atomName}
    # ATOM_HOME as previously mentioned in the INSTALL_DIR variable

    # Code Constants
    export h1="Content-Type: application/json"
    # Do not set
    export h2="Accept: application/json"
    # Do not set

}

getPackageManager () {
    if [ -x "$(command -v apt-get)" ]; 
        then 
        echo "apt-get"
    elif [ -x "$(command -v dnf)" ];     
        then 
        echo "dnf"
    elif [ -x "$(command -v yum)" ];     
        then 
        echo "yum"
    else echo "FAILED TO INSTALL: Package manager not found.">&2; fi
}

packageUpdate () {

    if [ -x "$(command -v apt-get)" ]; 
        then 
        sudo apt-get update -y && sudo apt-get upgrade -y
    elif [ -x "$(command -v dnf)" ];     
        then 
        sudo dnf update -y
    elif [ -x "$(command -v yum)" ];     
        then 
        sudo yum update -y
    fi

}

mountEBS () {

    printf "Mounting EBS..."
    DISKTOMOUNT=$(lsblk --fs --json |
    jq -r '.blockdevices[] | select(.children == null and .fstype == null) | .name')

    if [ ! -z "$DISKTOMOUNT" ]
    then
        sudo mkfs -t xfs /dev/$DISKTOMOUNT
        DISKTOMOUNTUUID=$(lsblk --fs --json |
        jq -r --arg DISKTOMOUNT "$diskToMount" '.blockdevices[] | select(.name==$DISKTOMOUNT) | .uuid')

        echo -e "UUID=$DISKTOMOUNTUUID\t$LOCALBOOMI\txfs\tdefaults,nofail\t0 2" >> sudo tee -a /etc/fstab    
        sudo mount -a
    fi

}


mountEFS () {

    println "Mounting EFS..."
    if [ $PACKAGE_MANAGER == "apt-get" ] 
    then 
        sudo apt-get install -y nfs-common
    fi
    if [ $PACKAGE_MANAGER == "yum" ] 
    then
        sudo yum install -y nfs-utils
    fi
    if [ $PACKAGE_MANAGER == "dnf" ] 
    then
        sudo dnf install -y nfs-utils
    fi

    # Mount EFS
    if grep -Fwq "$FILESHAREDNS" /etc/fstab
    then
        echo "EFS has already been mounted, skipping..."
    else
        echo -e "$FILESHAREDNS:/\t$MOUNT\tnfs4\tnfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport" | sudo tee -a /etc/fstab
        sudo mount -a
    fi

}


osPrep () {

    properties
    # Create service account
    sudo adduser -p $SERVICE_ACCOUNT_PWD $SERVICE_ACCOUNT

    #Modify Boomi User Limits
    printf "\nShell script is overriding default Boomi User Limits \n"
    if grep -Fxq "$SERVICE_ACCOUNT soft nproc 65535" /etc/security/limits.conf
    then
            echo "Soft nproc already overriden, skipping ..."
    else
            echo '$SERVICE_ACCOUNT soft nproc 65535' | sudo tee -a /etc/security/limits.conf
    fi
    if grep -Fxq "$SERVICE_ACCOUNT hard nproc 65535" /etc/security/limits.conf
    then
            echo "Hard nproc already overriden, skipping ..."
    else
            echo '$SERVICE_ACCOUNT hard nproc 65535' | sudo tee -a /etc/security/limits.conf
    fi
    if grep -Fxq "$SERVICE_ACCOUNT soft nofile 65535" /etc/security/limits.conf
    then
            echo "Soft nofile already overriden, skipping ..."
    else
            echo '$SERVICE_ACCOUNT soft nofile 65535' | sudo tee -a /etc/security/limits.conf
    fi
    if grep -Fxq "$SERVICE_ACCOUNT hard nofile 65535" /etc/security/limits.conf
    then
            echo "Hard nofile already overriden, skipping ..."
    else
            echo '$SERVICE_ACCOUNT hard nofile 65535' | sudo tee -a /etc/security/limits.conf
    fi

    # Set Firewall rules with firewalld
    sudo $PACKAGE_MANAGER install -y firewalld
    sudo systemctl enable firewalld
    sudo systemctl start firewalld
    printf "\nShell script is setting firewall ports \n"
    sudo firewall-cmd --permanent --add-port 5002/tcp
    sudo firewall-cmd --permanent --add-port 7800/tcp
    sudo firewall-cmd --permanent --add-port 9090/tcp
    # Port 61717 is only reqired if using Atom Queues
    sudo firewall-cmd --permanent --add-port 61717/tcp

    #Making directory and changing permission set as well as local work/temp
    sudo mkdir -p ${LOCALWORKINGDIR}
    sudo mkdir -p ${LOCALTEMPDIR}
    sudo mkdir -p ${INSTALL_DIR}

    sudo chown -R $SERVICE_ACCOUNT:$SERVICE_ACCOUNT ${LOCALBOOMI}

}


installMolecule () {

    properties
    tokenId=$(getInstallerToken)

    cd /tmp
    curl https://platform.boomi.com/atom/molecule_install64.sh -o molecule_install64.sh
    chmod +x /tmp/molecule_install64.sh

    # Add logic to only add node if ./atom exists 
    sudo ./molecule_install64.sh -q -console  \
    -VinstallToken=$tokenId \
    -VenvironmentId=$environmentId \
    -dir ${INSTALL_DIR} \
    -VatomName=$atomName \
    -VlocalPath=${LOCALWORKINGDIR} \
    -VlocalTempPath=${LOCALTEMPDIR} \
    -dir ${INSTALL_DIR} 

    # Update Advanced and Custom Properties
    echo "com.boomi.container.cloudlet.clusterConfig=UNICAST" | sudo tee -a $ATOM_HOME/conf/container.properties
    echo "com.boomi.container.dataDirNestLevel=2" | sudo tee -a $ATOM_HOME/conf/container.properties
    echo "com.boomi.container.executionDirNestLevel=2" | sudo tee -a $ATOM_HOME/conf/container.properties
    echo "com.boomi.container.pendingShutdownWarnTime=15000" | sudo tee -a $ATOM_HOME/conf/container.properties
    echo "-XX:+HeapDumpOnOutOfMemoryError" | sudo tee -a $ATOM_HOME/bin/atom.vmoptions
    echo "-Xmx$HEAP_SPACE" | sudo tee -a $ATOM_HOME/bin/atom.vmoptions
    echo "-XX:+ParallelRefProcEnabled" | sudo tee -a $ATOM_HOME/bin/atom.vmoptions
    echo "-XX:+UseStringDeduplication" | sudo tee -a $ATOM_HOME/bin/atom.vmoptions
    echo "-Dcom.sun.management.jmxremote.authenticate=false" | sudo tee -a $ATOM_HOME/bin/atom.vmoptions
    echo "-Dcom.sun.management.jmxremote.port=5002" | sudo tee -a $ATOM_HOME/bin/atom.vmoptions
    echo "-Dcom.sun.management.jmxremote.ssl=false" | sudo tee -a $ATOM_HOME/bin/atom.vmoptions
    echo "-Dcom.sun.management.jmxremote.rmi.port=5002" | sudo tee -a $ATOM_HOME/bin/atom.vmoptions
    if [ $classification == 'TEST' ]
    then 
        echo "com.boomi.container.resource.heapDumpOnLowMemory=true" | sudo tee -a $ATOM_HOME/conf/container.properties
    fi
    if [ $LOCALCONTAINERDIR > '' ]
    then 
        echo "-Dcom.boomi.container.localWorkDir="$LOCALCONTAINERDIR | sudo tee -a $ATOM_HOME/bin/atom.vmoptions
    fi
    sudo ${ATOM_HOME}/bin/atom restart

}

setSharedWebServer () {
    printf "Configuring Shared Web Server Settings ..."
    properties

    # Get Molecule Id
    URL=$baseURL/Atom/query
    request="{\"QueryFilter\":{\"expression\":{\"argument\":[\"$atomName\"],\"operator\":\"EQUALS\",\"property\":\"name\"}}}"

    atomId=$(curl -s -X POST -u $authToken -H "${h1}" -H "${h2}" $URL -d $request | jq -r .result[0].id)

    # Update the Shared Web Server Settings
    URL=$baseURL/SharedServerInformation/$atomId/update
    request="{\"atomId\":\"$atomId\",\"url\":\"$sharedWebURL\",\"apiType\":\"$apiType\",\"auth\":\"$apiAuth\",\"overrideUrl\":$overrideUrl,\"httpPort\":\"$httpPort\"}"
    curl -s -X POST -u $authToken -H "${h1}" -H "${h2}" $URL -d $request 

}


changeOwner () {

    properties
    cd "$ATOM_HOME/bin"
    ./atom stop
    printf "Sleeping to ensure the runtime is fully down ..."
    sleep 15
    printf "Changing ownership ... \n"
    sudo chown -R boomi:boomi $INSTALL_DIR
    sudo -u boomi ./atom start

}

setSysctl () {
    properties
    # cd /tmp
    runtime="molecule"
    sudo touch /etc/systemd/system/${runtime}.service
    sudo chmod 777 /etc/systemd/system/${runtime}.service
    # chmod 777 ${runtime}.service
    echo  "[Unit]
    Documentation=man:systemd-sysv-generator(8)
    Description=LSB: Molecule
    After=local-fs.target network.target remote-fs.target nss-lookup.target ntpd.service

[Service]
    LimitNOFILE=65536
    LimitNPROC=65536
    Type=forking
    Restart=always
    TimeoutSec=5min
    IgnoreSIGPIPE=no
    KillMode=process
    GuessMainPID=yes
    RemainAfterExit=yes
    ExecStart=${ATOM_HOME}/bin/atom start
    ExecStop=${ATOM_HOME}/bin/atom stop
    ExecReload=${ATOM_HOME}/bin/atom restart
    User=${SERVICE_ACCOUNT}
    Group=${SERVICE_ACCOUNT}

[Install]
    WantedBy=multi-user.target" | sudo tee /etc/systemd/system/${runtime}.service
    

    echo "Disabling SELinux..."
    sudo setenforce 0

    sudo systemctl daemon-reload
    sudo systemctl enable ${runtime}
    sleep 5
    sudo systemctl start ${runtime}

    if [ -f "/etc/sudoer.d/boomi" ]
    then 
        echo "/etc/sudoer.d/boomi file is already created."
    else 
        sudo touch /etc/sudoers.d/boomi
    fi


    # Give service account user permission to run systemctl on following files
    if sudo grep -Fxq "$SERVICE_ACCOUNT ALL=NOPASSWD: /bin/systemctl start molecule" /etc/sudoers.d/boomi
    then
        echo "$SERVICE_ACCOUNT ALL=NOPASSWD: /bin/systemctl start molecule, skipping ..."
    else
        echo "$SERVICE_ACCOUNT ALL=NOPASSWD: /bin/systemctl start molecule" | sudo tee -a /etc/sudoers.d/boomi
    fi
    if sudo grep -Fxq "$SERVICE_ACCOUNT ALL=NOPASSWD: /bin/systemctl stop molecule" /etc/sudoers.d/boomi
    then
        echo "$SERVICE_ACCOUNT ALL=NOPASSWD: /bin/systemctl stop molecule, skipping ..."
    else
        echo "$SERVICE_ACCOUNT ALL=NOPASSWD: /bin/systemctl stop molecule" | sudo tee -a /etc/sudoers.d/boomi
    fi    
    if sudo grep -Fxq "$SERVICE_ACCOUNT ALL=NOPASSWD: /bin/systemctl restart molecule" /etc/sudoers.d/boomi
    then
        echo "$SERVICE_ACCOUNT ALL=NOPASSWD: /bin/systemctl restart molecule, skipping ..."
    else
        echo "$SERVICE_ACCOUNT ALL=NOPASSWD: /bin/systemctl restart molecule" | sudo tee -a /etc/sudoers.d/boomi
    fi    
    if sudo grep -Fxq "$SERVICE_ACCOUNT ALL=NOPASSWD: /bin/systemctl status molecule" /etc/sudoers.d/boomi
    then
        echo "$SERVICE_ACCOUNT ALL=NOPASSWD: /bin/systemctl status molecule, skipping ..."
    else
        echo "$SERVICE_ACCOUNT ALL=NOPASSWD: /bin/systemctl status molecule" | sudo tee -a /etc/sudoers.d/boomi
    fi    
    if sudo grep -Fxq "$SERVICE_ACCOUNT ALL=NOPASSWD: /bin/systemctl show -p ActiveState molecule" /etc/sudoers.d/boomi
    then
        echo "$SERVICE_ACCOUNT ALL=NOPASSWD: /bin/systemctl show -p ActiveState molecule, skipping ..."
    else
        echo "$SERVICE_ACCOUNT ALL=NOPASSWD: /bin/systemctl show -p ActiveState molecule" | sudo tee -a /etc/sudoers.d/boomi
    fi    
    if sudo grep -Fxq "$SERVICE_ACCOUNT ALL=NOPASSWD: /bin/systemctl show -p SubState molecule" /etc/sudoers.d/boomi
    then
        echo "$SERVICE_ACCOUNT ALL=NOPASSWD: /bin/systemctl show -p SubState molecule, skipping ..."
    else
        echo "$SERVICE_ACCOUNT ALL=NOPASSWD: /bin/systemctl show -p SubState molecule" | sudo tee -a /etc/sudoers.d/boomi
    fi
    if sudo grep -Fxq "$SERVICE_ACCOUNT ALL=NOPASSWD: /bin/systemctl show -p ExecMainPID molecule" /etc/sudoers.d/boomi
    then
        echo "$SERVICE_ACCOUNT ALL=NOPASSWD: /bin/systemctl show -p ExecMainPID molecule, skipping ..."
    else
        echo "$SERVICE_ACCOUNT ALL=NOPASSWD: /bin/systemctl show -p ExecMainPID molecule" | sudo tee -a /etc/sudoers.d/boomi
    fi

}

setRestartScript () {

    # Update restart script to use systemd
    {
    echo '#!/bin/sh
    # ENV variables
    # LOCALHOST_ID - set if script is invoked by a cluster node.
    # service_name - set based on systemd service definition file. e.g. "molecule" for "molecule.service"
    restart_log="restart\${LOCALHOST_ID}.log"
    service_name="molecule"

    service_start() {
        log_info "Starting Atom via systemd"
        sudo /bin/systemctl start \$service_name
        if [ \$returnCode -eq 0 ]; then
            log_info " > Successfully started Atom service (\$returnCode)"
        else
            log_warn " > Atom service not started (\$returnCode).. sleeping 5sec.."
            sleep 5
        fi
    }

    service_stop() {
        log_info "Stopping Atom via systemd"
        sudo /bin/systemctl stop \$service_name
        returnCode=$?
        if [ \$returnCode -eq 0 ]; then
            log_info " > Successfully stopped Atom service (\$returnCode)"
        else
            log_warn " > Atom service not stopped (\$returnCode).. sleeping 5sec.."
            sleep 5
        fi
    }

    service_status() {
        local status=1
        log_info "Checking systemd status"
        ActiveState=$(sudo /bin/systemctl show -p ActiveState \$service_name)
        log_info " > \$ActiveState"
        if [[ \$ActiveState = "ActiveState=active" ]]; then
            SubState=$(sudo /bin/systemctl show -p SubState \$service_name)
            log_info " > \$SubState"
            if [[ \$SubState = "SubState=running" ]]; then
                ExecMainPID=$(sudo /bin/systemctl show -p ExecMainPID \$service_name)
                log_info " > \$ExecMainPID"
                if [[ \$ExecMainPID = "ExecMainPID=0" ]]; then
                    log_warn " > Issue with PID detection identified. Please check the state of the Atom and systemd manually"
                fi
                status=0
            fi
        fi
        echo \$status
    }

    log_info() {
        log "[INFO]" "\$1"
    }

    log_err() {
        log "[ERROR]" "\$1"
    }

    log_warn() {
        log "[WARNING]" "\$1"
    }

    log() {
        datestring=$(date +'%Y-%m-%d %H:%M:%S')
        echo -e "\$datestring \$1: \$2" >>"\${restart_log}" 2>&1
    }

    echo "=====================================================================" >>"\${restart_log}" 2>&1
    log_info "Initiating shutdown sequence.."
    #Attempt shutdown via systemd
    service_stop
    #Check status of atom and if not stopped, try to stop it manually
    for i in 1 2 3 4 5; do
        log_info "Checking Atom Status (Attempt \$i)"
        returnMessage=$(./atom status)
        returnCode=\$?
        log_info " > \$returnMessage - Code: \$returnCode"
        if [ \$returnCode -ne 0 ]; then
            log_info " > Atom stopped successfully"
            atom_status="stopped"
            break
        else
            atom_status="running"
            log_info " > Atom still running.. sleeping 5sec.."
            sleep 5
        fi
        if [ \$atom_status != "stopped" ]; then
            log_info "Stopping Atom via atom command"
            returnMessage=$(./atom stop)
            returnCode=\$?
            log_info " > \$returnMessage - Code: \$returnCode"
        fi
    done
    if [ \$atom_status != "stopped" ]; then
        log_err "Failure to stop Atom, please check manually"
        exit 1
    fi

    log_info "Initiating startup sequence.."
    #Attempt start via systemd
    service_start

    #Check systemd service
    for i in 1 2 3 4 5; do
        service_status=$(service_status)
        if [[ \$service_status != 0 ]]; then
            log_err "Failed to start systemd service.. sleeping 5sec.."
            sleep 5
        else
            break
        fi
    done

    #Check atom. If not started attempt to start manually and then trigger systemd start again
    for i in 1 2 3 4 5; do
        log_info "Checking Atom Status (Attempt \$i)"
        returnMessage=$(./atom status)
        returnCode=\$?
        log_info " > \$returnMessage - Code: \$returnCode"
        if [ \$returnCode -eq 0 ]; then
            log_info " > Atom started successfully"
            atom_status="running"
            break
        else
            atom_status="stopped"
            log_info " > Atom not started yet.. sleeping 20sec.."
            sleep 20
        fi
    done
    if [ \$atom_status != "running" ]; then
        log_info "Starting Atom via atom command"
        returnMessage=$(./atom start)
        returnCode=\$?
        log_info "  > \$returnMessage - Code: \$returnCode"
    fi
    if [[ \$service_status -ne 0 && \$atom_status != "running" ]]; then
        log_err "Warning, something went wrong! Please check the state of the Atom and systemd manually as they may be out of sync"
    else
        log_info "Restart request completed successfully!"
    fi" |> \${ATOM_HOME}/bin/restart.sh' | sudo tee $ATOM_HOME/bin/restart.sh

    sudo chown boomi:boomi $ATOM_HOME/bin/restart.sh
    } > /dev/null
}

getInstallerToken () {

    properties
    URL=$baseURL/InstallerToken
    request="{\"installType\":\"$atomType\",\"durationMinutes\":30}"
    token=$(curl -s -X POST -u $authToken -H "${h1}" -H "${h2}" $URL -d $request | jq -r .token)
    echo $token

}

properties
PACKAGE_MANAGER="$(getPackageManager)"
packageUpdate
sudo $PACKAGE_MANAGER install -y jq

mountEBS
mountEFS
osPrep

installMolecule
setSharedWebServer
changeOwner
setSysctl
setRestartScript

