FROM ubuntu:24.04
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       python3 python3-venv openssh-client ca-certificates rsync \
    && python3 -m venv /opt/ansible \
    && /opt/ansible/bin/pip install --no-cache-dir ansible-core==2.19.14 \
    && rm -rf /var/lib/apt/lists/*
ENV PATH="/opt/ansible/bin:$PATH"
COPY requirements.yml /opt/ansible/requirements.yml
RUN ansible-galaxy collection install -r /opt/ansible/requirements.yml
COPY entrypoint.sh /usr/local/bin/lab-entrypoint
RUN chmod +x /usr/local/bin/lab-entrypoint
ENTRYPOINT ["/usr/local/bin/lab-entrypoint"]
CMD ["sleep", "infinity"]
