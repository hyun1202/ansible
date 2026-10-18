FROM rockylinux/rockylinux:8
RUN dnf install -y openssh-server python39 rsync nginx ca-certificates shadow-utils \
    && useradd --create-home --shell /bin/bash ansible \
    && rm -f /etc/ssh/ssh_host_* \
    && dnf clean all
COPY source/sshd_config /etc/ssh/sshd_config
COPY source/sshd-entrypoint.sh /usr/local/bin/lab-sshd-entrypoint
COPY source/entrypoint.sh /usr/local/bin/lab-source-entrypoint
COPY target/nginx.conf /etc/nginx/nginx.conf
COPY source/html/ /usr/share/nginx/html/
RUN chmod +x /usr/local/bin/lab-sshd-entrypoint /usr/local/bin/lab-source-entrypoint
ENTRYPOINT ["/usr/local/bin/lab-source-entrypoint"]
