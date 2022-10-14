#!/bin/bash
#This script will install docker , docker compose and initialize local docker local registry
# written by Moran Guy
GREEN='\033[0;32m'
NC='\033[0m'

set -e
set -u 

group="docker"

if grep -q $group /etc/group
then
    echo "${group} permissions cofigured!"
else
    echo "${group} does not exist"
    echo "configure docker permissions..."
    echo "please re run the script"
    sudo groupadd docker
    sudo usermod -aG docker $USER
    newgrp docker
fi

#*** installing docker
function install-docker {
        if [ -x "$(command -v docker)" ]
        then
                echo "Dockder already installed"
        else
                echo  -e "${GREEN} installing docker ${NC}"
                sudo apt update
                sudo apt install -y ca-certificates curl gnupg lsb-release
                curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
                sudo apt-get update
                sudo DEBIAN_FRONTEND=noninteractive apt-get -y install docker-ce docker-ce-cli containerd.io > /dev/null
        fi
}

#*** installing docker-compose
function install-docker-compose {
        echo  -e "${GREEN} installing docker-compose ${NC}"
        sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
        cd $registry_name
        docker-compose up -d
        sleep 5  
        if pgrep -x "registry" >/dev/null 
        then
          echo "docker-compose is up and running"
        else
          echo "docker-compose is not running"
        fi
}


echo "Please enter local registry name ?"
read registry_name
echo "Please enter local domain name for registry?"
read domain

mkdir $registry_name
mkdir -p $registry_name/data


cat <<EOF > $registry_name/docker-compose.yaml
services:
#Registry
  registry:
    image: registry:2
    restart: always
    ports:
    - "5000:5000"
    environment:
      REGISTRY_STORAGE_FILESYSTEM_ROOTDIRECTORY: /data
    volumes:
      - ./data:/data
    networks:
      - mynet

#Docker Networks
networks:
  mynet:
    driver: bridge

#Volumes
volumes:
  myregistrydata:
    driver: local
EOF

install-docker
install-docker-compose


cat <<EOF > /etc/docker/daemon.json
{
  "insecure-registries" : ["$registry_name.$domain:5000"]
}
EOF

systemctl restart docker
sleep 5
if pgrep -x "dockerd" >/dev/null 
then
  echo "docker is up and running"
else
  echo "docker is not running"
fi

ip_addr=`hostname -I | awk '{print $1}'`

echo "***Installation has been completed***"
echo 
echo "*********************************************"
echo
echo "Please add A record $registry_name.$domain pointing to $ip_addr to your DNS"
echo
echo
echo 'For k8s please add /etc/docker/daemon.json on each node of the cluster as below :'
echo
cat <<EOF
{
  "insecure-registries" : ["$registry_name.$domain:5000"]
}
EOF
echo
echo
echo 'For openshift please run oc edit image.config.openshift.io/cluster and add the following :'
echo

cat <<EOF
spec:
  additionalTrustedCA:
    name: registry-config
  registrySources:
    insecureRegistries:
    - $registry_name.$domain:5000
EOF




