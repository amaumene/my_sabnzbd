FROM alpine AS builder

RUN apk add --no-cache \
    clang \
    lscpu \
    git \
    autoconf \
    automake \
    make \
    linux-headers \
    perl

WORKDIR /app

RUN git clone https://github.com/aawc/unrar.git

WORKDIR /app/unrar

RUN if [ $(lscpu | grep -c aarch64) -gt 0 ]; then sed -i 's|CXXFLAGS=.*|CXXFLAGS=-march=armv8-a+crypto+crc -O2 -std=c++11 -Wno-logical-op-parentheses -Wno-switch -Wno-dangling-else|' makefile; fi
RUN sed -i 's|CXX=.*|CXX=clang++|' makefile

RUN sed -i 's|LDFLAGS=-pthread|LDFLAGS=-pthread -static|' makefile

RUN make -j $(lscpu | grep "^CPU(s):" | awk '{print $2}')

WORKDIR /app

RUN git clone https://github.com/animetosho/par2cmdline-turbo.git

WORKDIR /app/par2cmdline-turbo

RUN ./automake.sh && \
    autoupdate

RUN if [ $(lscpu | grep -c aarch64) -gt 0 ]; then CC=clang CXXFLAGS="-O2 -march=armv8-a+crypto+crc" CFLAGS="-O2 -march=armv8-a+crypto+crc" LDFLAGS="-static" ./configure; else ./configure; fi

RUN make -j $(lscpu | grep "^CPU(s):" | awk '{print $2}')

WORKDIR /app

RUN wget -O - https://api.github.com/repos/openssl/openssl/releases/latest | grep 'tarball_url' | cut -d '"' -f 4 | xargs wget -O openssl.tar.gz

RUN mkdir openssl

RUN tar xvaf openssl.tar.gz -C openssl --strip-components=1

WORKDIR /app/openssl

RUN if [ $(lscpu | grep -c aarch64) -gt 0 ];\
    then CC=clang CXXFLAGS="-O3 -march=armv8-a+crypto+crc" CFLAGS="-O3 -march=armv8-a+crypto+crc" \
      ./Configure enable-ktls \
                shared \
                no-zlib \
                no-async \
                no-comp \
                no-idea \
                no-mdc2 \
                no-rc5 \
                no-ec2m \
                no-ssl3 \
                no-seed \
                no-weak-ssl-ciphers \
                enable-devcryptoeng; \
    else ./Configure enable-ktls \
                shared \
                no-zlib \
                no-async \
                no-comp \
                no-idea \
                no-mdc2 \
                no-rc5 \
                no-ec2m \
                no-ssl3 \
                no-seed \
                no-weak-ssl-ciphers \
                enable-devcryptoeng; fi

RUN wget -O include/crypto/cryptodev.h https://raw.githubusercontent.com/cryptodev-linux/cryptodev-linux/refs/heads/master/crypto/cryptodev.h

RUN make -j $(lscpu | grep "^CPU(s):" | awk '{print $2}')

RUN make install

RUN sed -e '/providers = provider_sect/a\' -e 'engines = engines_sect' -i /usr/local/ssl/openssl.cnf

COPY ./devcrypto.cnf ./devcrypto.cnf

RUN cat devcrypto.cnf >> /usr/local/ssl/openssl.cnf

FROM python:alpine AS python

WORKDIR /app

RUN wget -O - https://api.github.com/repos/sabnzbd/sabnzbd/releases/latest | grep 'tarball_url' | cut -d '"' -f 4 | xargs wget -O sabnzbd.tar.gz

RUN mkdir sabnzbd

RUN tar xvaf sabnzbd.tar.gz -C sabnzbd --strip-components=1

RUN pip install sabctools CT3 feedparser configobj cherrypy cheroot portend cryptography chardet guessit puremagic PySocks apprise --root /app/

RUN cd /usr/local/lib/python3.$(python -V | cut -d '.' -f 2) && \
    python -m compileall -o 2 . && \
    find . -name "*.cpython-*.opt-2.pyc" | awk '{print $1, $1}' | sed 's/__pycache__\///2' | sed 's/.cpython-[0-9]\{2,\}.opt-2//2' | xargs -n 2 mv && \
    find . -name "*.py" -delete && \
    find . -name "__pycache__" -exec rm -r {} +

RUN cd /app/usr && \
    python -m compileall -o 2 . && \
    find . -name "*.cpython-*.opt-2.pyc" | awk '{print $1, $1}' | sed 's/__pycache__\///2' | sed 's/.cpython-[0-9]\{2,\}.opt-2//2' | xargs -n 2 mv && \
    find . -name "*.py" -delete && \
    find . -name "__pycache__" -exec rm -r {} +

RUN cp -r /app/usr/local/lib/python3.$(echo $PYTHON_VERSION | cut -d '.' -f 2)/site-packages /app/usr/local/lib/python3/

RUN mkdir /tmp/lib && cp /lib/ld-musl-* /tmp/lib

FROM scratch

WORKDIR /app/sabnzbd

COPY --chown=65532 --from=python /app/sabnzbd/SABnzbd.py /app/sabnzbd/SABnzbd.py
COPY --chown=65532 --from=python /app/sabnzbd/sabnzbd/ /app/sabnzbd/sabnzbd/
COPY --chown=65532 --from=python /app/sabnzbd/interfaces/ /app/sabnzbd/interfaces/

COPY --from=python /app/usr/local/bin /app/usr/bin
COPY --from=python /usr/local/bin/python3 /
COPY --from=python /usr/local/lib/ /usr/local/lib/
COPY --from=python /app/usr/local/lib/python3/ /app/usr/local/lib/python3/

COPY --from=python /tmp/lib/ /lib/

COPY --from=builder /app/unrar/unrar /app/usr/bin/unrar
COPY --from=builder /app/par2cmdline-turbo/par2 /app/usr/bin/par2
COPY --from=builder /usr/local/lib /usr/local/lib
COPY --from=builder /usr/local/ssl /usr/local/ssl

COPY --from=python /usr/lib/libz.so.1 /usr/lib/libz.so.1
COPY --from=python /usr/lib/libffi.so.8 /usr/lib/libffi.so.8
COPY --from=python /usr/lib/libbz2.so.1 /usr/lib/libbz2.so.1
COPY --from=python /usr/lib/libsqlite3.so.0 /usr/lib/libsqlite3.so.0

VOLUME /config

VOLUME /data

EXPOSE 8080/tcp

ENV PATH=/app/usr/bin/:$PATH
ENV PYTHONPATH=/usr/local/lib/python3/:/app/usr/local/lib/python3/

CMD [ "/python3", "SABnzbd.py", "-f", "/config/sabnzbd.ini" ]
