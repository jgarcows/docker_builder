#!/bin/bash

#********************************************************************************
# Copyright 2014 IBM
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#********************************************************************************

#############
# Colors    #
#############
export green='\e[0;32m'
export red='\e[0;31m'
export label_color='\e[0;33m'
export no_color='\e[0m' # No Color

##################################################
# Simple function to only run command if DEBUG=1 # 
### ###############################################
debugme() {
  [[ $DEBUG = 1 ]] && "$@" || :
}
export -f debugme 

if [ $DEBUG = 1 ]; then 
    export ICE_ARGS="--verbose"
else
    export ICE_ARGS=""
fi 

set +e
set +x 

###############################
# Configure extension PATH    #
###############################
if [ -n $EXT_DIR ]; then 
    export PATH=$EXT_DIR:$PATH
fi 

########################
# REGISTRY INFORMATION #
########################
if [ -z $REGISTRY_URL ]; then
    echo -e "${red}Please set REGISTRY_URL in the environment${no_color}"
    exit 1
fi
########################
# Fix timestamps 
########################

echo "Current working directory and contents:"
pwd 
ls -la 

echo "updating timestamps to match the git commit time"
get_file_rev() {
    git rev-list -n 1 HEAD "$1"
}

update_file_timestamp() {
    file_time=`git show --pretty=format:%ai --abbrev-commit "$(get_file_rev "$1")" | head -n 1`
    touch -d "$file_time" "$1"
}

old_ifs=$IFS
IFS=$'\n' 
for file in $(git ls-files)
do
    update_file_timestamp "${file}"
done
IFS=$old_ifs
echo "New timestamps"
pwd 
ls -la 
echo "Done"


################################
# Application Name and Version #
################################
# The build number for the builder is used for the version in the image tag 
# For deployers this information is stored in the $BUILD_SELECTOR variable and can be pulled out
if [ -z "$APPLICATION_VERSION" ]; then
    export SELECTED_BUILD=$(grep -Eo '[0-9]{1,100}' <<< "${BUILD_SELECTOR}")
    if [ -z $SELECTED_BUILD ]
    then 
        if [ -z $BUILD_NUMBER ]
        then 
            export APPLICATION_VERSION=$(date +%s)
        else 
            export APPLICATION_VERSION=$BUILD_NUMBER    
        fi
    else
        export APPLICATION_VERSION=$SELECTED_BUILD
    fi 
fi 
echo "APPLICATION_VERSION: $APPLICATION_VERSION"

if [ -z $APPLICATION_NAME ]; then 
    echo -e "${red}setting application name to helloworld, please set APPLICATION_NAME in the environment to desired name ${no_color}"
    exit 1
fi 

################################
# Setup archive information    #
################################
if [ -z $WORKSPACE ]; then 
    echo -e "${red}Please set WORKSPACE in the environment${no_color}"
    exit 1
fi 

if [ -z $ARCHIVE_DIR ]; then 
    echo "${label_color}ARCHIVE_DIR was not set, setting to WORKSPACE/archive ${no_color}"
    export ARCHIVE_DIR="${WORKSPACE}"
fi 

if [ -d $ARCHIVE_DIR ]; then
  echo "Archiving to $ARCHIVE_DIR"
else 
  echo "Creating archive directory $ARCHIVE_DIR"
  mkdir $ARCHIVE_DIR 
fi 
export LOG_DIR=$ARCHIVE_DIR

######################
# Install ICE CLI    #
######################
echo "Installing IBM Container Service CLI"
ice help &> /dev/null
RESULT=$?
if [ $RESULT -ne 0 ]; then
    pushd . 
    cd $EXT_DIR
    sudo apt-get update &> /dev/null
    sudo apt-get -y install python2.7 &> /dev/null
    python --version 
    python get-pip.py --user &> /dev/null
    export PATH=$PATH:~/.local/bin
    echo "Installing patched CLI"
    pip install --user icecli-2.0-patch.zip
    #pip install --user icecli-2.0.zip
    ice help &> /dev/null
    RESULT=$?
    if [ $RESULT -ne 0 ]; then
        echo -e "${red}Failed to install IBM Container Service CLI ${no_color}"
        debugme python --version
        exit $RESULT
    fi
    popd 
    echo -e "${label_color}Successfully installed IBM Container Service CLI ${no_color}"
fi 

#############################
# Install Cloud Foundry CLI #
#############################
cf help &> /dev/null
RESULT=$?
if [ $RESULT -ne 0 ]; then
    echo "Installing Cloud Foundry CLI"
    pushd . 
    cd $EXT_DIR 
    gunzip cf-linux-amd64.tgz &> /dev/null
    tar -xvf cf-linux-amd64.tar  &> /dev/null
    cf help &> /dev/null
    RESULT=$?
    if [ $RESULT -ne 0 ]; then
        echo -e "${red}Could not install the cloud foundry CLI ${no_color}"
        exit 1
    fi  
    popd
    echo -e "${label_color}Successfully installed Cloud Foundry CLI ${no_color}"
fi 

#################################
# Set Bluemix Host Information  #
#################################
if [ -n "$BLUEMIX_TARGET" ]; then
    if [ "$BLUEMIX_TARGET" == "staging" ]; then 
        export CCS_API_HOST="api-ice.stage1.ng.bluemix.net" 
        export CCS_REGISTRY_HOST="registry-ice.stage1.ng.bluemix.net"
        export BLUEMIX_API_HOST="api.stage1.ng.bluemix.net"
        export ICE_CFG="ice-cfg-staging.ini"
    elif [ "$BLUEMIX_TARGET" == "prod" ]; then 
        echo -e "Targetting production Bluemix"
        export CCS_API_HOST="api-ice.ng.bluemix.net" 
        export CCS_REGISTRY_HOST="registry-ice.ng.bluemix.net"
        export BLUEMIX_API_HOST="api.ng.bluemix.net"
        export ICE_CFG="ice-cfg-prod.ini"
    else 
        echo -e "${red}Unknown Bluemix environment specified"
    fi 
else 
    echo -e "Targetting production Bluemix"
    export CCS_API_HOST="api-ice.ng.bluemix.net" 
    export CCS_REGISTRY_HOST="registry-ice.ng.bluemix.net"
    export BLUEMIX_API_HOST="api.ng.bluemix.net"
    export ICE_CFG="ice-cfg-prod.ini"

fi  

################################
# Login to Container Service   #
################################
if [ -n "$API_KEY" ]; then 
    echo -e "${label_color}Logging on with API_KEY${no_color}"
    debugme echo "Login command: ice $ICE_ARGS login --key ${API_KEY}"
    #ice $ICE_ARGS login --key ${API_KEY} --host ${CCS_API_HOST} --registry ${CCS_REGISTRY_HOST} --api ${BLUEMIX_API_HOST} 
    ice $ICE_ARGS login --key ${API_KEY}
    RESULT=$?
elif [ -n "$BLUEMIX_TARGET" ] || [ ! -f ~/.cf/config.json ]; then
    # need to gather information from the environment 
    # Get the Bluemix user and password information 
    if [ -z "$BLUEMIX_USER" ]; then 
        echo -e "${red} Please set BLUEMIX_USER on environment ${no_color} "
        exit 1
    fi 
    if [ -z "$BLUEMIX_PASSWORD" ]; then 
        echo -e "${red} Please set BLUEMIX_PASSWORD as an environment property environment ${no_color} "
        exit 1 
    fi 
    if [ -z "$BLUEMIX_ORG" ]; then 
        export BLUEMIX_ORG=$BLUEMIX_USER
        echo -e "${label_color} Using ${BLUEMIX_ORG} for Bluemix organization, please set BLUEMIX_ORG if on the environment if you wish to change this. ${no_color} "
    fi 
    if [ -z "$BLUEMIX_SPACE" ]; then
        export BLUEMIX_SPACE="dev"
        echo -e "${label_color} Using ${BLUEMIX_SPACE} for Bluemix space, please set BLUEMIX_SPACE if on the environment if you wish to change this. ${no_color} "
    fi 
    echo -e "${label_color}Targetting information.  Can be updated by setting environment variables${no_color}"
    echo "BLUEMIX_USER: ${BLUEMIX_SPACE}"
    echo "BLUEMIX_SPACE: ${BLUEMIX_SPACE}"
    echo "BLUEMIX_ORG: ${BLUEMIX_ORG}"
    echo "BLUEMIX_PASSWORD: xxxxx"
    echo ""
    echo -e "${label_color}Logging in to Bluemix and IBM Container Service using environment properties${no_color}"
    debugme echo "login command: ice $ICE_ARGS login --cf --host ${CCS_API_HOST} --registry ${CCS_REGISTRY_HOST} --api ${BLUEMIX_API_HOST} --user ${BLUEMIX_USER} --psswd ${BLUEMIX_PASSWORD} --org ${BLUEMIX_ORG} --space ${BLUEMIX_SPACE}"
    ice $ICE_ARGS login --cf --host ${CCS_API_HOST} --registry ${CCS_REGISTRY_HOST} --api ${BLUEMIX_API_HOST} --user ${BLUEMIX_USER} --psswd ${BLUEMIX_PASSWORD} --org ${BLUEMIX_ORG} --space ${BLUEMIX_SPACE} 
    RESULT=$?
else 
    # we are already logged in.  Simply check via ice command 
    echo -e "${label_color}Logging into IBM Container Service using credentials passed from IBM DevOps Services ${no_color}"
    mkdir -p ~/.ice
    echo "Copying ${EXT_DIR}/${ICE_CFG}"
    debugme more "${EXT_DIR}/${ICE_CFG}"
    cp ${EXT_DIR}/${ICE_CFG} ~/.ice/ice-cfg.ini

    debugme more ~/.ice/ice-cfg.ini
    debugme more ~/.cf/config.json

    ice --verbose ps > ps.log 
    debugme cat ps.log 
    RESULT=$?
    if [ $RESULT -ne 0 ]; then
        echo "checking login to registry server" 
        ice images &> /dev/null
        RESULT=$? 
    fi 
fi 

# check login result 
if [ $RESULT -eq 1 ]; then
    echo -e "${red}Failed to login to IBM Container Service${no_color}"
    exit $RESULT
else 
    echo -e "${green}Successfully logged into IBM Container Service${no_color}"
    ice info 
fi 

echo -e "${label_color}Initialization complete${no_color}"