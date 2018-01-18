#!/bin/bash

mkdir -p /var/eyprepos

GITHUB_USERNAME=${GITHUB_USERNAME:-NTTCom-MS}

REPOLIST=$(curl https://api.github.com/users/${GITHUB_USERNAME}/repos 2>/dev/null | grep "ssh_url" | cut -f4 -d\" | grep -E "/${REPO_PATTERN}")

for REPO_URL in ${REPOLIST};
do
  REPO_NAME=${REPO_URL##*/}
  REPO_NAME=${REPO_NAME%.*}

  echo $REPO_NAME
  cd /var/eyprepos
  git clone $REPO_URL

  cd $REPO_NAME

  LATEST_COMMIT=$(git log -1 --pretty=format:%H)

  if [ ! -z "${LATEST_COMMIT}" ];
  then

   MODULE_VERSION=$(cat metadata.json  | grep '"version"' | awk '{ print $NF }' | cut -f2 -d\")

   if [ ! -z "${MODULE_VERSION}" ];
   then
     LATEST_TAG=$(git tag -l -n 1)

     if [ ! -z "${LATEST_TAG}" ];
     then
       if [ "${LATEST_TAG}"!="${MODULE_VERSION}" ];
       then
        # el tag no correspon a la versio actual
        # TODO: verifico que no existeixi el tag
        #  git tag -l | grep -E "\\b${VERSION}\\b"
        #  if [ $? -ne 0 ];
        #  then
        #  fi
        git tag "${MODULE_VERSION}" -m "$(date +%Y%m%d%H%M)"
       else
         TAG_LATEST_COMMIT=$(git tag --points-at "${LATEST_COMMIT}")

         if [ "${TAG_LATEST_COMMIT}"!="${LATEST_COMMIT}"];
         then
           # tag no apunta al ultim commit, eliminar tag i tornat a apuntar
           git tag -d "${MODULE_VERSION}"
           git tag "${MODULE_VERSION}" -m "$(date +%Y%m%d%H%M)"
         fi
       fi
     else
       # no existeixen tags
       git tag "${MODULE_VERSION}" -m "$(date +%Y%m%d%H%M)"
     fi
   fi
  fi
done

exit 0
