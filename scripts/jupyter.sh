#!/bin/sh

PASS="opensesami"
cd ${HOME} \
    && xvfb-run -s "-screen 0 1024x768x24" \
    /usr/local/bin/jupyter notebook \
    --port=8888 --ip=0.0.0.0 --allow-root $1 \
    --NotebookApp.token=${PASS}



