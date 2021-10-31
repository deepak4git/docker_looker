#!/usr/bin/env bash

setHostname() {
    # If we're in ECS land, lets get host name from the meta data on the ec2 node
    if [[ ! -z "${ECS_CONTAINER_METADATA_FILE}" ]]; then
        _HOSTNAME=$(curl -s -XGET http://169.254.169.254/latest/meta-data/local-hostname)
    else
        _HOSTNAME=${HOSTNAME:-$(hostname)}
    fi

    hostname ${_HOSTNAME}
}

function check_for_error() {
  RC=$1
  MESSAGE=$2
  if [ $1 -ne 0 ]; then
    echo "[entrypoint.sh] ERROR: RC=$RC $MESSAGE"
  fi
}

function check_for_error_with_exit() {
  RC=$1
  MESSAGE=$2
  if [ $1 -ne 0 ]; then
    echo "[entrypoint.sh] ERROR: RC=$RC $MESSAGE"
    exit $RC
  fi
}

# single log point to standardize format, and eventually generate json
function entrypoint_log() {
  echo "[entrypoint.sh] $@"
}


function set_aws_region() {
  # entrypoint_log "Checking AWS_SM_REGION..."
  WGET_TIMEOUT=1
  AWS_ZONE=$(wget --timeout=$WGET_TIMEOUT http://169.254.169.254/latest/meta-data/placement/availability-zone/ -q -O -)
  check_for_error $? "wget to detect availability zone failed"
  export AWS_REGION=${AWS_ZONE%?}
  entrypoint_log "AWS_REGION=$AWS_REGION"
}

function set_secret_name(){
  export SECRET_NAME=$AWSSM_NAME
}

function set_looker_db(){
 #RDS_PWD=`aws secretsmanager get-secret-value --secret-id ${SECRET_NAME} --region ${AWS_REGION} | jq .SecretString -r | jq .MYSQL_ROOT_PASSWORD -r`
 #RDS_USER=`aws secretsmanager get-secret-value --secret-id ${SECRET_NAME} --region ${AWS_REGION} | jq .SecretString -r | jq .MYSQL_USER -r`
 #RDS_DB=`aws secretsmanager get-secret-value --secret-id ${SECRET_NAME} --region ${AWS_REGION} | jq .SecretString -r | jq .MYSQL_DATABASE -r`
 #RDS_HOST=`aws secretsmanager get-secret-value --secret-id ${SECRET_NAME} --region ${AWS_REGION} | jq .SecretString -r | jq .MYSQL_HOST -r`
 RDS_PWD="lookerpoc#123"
 RDS_USER="admin"
 RDS_DB="looker"
 RDS_HOST="looker-appliance-poc.cvzfewnan2km.us-east-1.rds.amazonaws.com"
 export LOOKER_DB="dialect=mysql&host=${RDS_HOST}&username=${RDS_USER}&password=${RDS_PWD}&database=${RDS_DB}&port=3306"
}
_HOSTNAME=""
setHostname

echo "hostname:[${_HOSTNAME}]"
echo "Current user"
whoami
set_aws_region
set_secret_name
set_looker_db

# dynamic looker args created at run time for the container.
# this is needed for proper clustering.
if [[ "$(cat /home/looker/looker/lookerstart.cfg)" != *"--hostname"* ]]; then
    echo "[Appending hostname]::[${_HOSTNAME}]::[/home/looker/looker/lookerstart.cfg]"
    echo "" >> /home/looker/looker/lookerstart.cfg
    echo "LOOKERARGS=\"\${LOOKERARGS} --hostname=${_HOSTNAME}\"" >> /home/looker/looker/lookerstart.cfg
fi

# the exit process isn't cleaning itself up, so we'll purge these if we see them.
if [[ -f "/home/looker/looker/.deploying" ]]; then
    echo "Removing [/home/looker/looker/.deploying] file"
    rm /home/looker/looker/.deploying
fi

if [[ -f "/home/looker/looker/.starting" ]]; then
    echo "Removing [/home/looker/looker/.starting] file"
    rm /home/looker/looker/.starting
fi

echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo "starting up container for [looker] service"

echo "[startup args configured]++++++++++++++++++++++++++++++++++++++"
cat /home/looker/looker/lookerstart.cfg

echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo "Permisssion the volume mount"

echo "[chown -R looker:looker /srv/data/looker]++++++++++++++++++++++"
# /srv is owned by root:root out of the box. Add looker:looker /srv/data because Looker expects to write data to this volume
chown -R looker:looker /srv/data
exec $@
