FROM ubuntu:24.04
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       openssh-server python3 sudo ca-certificates nginx rsync \
    && useradd --create-home --shell /bin/bash deploy \
    && useradd --create-home --shell /bin/bash --groups sudo adminuser \
    && rm -f /etc/ssh/ssh_host_* /etc/nginx/sites-enabled/default \
    && rm -rf /var/lib/apt/lists/*
COPY sshd_config /etc/ssh/sshd_config
COPY entrypoint.sh /usr/local/bin/lab-entrypoint
COPY initial-app.conf /etc/nginx/sites-available/legacy-app.conf
RUN ln -s ../sites-available/legacy-app.conf /etc/nginx/sites-enabled/legacy-app.conf
RUN chmod +x /usr/local/bin/lab-entrypoint
ENTRYPOINT ["/usr/local/bin/lab-entrypoint"]
