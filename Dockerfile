FROM alpine AS builder

RUN apk update \
  && apk upgrade \
  && apk add --no-cache \
    clang \
    lscpu \
    git \
    autoconf \
    automake \
    make \
    linux-headers

WORKDIR /app

RUN git clone https://github.com/aawc/unrar.git

WORKDIR /app/unrar

RUN if [ $(lscpu | grep -c aarch64) -gt 0 ]; then sed -i 's|CXXFLAGS=.*|CXXFLAGS=-mtune=cortex-a53 -march=armv8-a+crypto+crc -O2 -std=c++11 -Wno-logical-op-parentheses -Wno-switch -Wno-dangling-else|' makefile; fi
RUN sed -i 's|CXX=.*|CXX=clang++|' makefile

RUN sed -i 's|LDFLAGS=-pthread|LDFLAGS=-pthread -static|' makefile

RUN make -j $(lscpu | grep "^CPU(s):" | awk '{print $2}')

WORKDIR /app

RUN git clone https://github.com/animetosho/par2cmdline-turbo.git

WORKDIR /app/par2cmdline-turbo

RUN ./automake.sh && \
    autoupdate && \
    ./configure

RUN if [ $(lscpu | grep -c aarch64) -gt 0 ]; then sed -i 's|CXXFLAGS =.*|CXXFLAGS = -O2 -mtune=cortex-a53 -march=armv8-a+crypto+crc|' Makefile; fi

RUN make

FROM python:alpine AS python

RUN apk add curl

WORKDIR /app

RUN curl -s https://api.github.com/repos/sabnzbd/sabnzbd/releases/latest | grep 'tarball_url' | cut -d '"' -f 4 | xargs curl -L -o sabnzbd.tar.gz

RUN mkdir sabnzbd

RUN tar xvaf sabnzbd.tar.gz -C sabnzbd --strip-components=1

WORKDIR /app/sabnzbd

RUN pip install -r requirements.txt --root /app/

FROM python:alpine

WORKDIR /app/sabnzbd

COPY --from=builder /app/unrar/unrar /usr/bin/unrar
COPY --from=builder /app/par2cmdline-turbo/par2 /usr/bin/par2

COPY --chown=65532 --from=python /app/sabnzbd /app/sabnzbd
COPY --chown=65532 --from=python /app/usr /app/usr

VOLUME /config

VOLUME /data

EXPOSE 8080/tcp

ENV PATH=/app/usr/local/bin/:$PATH
ENV PYTHONPATH=/app/usr/local/lib/python3.13/site-packages/

CMD [ "python", "SABnzbd.py", "-f", "/config/sabnzbd.ini" ]
