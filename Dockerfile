FROM ubuntu:20.04

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
USER root


WORKDIR /home
RUN mkdir src
ADD VERSION .

ENV DEBIAN_FRONTEND noninteractive

# Ubuntu packages + Numpy
RUN apt-get update \
     && apt-get install -y --no-install-recommends \
        apt-utils \
        build-essential \
        sudo \
        less \
        jed \
        g++  \
        git  \
        gpg \
        curl  \
        cmake \
        zlib1g-dev \
        libjpeg-dev \
        xvfb \
        xorg-dev \
        libboost-all-dev \
        libsdl2-dev \
        dbus \
        swig \
        python3  \
        python3-dev  \
        python3-distutils \
        python3-pip  \
        ffmpeg \
        libopenblas-base  \
#        cython3  \
     && apt-get upgrade -y \
     && apt-get clean \
     && rm -rf /var/lib/apt/lists/*

# use python3.8 as default
RUN update-alternatives --install /usr/bin/python python /usr/bin/python3.8 1
RUN update-alternatives --config python

# upgrade pip
RUN python -m pip install --upgrade pip

# Step 1: basic python/jupyter packages
COPY requirements_py.txt /tmp/
COPY requirements_jupyter.txt /tmp/
COPY requirements_financial.txt /tmp/
COPY requirements_misc.txt /tmp/

RUN python -m pip install -r /tmp/requirements_py.txt
RUN python -m pip install -r /tmp/requirements_jupyter.txt
RUN python -m pip install -r /tmp/requirements_financial.txt
RUN python -m pip install -r /tmp/requirements_misc.txt


# Step 2: install zipline & watermark
# https://github.com/stefan-jansen/zipline-reloaded

RUN apt-get update && \
   apt-get install  -y --no-install-recommends  \
   libhdf5-serial-dev \
   wget

RUN wget http://prdownloads.sourceforge.net/ta-lib/ta-lib-0.4.0-src.tar.gz && \
   tar -xzf ta-lib-0.4.0-src.tar.gz && \
   cd ta-lib/ && \ 
   ./configure && \
   make && \
   make install

RUN python -m pip install zipline-reloaded

# patch to fix error by pd.NaT
# https://github.com/stefan-jansen/zipline-reloaded/issues/29
#COPY patch/calendar_helpers.patch /tmp/
#RUN cd /usr/local/lib/python3.8/dist-packages/trading_calendars && \
#    patch -p0 < /tmp/calendar_helpers.patch

# Step 3: install additional kernel for iPython
RUN python -m pip install bash_kernel
RUN python -m bash_kernel.install 

# Step 4: Copy a script that we will use to correct permissions after running certain commands
COPY scripts/fix-permissions /usr/local/bin
RUN chmod a+rx /usr/local/bin/fix-permissions

# Step 5: Customize jupyter extensions
RUN python -m pip install jupyter-emacskeys \
    jupyter_contrib_nbextensions && \
    jupyter contrib nbextension install --sys-prefix

RUN python -m pip install RISE && \
    jupyter-nbextension install rise --py --sys-prefix


RUN python -m pip install jupytext --upgrade
RUN jupyter nbextension install --py jupytext --sys-prefix
RUN jupyter nbextension enable --py jupytext --sys-prefix

RUN python -m pip install autopep8 --upgrade
RUN jupyter nbextension install https://github.com/kenkoooo/jupyter-autopep8/archive/master.zip --user
RUN jupyter nbextension enable jupyter-autopep8-master/jupyter-autopep8


RUN jupyter nbextension enable highlighter/highlighter --sys-prefix
RUN jupyter nbextension enable toggle_all_line_numbers/main --sys-prefix
RUN jupyter nbextension enable hide_header/main --sys-prefix
#RUN jupyter nbextension enable hide_input/main --sys-prefix
RUN jupyter nbextension enable toc2/main --sys-prefix
RUN python -m pip install black
RUN jupyter nbextension install https://github.com/drillan/jupyter-black/archive/master.zip --sys-prefix
RUN jupyter nbextension enable jupyter-black-master/jupyter-black --sys-prefix

ENV DEBIAN_FRONTEND teletype
ENV JUPYTER_ALLOW_INSECURE_WRITES=true

RUN rm -rf "/root/.cache/yarn" && \
    rm -rf "/root/.node-gyp" 

# Step 6: create user account
ARG NB_USER="jovyan"
ARG NB_UID="1000"
ARG NB_GID="100"

ENV SHELL=/bin/bash \
    NB_USER=$NB_USER \
    NB_UID=$NB_UID \
    NB_GID=$NB_GID \
    HOME=/home/$NB_USER
    
RUN export uid=${NB_UID} gid=${NB_GID} && \
    echo "${NB_USER}:x:${NB_UID}:${NB_GID}:Developer,,,:${HOME}:/bin/bash" >> /etc/passwd && \
    echo "${NB_USER}:x:${NB_UID}:" >> /etc/group && \
    echo "${NB_USER} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers && \
    install -d -m 0755 -o ${NB_UID} -g ${NB_GID} ${HOME} && \
    fix-permissions ${HOME}

# Step 7: Install tini
ENV TINI_VERSION v0.19.0
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /tini
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini.asc /tini.asc
#RUN gpg --batch --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 595E85A6B1B4779EA4DAAEC70B588DFF0527A9B7 \
# && gpg --batch --verify /tini.asc /tini
RUN chmod a+rx /tini

# Step 8: Install other staffs

# Step 9: Configure container startup
RUN wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
RUN apt install -y ./google-chrome-stable_current_amd64.deb

ENTRYPOINT ["/tini", "-g", "--"]
CMD ["jupyter.sh"]
#CMD ["start-notebook.sh"]


## Copy local files as late as possible to avoid cache busting
COPY scripts/start.sh /usr/local/bin/
COPY scripts/start-notebook.sh /usr/local/bin/
COPY scripts/start-singleuser.sh /usr/local/bin/
RUN chmod a+rx /usr/local/bin/start.sh
RUN chmod a+rx /usr/local/bin/start-notebook.sh
RUN chmod a+rx /usr/local/bin/start-singleuser.sh

COPY scripts/jupyter.sh /usr/local/bin
COPY scripts/enable-formgrader /usr/local/bin
COPY scripts/aliases.sh /etc/profile.d
RUN chmod a+rx /usr/local/bin/jupyter.sh
RUN chmod a+rx /usr/local/bin/enable-formgrader

## Fix permissions on /etc/jupyter
USER root
RUN mkdir /etc/jupyter/ && \
    fix-permissions /etc/jupyter/

ENV DISPLAY :0.0
VOLUME /tmp/.X11-unix
VOLUME ${HOME}
USER ${NB_USER}
RUN fix-permissions ${HOME}

## Switch to jovyan to avoid accidental container runs as root
USER $NB_UID

WORKDIR $HOME
