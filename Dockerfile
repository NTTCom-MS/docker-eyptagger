FROM centos:centos7
MAINTAINER Jordi Prats

ENV HOME /root
ENV GITHUB_USERNAME NTTCom-MS
ENV REPO_PATTERN eyp-

ENV BOT_EMAIL "bot@nttcom.ms"
ENV BOT_NAME "Tag Bot"

RUN yum install epel-release -y
RUN yum install git -y
RUN yum install curl -y

RUN mkdir -p /var/eyprepos /usr/bin

COPY updatetags.sh /usr/bin/updatetags.sh

VOLUME ["/var/eyprepos"]
VOLUME ["/root/.ssh"]

CMD /bin/bash /usr/bin/updatetags.sh
