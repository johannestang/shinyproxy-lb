FROM maven:3-jdk-8
RUN apt-get update && apt-get install -y patch

WORKDIR /build
RUN git clone -n https://github.com/openanalytics/containerproxy
WORKDIR /build/containerproxy
RUN git checkout 9d8295a2015ea5cdb1b0e9d05ec9cf4e0bd25e74
COPY context-provider.patch .
RUN patch -p0 < context-provider.patch
RUN mvn -U clean install -DskipTests=true -Dlicense.skip=true

WORKDIR /build
RUN git clone -n https://github.com/openanalytics/shinyproxy
WORKDIR /build/shinyproxy
RUN git checkout f4576055af7f51934470ada82bbf07b5d5fc65df
RUN mkdir local-maven-repo
RUN mvn org.apache.maven.plugins:maven-install-plugin:2.5.2:install-file  \
    -Dfile=/build/containerproxy/target/containerproxy-0.8.3.jar \
    -DgroupId=eu.openanalytics -DartifactId=containerproxy \
    -Dversion=0.8.3 -Dpackaging=jar \
    -DlocalRepositoryPath=local-maven-repo
COPY local-maven-repo.patch .
RUN patch -p0 < local-maven-repo.patch
RUN mvn -U clean install -DskipTests=true -Dlicense.skip=true

