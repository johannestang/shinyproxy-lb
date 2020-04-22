FROM maven:3.6.1-jdk-8
RUN apt-get update && apt-get install -y patch

WORKDIR /build
RUN git clone -n -b localdev https://github.com/johannestang/containerproxy
WORKDIR /build/containerproxy
RUN git checkout cbec676d29306050a4d65815a933550fd1e36591
RUN mvn -U clean install -DskipTests=true -Dlicense.skip=true

WORKDIR /build
RUN git clone -n https://github.com/openanalytics/shinyproxy
WORKDIR /build/shinyproxy
RUN git checkout v2.3.0
RUN mkdir local-maven-repo
RUN mvn org.apache.maven.plugins:maven-install-plugin:2.5.2:install-file  \
    -Dfile=/build/containerproxy/target/containerproxy-0.8.3.jar \
    -DgroupId=eu.openanalytics -DartifactId=containerproxy \
    -Dversion=0.8.3 -Dpackaging=jar \
    -DlocalRepositoryPath=local-maven-repo
COPY local-maven-repo.patch .
RUN patch -p0 < local-maven-repo.patch
RUN mvn -U clean install -DskipTests=true -Dlicense.skip=true

