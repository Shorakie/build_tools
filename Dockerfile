# ==============================[Compiler]==============================
FROM ubuntu:18.04 AS compiler

ENV TZ=Etc/UTC
ENV PYTHONUNBUFFERED=1
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

RUN apt-get -o Acquire::https::Verify-Peer=false update && \
    apt-get full-upgrade -y && \
    apt-get -y install ca-certificates

RUN update-ca-certificates
RUN apt full-upgrade -y
RUN apt-get install -y build-essential module-assistant python python3 sudo dos2unix \
    wget software-properties-common python3-launchpadlib qtbase5-dev qtbase5-dev-tools

RUN sudo add-apt-repository -y ppa:git-core/ppa && \
    sudo apt-get update && \
    sudo apt-get install -y git

RUN sudo update-alternatives --install /usr/bin/python python /usr/bin/python3 1
ADD . /root/build_tools
WORKDIR /root/build_tools

# Build Deps
RUN cd tools/linux && python3 ./deps.py

# Build Qt
RUN cd tools/linux && \
    wget -O qt_source_5.9.9.tar.xz http://image.hi-hufei.com/qt/qt-everywhere-opensource-src-5.9.9.tar.xz && \
    tar -xf ./qt_source_5.9.9.tar.xz && rm ./qt_source_5.9.9.tar.xz
ENV CORES=8
RUN cd tools/linux/qt-everywhere-opensource-src-5.9.9 && \
    ./configure -opensource -confirm-license -release -shared -accessibility -prefix ./../qt_build/Qt-5.9.9/gcc_64 -qt-zlib -qt-libpng -qt-libjpeg -qt-xcb -qt-pcre -no-sql-sqlite -no-qml-debug -gstreamer 1.0 -nomake examples -nomake tests -skip qtenginio -skip qtlocation -skip qtserialport -skip qtsensors -skip qtxmlpatterns -skip qt3d -skip qtwebview -skip qtwebengine && \
    make -j${CORES} && \
    make install && \
    cd .. && rm -rd qt-everywhere-opensource-src-5.9.9

# Define the command to run
RUN cd tools/linux && python3 ./automate.py server --platform=linux_arm64

# ==============================[Package Builder]==============================
# 
FROM debian:11 as package_builder

ENV DEBIAN_FRONTEND=noninteractive

# SYSTEM
RUN apt-get -qq update
RUN apt-get -qq dist-upgrade -y
RUN apt-get -qq autoremove -y
RUN apt-get -qq install -y apt-utils ca-certificates tzdata curl wget \
    software-properties-common apt-transport-https debhelper sudo

# ENVIRONMENT
RUN apt-get -qq install -y build-essential git m4 npm locales locales-all
RUN locale-gen en_US.UTF-8

RUN npm install -g pkg

ARG DS_VERSION=8.2
ARG DS_BUILD_NUMBER=0
ENV DS_PACKAGE_BRANCH=release/v${DS_VERSION}.${DS_BUILD_NUMBER}
ENV LC_ALL=en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US.UTF-8

WORKDIR /root
COPY --from=compiler /root/build_tools/out /root/build_tools/out

RUN git clone https://github.com/ONLYOFFICE/document-server-package.git
RUN cd /root/document-server-package && \
PRODUCT_VERSION="${DS_VERSION}" BUILD_NUMBER="${DS_BUILD_NUMBER}" make deb

# ==============================[Dockerize]==============================
# 
FROM ubuntu:22.04 AS documentserver
LABEL maintainer Mohamad Amin Jafari <mhmdamin.jafari@gmail.com>

ARG BASE_VERSION
ARG PG_VERSION=14

ENV OC_RELEASE_NUM=21
ENV OC_RU_VER=12
ENV OC_RU_REVISION_VER=0
ENV OC_RESERVED_NUM=0
ENV OC_RU_DATE=0
ENV OC_PATH=${OC_RELEASE_NUM}${OC_RU_VER}000
ENV OC_FILE_SUFFIX=${OC_RELEASE_NUM}.${OC_RU_VER}.${OC_RU_REVISION_VER}.${OC_RESERVED_NUM}.${OC_RU_DATE}${OC_FILE_SUFFIX}dbru
ENV OC_VER_DIR=${OC_RELEASE_NUM}_${OC_RU_VER}
ENV OC_DOWNLOAD_URL=https://download.oracle.com/otn_software/linux/instantclient/${OC_PATH}

ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8 DEBIAN_FRONTEND=noninteractive PG_VERSION=${PG_VERSION} BASE_VERSION=22.04

ARG ONLYOFFICE_VALUE=onlyoffice

RUN echo "#!/bin/sh\nexit 0" > /usr/sbin/policy-rc.d && \
    apt-get -y update && \
    apt-get -yq install wget apt-transport-https gnupg locales lsb-release && \
    wget -q -O /etc/apt/sources.list.d/mssql-release.list https://packages.microsoft.com/config/ubuntu/$BASE_VERSION/prod.list && \
    wget -q -O - https://packages.microsoft.com/keys/microsoft.asc | apt-key add - && \
    apt-get -y update && \
    locale-gen en_US.UTF-8 && \
    echo ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true | debconf-set-selections && \
    ACCEPT_EULA=Y apt-get -yq install \
        adduser \
        apt-utils \
        bomstrip \
        certbot \
        cron \
        curl \
        htop \
        libaio1 \
        libasound2 \
        libboost-regex-dev \
        libcairo2 \
        libcurl3-gnutls \
        libcurl4 \
        libgtk-3-0 \
        libnspr4 \
        libnss3 \
        libstdc++6 \
        libxml2 \
        libxss1 \
        libxtst6 \
        mssql-tools18 \
        mysql-client \
        nano \
        net-tools \
        netcat-openbsd \
        nginx-extras \
        postgresql \
        postgresql-client \
        pwgen \
        rabbitmq-server \
        redis-server \
        sudo \
        supervisor \
        ttf-mscorefonts-installer \
        unixodbc-dev \
        unzip \
        xvfb \
        xxd \
        zlib1g && \
    if [  $(ls -l /usr/share/fonts/truetype/msttcorefonts | wc -l) -ne 61 ]; \
        then echo 'msttcorefonts failed to download'; exit 1; fi  && \
    echo "SERVER_ADDITIONAL_ERL_ARGS=\"+S 1:1\"" | tee -a /etc/rabbitmq/rabbitmq-env.conf && \
    sed -i "s/bind .*/bind 127.0.0.1/g" /etc/redis/redis.conf && \
    sed 's|\(application\/zip.*\)|\1\n    application\/wasm wasm;|' -i /etc/nginx/mime.types && \
    pg_conftool $PG_VERSION main set listen_addresses 'localhost' && \
    service postgresql restart && \
    sudo -u postgres psql -c "CREATE USER $ONLYOFFICE_VALUE WITH password '$ONLYOFFICE_VALUE';" && \
    sudo -u postgres psql -c "CREATE DATABASE $ONLYOFFICE_VALUE OWNER $ONLYOFFICE_VALUE;" && \
    wget -O basic.zip ${OC_DOWNLOAD_URL}/instantclient-basic-linux.x64-${OC_FILE_SUFFIX}.zip && \
    wget -O sqlplus.zip ${OC_DOWNLOAD_URL}/instantclient-sqlplus-linux.x64-${OC_FILE_SUFFIX}.zip && \
    unzip -d /usr/share basic.zip && \
    unzip -d /usr/share sqlplus.zip && \
    mv /usr/share/instantclient_${OC_VER_DIR} /usr/share/instantclient && \
    service postgresql stop && \
    service redis-server stop && \
    service rabbitmq-server stop && \
    service supervisor stop && \
    service nginx stop && \
    rm -rf /var/lib/apt/lists/*

COPY configurations/supervisor/supervisor /etc/init.d/
COPY configurations/supervisor/ds/*.conf /etc/supervisor/conf.d/
COPY run-document-server.sh /app/ds/run-document-server.sh
COPY oracle/sqlplus /usr/bin/sqlplus

EXPOSE 80 443

ARG COMPANY_NAME=onlyoffice
ARG PRODUCT_NAME=documentserver
ARG DS_VERSION=8.2
ARG DS_BUILD_NUMBER=0
ARG TARGETARCH

ENV COMPANY_NAME=$COMPANY_NAME \
    PRODUCT_NAME=$PRODUCT_NAME \
    DS_PLUGIN_INSTALLATION=false \
    DS_DOCKER_INSTALLATION=true

# onlyoffice-documentserver_8.2-0_arm64.deb
ENV PACKAGE_FILE="${COMPANY_NAME}-${PRODUCT_NAME}_${DS_VERSION}-${DS_BUILD_NUMBER}_${TARGETARCH:-$(dpkg --print-architecture)}.deb"
COPY --from=package_builder /root/document-server-package/deb/${PACKAGE_FILE} /tmp/
RUN apt-get -y update && \
    service postgresql start && \
    apt-get -yq install /tmp/$PACKAGE_FILE && \
    service postgresql stop && \
    chmod 755 /etc/init.d/supervisor && \
    sed "s/COMPANY_NAME/${COMPANY_NAME}/g" -i /etc/supervisor/conf.d/*.conf && \
    service supervisor stop && \
    chmod 755 /app/ds/*.sh && \
    printf "\nGO" >> /var/www/$COMPANY_NAME/documentserver/server/schema/mssql/createdb.sql && \
    printf "\nGO" >> /var/www/$COMPANY_NAME/documentserver/server/schema/mssql/removetbl.sql && \
    printf "\nexit" >> /var/www/$COMPANY_NAME/documentserver/server/schema/oracle/createdb.sql && \
    printf "\nexit" >> /var/www/$COMPANY_NAME/documentserver/server/schema/oracle/removetbl.sql && \
    rm -f /tmp/$PACKAGE_FILE && \
    rm -rf /var/log/$COMPANY_NAME && \
    rm -rf /var/lib/apt/lists/*

VOLUME /var/log/$COMPANY_NAME /var/lib/$COMPANY_NAME /var/www/$COMPANY_NAME/Data /var/lib/postgresql /var/lib/rabbitmq /var/lib/redis /usr/share/fonts/truetype/custom

ENTRYPOINT ["/app/ds/run-document-server.sh"]
