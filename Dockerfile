FROM ubuntu:18.04

RUN if [ "$(uname -m)" = "aarch64" ]; then \
        echo "deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ bionic main restricted universe multiverse" > /etc/apt/sources.list && \
        echo "deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ bionic-updates main restricted universe multiverse" >> /etc/apt/sources.list && \
        echo "deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ bionic-backports main restricted universe multiverse" >> /etc/apt/sources.list && \
        echo "deb http://ports.ubuntu.com/ubuntu-ports/ bionic-security main restricted universe multiverse" >> /etc/apt/sources.list; \
    else \
        echo "deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ bionic main restricted universe multiverse" > /etc/apt/sources.list && \
        echo "deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ bionic-updates main restricted universe multiverse" >> /etc/apt/sources.list && \
        echo "deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ bionic-backports main restricted universe multiverse" >> /etc/apt/sources.list && \
        echo "deb http://security.ubuntu.com/ubuntu/ bionic-security main restricted universe multiverse" >> /etc/apt/sources.list; \
    fi

ENV TZ=Etc/UTC
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

RUN apt-get -o Acquire::https::Verify-Peer=false update && \
    apt-get upgrade && \
    apt-get -y install ca-certificates

RUN update-ca-certificates
RUN apt-get full-upgrade -y
RUN apt-get install -y build-essential module-assistant python python3 sudo wget software-properties-common python3-launchpadlib qtbase5-dev qtbase5-dev-tools

ARG GIT_NAME
ARG GIT_EMAIL
RUN sudo add-apt-repository -y ppa:git-core/ppa \
sudo apt-get update \
sudo apt-get install git -y \
git config --set user.name ${GIT_NAME} \
git config --set user.email ${GIT_EMAIL}

RUN sudo update-alternatives --install /usr/bin/python python /usr/bin/python3 1
ADD . /build_tools
WORKDIR /build_tools

# Build arguments
ARG BRANCH
ARG PLATFORM
ARG HTTP_PROXY
ARG HTTPS_PROXY

ENV http_proxy=${HTTP_PROXY}
ENV https_proxy=${HTTPS_PROXY}

ENV BRANCH=${BRANCH}
ENV PLATFORM=${PLATFORM}

# Define the command to run
CMD cd tools/linux && \    if [ -n "$BRANCH" ]; then \
        BRANCH_ARG="--branch=${BRANCH}"; \
    else \
        BRANCH_ARG=""; \
    fi && \
    if [ -n "$PLATFORM" ]; then \
        PLATFORM_ARG="--platform=${PLATFORM}"; \
    else \
        PLATFORM_ARG=""; \
    fi && \
    python3 ./automate.py $BRANCH_ARG $PLATFORM_ARG
