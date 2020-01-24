
#------------------------------------------------------------------------------------
#--------------------------build-----------------------------------------------------
#------------------------------------------------------------------------------------
FROM centos:7 as build

RUN yum install -y gcc gcc-c++ make patch sudo unzip perl zlib automake libtool \
    zlib-devel bzip2 bzip2-devel libxml2-devel \
    tcl cmake

# Openssl for SRS
ADD openssl-1.1.0e.tar.bz2 /tmp
RUN cd /tmp/openssl-1.1.0e && ./config -no-shared no-threads && make && make install_sw

# For FFMPEG
ADD nasm-2.14.tar.bz2 /tmp
ADD yasm-1.2.0.tar.bz2 /tmp
ADD fdk-aac-0.1.3.tar.bz2 /tmp
ADD lame-3.99.5.tar.bz2 /tmp
ADD speex-1.2rc1.tar.bz2 /tmp
ADD x264-snapshot-20181116-2245.tar.bz2 /tmp
ADD ffmpeg-4.2.1.tar.bz2 /tmp
# The libsrt for SRS, which depends on openssl.
ADD srt-1.4.1.tar.gz /tmp
RUN cd /tmp/nasm-2.14 && ./configure && make && make install && \
    cd /tmp/yasm-1.2.0 && ./configure && make && make install && \
    cd /tmp/fdk-aac-0.1.3 && bash autogen.sh && ./configure && make && make install && \
    cd /tmp/lame-3.99.5 && ./configure && make && make install && \
    cd /tmp/speex-1.2rc1 && ./configure && make && make install && \
    cd /tmp/srt-1.4.1 && ./configure && make && make install && \
    cd /tmp/x264-snapshot-20181116-2245 && ./configure --disable-cli --enable-static && make && make install

# Remark, FFMPEG should always use libsrt.so, never use libsrt.a, or it'll failed.
RUN export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig && \
    cd /tmp/ffmpeg-4.2.1 && ./configure --enable-pthreads --extra-libs=-lpthread \
        --enable-gpl --enable-nonfree \
        --enable-postproc --enable-bzlib --enable-zlib \
        --enable-libx264 --enable-libmp3lame --enable-libfdk-aac --enable-libspeex \
        --enable-libxml2 --enable-demuxer=dash \
        --enable-libsrt && \
    (cd /usr/local/lib && mkdir -p tmp && mv *.so* *.la tmp && echo "Force use static libraries in lib") && \
	make && make install && echo "FFMPEG build and install successfully" && \
    (cd /usr/local/lib && mv tmp/* . && rmdir tmp)

#------------------------------------------------------------------------------------
#--------------------------dist------------------------------------------------------
#------------------------------------------------------------------------------------
FROM centos:7 as dist

WORKDIR /tmp/srs

COPY --from=build /usr/local/bin/ffmpeg /usr/local/bin/ffmpeg
COPY --from=build /usr/local/lib64/libssl.a /usr/local/lib64/libssl.a
COPY --from=build /usr/local/lib64/libcrypto.a /usr/local/lib64/libcrypto.a
COPY --from=build /usr/local/include/openssl /usr/local/include/openssl
COPY --from=build /usr/local/lib64/libsrt.a /usr/local/lib64/libsrt.a
COPY --from=build /usr/local/lib64/libsrt.so.1.4.1 /usr/local/lib64/libsrt.so.1.4.1
COPY --from=build /usr/local/include/srt /usr/local/include/srt
RUN cd /usr/local/lib64 && ln -sf libsrt.so.1.4.1 libsrt.so.1 && ln -sf libsrt.so.1 libsrt.so

# Note that git is very important for codecov to discover the .codecov.yml
RUN yum install -y gcc gcc-c++ make net-tools gdb lsof tree dstat redhat-lsb unzip zip git \
    tcl cmake

# Install cherrypy for HTTP hooks.
ADD CherryPy-3.2.4.tar.gz2 /tmp
RUN cd /tmp/CherryPy-3.2.4 && python setup.py install

# For FFMPEG to search libsrt.so.1
ENV LD_LIBRARY_PATH /usr/local/lib64

ENV PATH $PATH:/usr/local/go/bin
RUN cd /usr/local && \
    curl -L -O https://dl.google.com/go/go1.13.5.linux-amd64.tar.gz && \
    tar xf go1.13.5.linux-amd64.tar.gz && \
    rm -f go1.13.5.linux-amd64.tar.gz
