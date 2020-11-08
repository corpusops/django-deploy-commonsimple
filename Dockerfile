ARG BASE=corpusops/ubuntu-bare:bionic
FROM $BASE
ENV PYTHONUNBUFFERED 1
ENV DEBIAN_FRONTEND=noninteractive
ARG TZ=Europe/Paris
ARG PY_VER=3.6
# See https://github.com/nodejs/docker-node/issues/380
ARG GPG_KEYS=B42F6819007F00F88E364FD4036A9C25BF357DD4
ARG GPG_KEYS_SERVERS="hkp://p80.pool.sks-keyservers.net:80 hkp://ipv4.pool.sks-keyservers.net hkp://pgp.mit.edu:80"

WORKDIR /code
ADD apt.txt /code/apt.txt

# setup project timezone, dependencies, user & workdir, gosu
RUN bash -c 'set -ex \
    && date && : "set correct timezone" \
    && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone \
    && : "install packages" \
    && apt-get update -qq \
    && apt-get install -qq -y $(grep -vE "^\s*#" /code/apt.txt  | tr "\n" " ") \
    && apt-get clean all && apt-get autoclean \
    && : "project user & workdir" \
    && if ! ( getent passwd django &>/dev/null );then useradd -ms /bin/bash django --uid 1000;fi && date'

ADD --chown=django:django requirements*.txt tox.ini README.md /code/
ADD --chown=django:django src /code/src/
ADD --chown=django:django lib /code/lib/
ADD --chown=django:django private /code/private/

ARG BUILD_DEV=
ARG VSCODE_VERSION=
ARG PYCHARM_VERSION=
ARG WITH_VSCODE=0
ARG WITH_PYCHARM=0
ARG CFLAGS=
ARG CPPLAGS=
ARG C_INCLUDE_PATH=/usr/include/gdal/
ARG CPLUS_INCLUDE_PATH=/usr/include/gdal/
ARG LDFLAGS=
ARG LANG=fr_FR.utf8
ENV VSCODE_VERSION="$VSCODE_VERSION" \
    PYCHARM_VERSION="$PYCHARM_VERSION" \
    WITH_VSCODE="$WITH_VSCODE" \
    CFLAGS="$CFLAGS" \
    CPPLAGS="$CPPFLAGS" \
    C_INCLUDE_PATH="$C_INCLUDE_PATH" \
    CPLUS_INCLUDE_PATH="$CPLUS_INCLUDE_PATH" \
    LDFLAGS="$LDFLAGS" \
    WITH_PYCHARM="$WITH_PYCHARM" \
    LANG="$LANG"

RUN bash -exc ': \
    && date && find /code -not -user django \
    | while read f;do chown django:django "$f";done \
    && gosu django:django bash -exc "python${PY_VER} -m venv venv \
    && venv/bin/pip install -U --no-cache-dir setuptools wheel pip\
    && venv/bin/pip install -U --no-cache-dir -r ./requirements.txt \
    && if [[ -n \"$BUILD_DEV\" ]];then \
      venv/bin/pip install -U --no-cache-dir \
      -r ./requirements.txt \
      -r ./requirements-dev.txt\
      && if [ "x$WITH_VSCODE" = "x1" ];then venv/bin/python -m pip install -U "ptvsd${VSCODE_VERSION}";fi \
      && if [ "x$WITH_PYCHARM" = "x1" ];then venv/bin/python -m pip install -U "pydevd-pycharm${PYCHARM_VERSION}";fi; \
    fi \
    && for i in public/static public/media;do if [ ! -e $i ];then mkdir -p $i;fi;done" && date'

# django basic setup
RUN gosu django:django bash -exc ': \
    && . venv/bin/activate &>/dev/null \
    && cd src \
    && : django settings only for building steps \
    && export SECRET_KEY=build_time_key \
    && : \
    && ./manage.py compilemessages \
    && cd - \
    '

ADD sys                             /code/sys
ADD local/django-deploy-common/     /code/local/django-deploy-common/
RUN bash -exc ': \
    && cd /code && for i in init;do if [ ! -e $i ];then mkdir -p $i;fi;done \
    && find /code -not -user django \
    | while read f;do chown django:django "$f";done \
    && cp -frnv /code/local/django-deploy-common/sys/* sys \
    && cp -frnv sys/* init \
    && ln -sf $(pwd)/init/init.sh /init.sh'

# image will drop privileges itself using gosu
CMD chmod 0644 /etc/cron.d/django

WORKDIR /code/src

CMD "/init.sh"
