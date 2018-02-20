#!/bin/bash

if [ ! -z "${ENABLE_DEBUG}" ] && [ "${ENABLE_DEBUG}" -eq 1 ];
then
  set -x
fi

GITHUB_USERNAME=${GITHUB_USERNAME:-NTTCom-MS}
REPOBASEDIR=${REPOBASEDIR:-/var/eyprepos}

API_URL_REPOLIST="https://api.github.com/users/${GITHUB_USERNAME}/repos?per_page=100"
API_URL_REPOINFO_BASE="https://api.github.com/repos/${GITHUB_USERNAME}"

function botsays()
{
  if [ ! -z "${TELEGRAMTOKEN}" ] && [ ! -z "${TELEGRAMCHATID}" ];
  then
    curl -s \
    -X POST \
    https://api.telegram.org/bot${TELEGRAMTOKEN}/sendMessage \
    -d text="${1}" \
    -d chat_id=$TELEGRAMCHATID
  fi
}

function paginar()
{
  REPO_LIST_HEADERS=$(curl -I "${API_URL_REPOLIST}&page=${PAGENUM}" 2>/dev/null)

  echo "${REPO_LIST_HEADERS}" | grep "HTTP/1.1 403 Forbidden"
  if [ $? -eq 0 ];
  then
    RESET_RATE_LIMIT=$(echo "${REPO_LIST_HEADERS}" | grep "^X-RateLimit-Reset" | awk '{ print $NF }' | grep -Eo "[0-9]*")
    CURRENT_TS=$(date +%s)

    if [ "${RESET_RATE_LIMIT}" -ge "${CURRENT_TS}" ];
    then
      let SLEEP_RATE_LIMIT=RESET_RATE_LIMIT-CURRENT_TS
    else
      SLEEP_RATE_LIMIT=10
    fi

    RANDOM_EXTRA_SLEEP=$(echo $RANDOM | grep -Eo "^[0-9]{2}")
    let SLEEP_RATE_LIMIT=SLEEP_RATE_LIMIT+RANDOM_EXTRA_SLEEP

    echo "rate limited, sleep: ${SLEEP_RATE_LIMIT}"
    sleep "${SLEEP_RATE_LIMIT}"
  fi

  REPOLIST_LINKS=$(echo "${REPO_LIST_HEADERS}" | grep "^Link" | head -n1)
  REPOLIST_NEXT=$(echo "${REPOLIST_LINKS}" | awk '{ print $2 }')
  REPOLIST_LAST=$(echo "${REPOLIST_LINKS}" | awk '{ print $4 }')
}

function tagrepo()
{
  REPO_URL=$1

  REPO_NAME=${REPO_URL##*/}
  REPO_NAME=${REPO_NAME%.*}

  echo ${REPO_NAME}
  cd ${REPOBASEDIR}

  if [ -d "${REPO_NAME}" ];
  then
    rm -fr "${REPOBASEDIR}/${REPO_NAME}"
  fi

  git clone ${REPO_URL}
  cd ${REPO_NAME}

  OWNER=$(git remote show origin | grep Fetch | awk '{ print $NF }' | rev | cut -f 2 -d/ | cut -f 1 -d: | rev)

  if [ -z "${OWNER}" ];
  then
    REPO_DISPLAY_NAME="${REPO_NAME}"
  else
    REPO_DISPLAY_NAME="${OWNER}/${REPO_NAME}"
  fi

  LATEST_COMMIT=$(git log -1 --pretty=format:%H)

  if [ ! -z "${LATEST_COMMIT}" ];
  then

   MODULE_VERSION=$(cat metadata.json  | grep '"version"' | awk '{ print $NF }' | cut -f2 -d\")

   if [ ! -z "${MODULE_VERSION}" ];
   then
     LIST_TAGS=$(git tag -l)

     if [ ! -z "${LIST_TAGS}" ];
     then
       echo "${LIST_TAGS}" | grep "^${MODULE_VERSION}\$" >/dev/null 2>&1
       if [ "$?" -ne "0" ];
       then
        # el tag no correspon a la versio actual
        # TODO: verifico que no existeixi el tag
        #  git tag -l | grep -E "\\b${VERSION}\\b"
        #  if [ $? -ne 0 ];
        #  then
        #  fi
        git tag "${MODULE_VERSION}" -m "$(date +%Y%m%d%H%M)"
        botsays "new tag for ${REPO_DISPLAY_NAME}: ${MODULE_VERSION}"
       else
         TAG_LATEST_COMMIT="$(git tag --points-at "${LATEST_COMMIT}" | grep "^${MODULE_VERSION}\$")"

         if [ -z "${TAG_LATEST_COMMIT}" ];
         then
           # no hi ha tag a lultim commit, reapuntem
           git tag -d "${MODULE_VERSION}"
           git push --delete origin "${MODULE_VERSION}"
           git tag "${MODULE_VERSION}" -m "$(date +%Y%m%d%H%M)"
           botsays "updated tag ${MODULE_VERSION} to latest commit for ${REPO_DISPLAY_NAME}:${MODULE_VERSION} -> ${LATEST_COMMIT}"
         fi
       fi

       # update latest tag
       echo "${LIST_TAGS}" | grep "^latest\$" >/dev/null 2>&1
       if [ "$?" -ne 0 ];
       then
         git tag latest -m "$(date +%Y%m%d%H%M)"
         botsays "new latest tag for ${REPO_DISPLAY_NAME} pointing to release ${MODULE_VERSION}"
       else
         TAG_LATEST_COMMIT="$(git tag --points-at "${LATEST_COMMIT}" | grep latest)"
         if [ -z "${TAG_LATEST_COMMIT}" ];
         then
           git tag -d latest
           git push --delete origin latest
           git tag latest -m "$(date +%Y%m%d%H%M)"
           botsays "updated latest tag to release ${REPO_DISPLAY_NAME}:${MODULE_VERSION}"
         fi
       fi
     else
       # no existeixen tags
       botsays "first tag for ${REPO_DISPLAY_NAME}:${MODULE_VERSION}"
       git tag "${MODULE_VERSION}" -m "$(date +%Y%m%d%H%M)"
     fi
   fi

  git push --follow-tags
  fi
}

function getrepolist()
{
  # curl -I https://api.github.com/users/NTTCom-MS/repos?per_page=100 2>/dev/null| grep ^Link:

  PAGENUM=1

  REPOLIST=$(curl "${API_URL_REPOLIST}&page=${PAGENUM}" 2>/dev/null | grep "ssh_url" | cut -f4 -d\" | grep -E "/${REPO_PATTERN}")

  paginar

  while [ "${REPOLIST_NEXT}" != "${REPOLIST_LAST}" ];
  do
    let PAGENUM=PAGENUM+1
    REPOLIST=$(echo -e "${REPOLIST}\n$(curl "${API_URL_REPOLIST}&page=${PAGENUM}" 2>/dev/null | grep "ssh_url" | cut -f4 -d\" | grep -E "/${REPO_PATTERN}")")

    paginar
  done

  let PAGENUM=PAGENUM+1
  REPOLIST=$(echo -e "${REPOLIST}\n$(curl "${API_URL_REPOLIST}&page=${PAGENUM}" 2>/dev/null | grep "ssh_url" | cut -f4 -d\" | grep -E "/${REPO_PATTERN}")")
}

mkdir -p ${REPOBASEDIR}

git config --global user.email "${BOT_EMAIL}"
git config --global user.name "${BOT_NAME}"

if [ -z "$1" ];
then
  getrepolist

  echo "start: $(date)"
  for REPO_URL in ${REPOLIST};
  do
    tagrepo "${REPO_URL}"
    sleep $(echo $RANDOM | grep -Eo "^[0-9]{2}")
  done
  echo "end: $(date)"
else
  # un sol repo

  #GET /repos/:owner/:repo
  #API_URL_REPOINFO_BASE="https://api.github.com/repos/${GITHUB_USERNAME}"
  REPO_URL=$(curl "${API_URL_REPOINFO_BASE}/${1}" 2>/dev/null | grep "ssh_url" | cut -f4 -d\")

  if [ -z "${REPO_URL}" ];
  then
    REPO_INFO_HEADERS=$(curl -I "${API_URL_REPOINFO_BASE}/${1}" 2>/dev/null)

    echo "${REPO_INFO_HEADERS}" | grep "HTTP/1.1 403 Forbidden"
    if [ $? -eq 0 ];
    then
      RESET_RATE_LIMIT=$(echo "${REPO_INFO_HEADERS}" | grep "^X-RateLimit-Reset" | awk '{ print $NF }' | grep -Eo "[0-9]*")
      CURRENT_TS=$(date +%s)

      if [ "${RESET_RATE_LIMIT}" -ge "${CURRENT_TS}" ];
      then
        let SLEEP_RATE_LIMIT=RESET_RATE_LIMIT-CURRENT_TS
      else
        SLEEP_RATE_LIMIT=10
      fi

      RANDOM_EXTRA_SLEEP=$(echo $RANDOM | grep -Eo "^[0-9]{2}")
      let SLEEP_RATE_LIMIT=SLEEP_RATE_LIMIT+RANDOM_EXTRA_SLEEP

      echo "rate limited, sleep: ${SLEEP_RATE_LIMIT}"
      sleep "${SLEEP_RATE_LIMIT}"
    fi
  fi

  tagrepo "${REPO_URL}"
fi

exit 0
