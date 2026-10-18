FROM rockylinux/rockylinux:8
RUN dnf install -y openssh-server python39 sudo ca-certificates nginx rsync acl shadow-utils passwd util-linux \
    && useradd --create-home --shell /bin/bash deploy \
    && useradd --create-home --shell /bin/bash --groups wheel adminuser \
    && printf '%s\n' '%wheel ALL=(ALL) ALL' > /etc/sudoers.d/lab-admin \
    && chmod 440 /etc/sudoers.d/lab-admin \
    && rm -f /etc/ssh/ssh_host_* \
    && dnf clean all
COPY sshd_config /etc/ssh/sshd_config
COPY entrypoint.sh /usr/local/bin/lab-entrypoint
COPY nginx.conf /etc/nginx/nginx.conf
COPY initial-index.html /usr/share/nginx/html/index.html
RUN chmod +x /usr/local/bin/lab-entrypoint
ENTRYPOINT ["/usr/local/bin/lab-entrypoint"]
