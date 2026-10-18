FROM rockylinux/rockylinux:8
RUN dnf install -y openssh-server python39 rsync nginx ca-certificates shadow-utils sudo acl passwd util-linux \
    && useradd --create-home --shell /bin/bash ansible \
    && useradd --create-home --shell /bin/bash --groups wheel adminuser \
    && printf '%s\n' '%wheel ALL=(ALL) ALL' > /etc/sudoers.d/lab-admin \
    && chmod 440 /etc/sudoers.d/lab-admin \
    && rm -f /etc/ssh/ssh_host_* \
    && dnf clean all
COPY source/sshd_config /etc/ssh/sshd_config
COPY source/sshd-entrypoint.sh /usr/local/bin/lab-sshd-entrypoint
COPY source/entrypoint.sh /usr/local/bin/lab-source-entrypoint
COPY target/nginx.conf /etc/nginx/nginx.conf
COPY source/html/ /usr/share/nginx/html/
RUN chmod +x /usr/local/bin/lab-sshd-entrypoint /usr/local/bin/lab-source-entrypoint
COPY source/service-template/ /opt/lab-service-template/
COPY source/prepare-services.sh /usr/local/bin/lab-prepare-services
RUN sh /usr/local/bin/lab-prepare-services
ENTRYPOINT ["/usr/local/bin/lab-source-entrypoint"]
