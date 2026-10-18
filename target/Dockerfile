FROM ubuntu:24.04
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       openssh-server python3 sudo ca-certificates \
    && useradd --create-home --shell /bin/bash ansible \
    && printf 'ansible ALL=(ALL) NOPASSWD: ALL\n' > /etc/sudoers.d/ansible-lab \
    && chmod 440 /etc/sudoers.d/ansible-lab \
    && rm -f /etc/ssh/ssh_host_* \
    && rm -rf /var/lib/apt/lists/*
COPY sshd_config /etc/ssh/sshd_config
COPY entrypoint.sh /usr/local/bin/lab-entrypoint
RUN chmod +x /usr/local/bin/lab-entrypoint
ENTRYPOINT ["/usr/local/bin/lab-entrypoint"]
