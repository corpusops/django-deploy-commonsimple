# syntax=docker/dockerfile:1.3
ARG BASE=corpusops/ubuntu:20.04
FROM $BASE
ARG PY_VER=3.8
ARG DEBIAN_FRONTEND=noninteractive
ENV PY_VER=$PY_VER
WORKDIR /code/docs
ADD apt.txt ../
ADD docs/apt.txt ./
RUN \
    --mount=type=cache,id=copsdocs${BASE}apt,target=/var/cache/apt \
    --mount=type=cache,id=copsdocs${BASE}list,target=/var/lib/apt/lists \
    bash -exc ': \
    && : "install dev packages" \
    && rm -f /etc/apt/apt.conf.d/docker-clean || true;echo "Binary::apt::APT::Keep-Downloaded-Packages \"true\";" > /etc/apt/apt.conf.d/keep-cache \
    && apt-get update  -qq \
    && sed -i -re "s/(python-?)[0-9]\.[0-9]+/\1$PY_VER/g" ../apt.txt ./apt.txt \
    && apt-get install -qq -y $(cat ../apt.txt apt.txt |grep -vE "^\s*#"|tr "\n" " " )  \
    && apt-get clean all && apt-get autoclean && rm -rf /var/lib/apt/lists/* \
   '
RUN \
    --mount=type=cache,id=copsdocs${PY_VER}pip,target=/home/$APP_TYPE/.cache/pip \
   bash -ec "if ! ( python${PY_VER} -m pip --version; );then python${PY_VER} <( curl https://bootstrap.pypa.io/get-pip.py; );fi && python${PY_VER} -m pip --version"
ADD docs/req*.txt ./
ADD requirements* *txt ../requirements/
RUN \
    --mount=type=cache,id=copsdocs${PY_VER}pip,target=/home/$APP_TYPE/.cache/pip \
    python${PY_VER} -m pip install -r requirements.txt
ADD .env *env ../
ADD docs ./
ADD local /code/local/
ENTRYPOINT ["/code/docs/entry.sh"]
