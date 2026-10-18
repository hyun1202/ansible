FROM ubuntu:24.04
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       openssh-server python3 rsync nginx ca-certificates \
    && useradd --create-home --shell /bin/bash ansible \
    && rm -f /etc/ssh/ssh_host_* /etc/nginx/sites-enabled/default \
    && rm -rf /var/lib/apt/lists/*
COPY source/sshd_config /etc/ssh/sshd_config
COPY source/sshd-entrypoint.sh /usr/local/bin/lab-sshd-entrypoint
COPY source/entrypoint.sh /usr/local/bin/lab-source-entrypoint
COPY source/legacy-app.conf /etc/nginx/sites-available/legacy-app.conf
RUN chmod +x /usr/local/bin/lab-sshd-entrypoint /usr/local/bin/lab-source-entrypoint \
    && ln -s ../sites-available/legacy-app.conf /etc/nginx/sites-enabled/legacy-app.conf
ENTRYPOINT ["/usr/local/bin/lab-source-entrypoint"]
