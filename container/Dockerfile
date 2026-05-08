FROM debian:stable-slim

RUN apt-get update && \
    apt-get install -y openssh-server openssh-client && \
    mkdir -p /var/run/sshd /root/.ssh

# Generate MITM server host keys
RUN ssh-keygen -A

# Install forced command script
COPY dest-mitm.sh /usr/local/bin/dest-mitm
RUN chmod +x /usr/local/bin/dest-mitm

# Install reconfigure (idempotent rebuild)
COPY reconfigure.sh /reconfigure
RUN chmod +x /reconfigure

# Install entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# create user git, github needs a user named git.
RUN useradd -m git

# sshd base configuration
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    echo 'PasswordAuthentication no' >> /etc/ssh/sshd_config && \
    echo 'PubkeyAuthentication yes' >> /etc/ssh/sshd_config && \
    echo 'AllowTcpForwarding no' >> /etc/ssh/sshd_config && \
    echo 'X11Forwarding no' >> /etc/ssh/sshd_config

EXPOSE 22

CMD ["/entrypoint.sh"]