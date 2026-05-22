FROM alpine:latest AS baseline

RUN apk update && apk add bash

RUN mkdir /work

COPY src/iotest.sh /work/iotest.sh
COPY src/k8s_iotest.sh /work/k8s_iotest.sh

RUN    ln -s /work/iotest.sh /usr/local/bin/iotest \
    && ln -s /work/iotest.sh /usr/local/bin/iotest.sh \
    && ln -s /work/k8s_iotest.sh /usr/local/bin/k8s_iotest \
    && ln -s /work/k8s_iotest.sh /usr/local/bin/k8s_iotest.sh \
    && chown 0:0 /work/k8s_iotest.sh /work/iotest.sh \
    && chmod 777 /work \
    && chmod 755 /work/k8s_iotest.sh /work/iotest.sh

WORKDIR /work

ENTRYPOINT ["bash","k8s_iotest"]