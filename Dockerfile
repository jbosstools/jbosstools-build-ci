FROM centos:centos7
MAINTAINER Jeff Maury <jmaury@redhat.com>

# install deps required by our build
RUN gpg2 --keyserver hkp://keys.gnupg.net --recv-keys 352c64e5 f4a80eb5
RUN gpg2 --export -a 352c64e5 >352c64e5.key;gpg2 --export -a f4a80eb5 >f4a80eb5.key
RUN rpm --import 352c64e5.key;rpm --import f4a80eb5.key
RUN rpm -iUvh https://dl.fedoraproject.org/pub/epel/7/x86_64/Packages/e/epel-release-7-13.noarch.rpm

RUN yum install -y python-pip git gcc python-devel

RUN pip install 'setuptools==44' python-magic jira PyGitHub

WORKDIR /tmp/

ENTRYPOINT [ "/bin/bash", "-l" ]
