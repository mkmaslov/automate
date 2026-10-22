# How to deploy:
#
# 1. Create Docker image.
#    Inside a Linux machine:
#    docker build -t codex-dev --build-arg SSH_PUBLIC_KEY="$(cat ~/.ssh/keys/CodexVM.pub)" - < codex-dev.dockerfile
#    Inside a VM:
#    docker build -t codex-dev --build-arg SSH_PUBLIC_KEY="$(cat "$HOME/.ssh/authorized_keys")" - < codex-dev.dockerfile
#
# 2. Create Docker container:
#    docker create -it --name codex-dev --hostname codex-dev --dns 8.8.8.8 --security-opt no-new-privileges=true -p 127.0.0.1:3452:22 codex-dev
#
# 3. Start container:
#    docker start codex-dev
#
# 4. Set root user password:
#    docker exec -it --user root codex-dev passwd root
#    Log in as root:
#    docker exec -it --user root codex-dev zsh -l
#    Log in as normal user:
#    docker exec -it codex-dev zsh
#
# 5. Stop container:
#    docker stop codex-dev
#
# 6. Delete container:
#    docker rm codex-dev
#
#------------------------------------------------------------------------------

FROM debian:trixie-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Bootstrap dependencies; scripts install their own tools.
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git locales python3-venv passwd nodejs \
    npm zsh neovim tmux openssh-server && rm -rf /var/lib/apt/lists/*

# /opt/setup is inside the image, not on the Mac.
ARG SCRIPTS_URL=https://raw.githubusercontent.com/mkmaslov/automate/refs/heads/main/dist/linux
RUN mkdir -p /opt/setup \
    && curl -fsSL "$SCRIPTS_URL/configure-zsh.sh" -o /opt/setup/zsh.sh \
    && curl -fsSL "$SCRIPTS_URL/configure-nvim.sh" -o /opt/setup/nvim.sh \
    && curl -fsSL "$SCRIPTS_URL/configure-tmux.sh" -o /opt/setup/tmux.sh \
    && curl -fsSL "$SCRIPTS_URL/install-python.sh" -o /opt/setup/python.sh

# Create a non-root user with a home directory and Zsh.
RUN useradd --create-home --shell /usr/bin/zsh --password '*' containeruser
RUN touch /home/containeruser/.hushlogin \
    && chown containeruser:containeruser /home/containeruser/.hushlogin

# Configure both homes while retaining root privileges for installation.
RUN for setup_user in root containeruser; do \
        runuser -u "$setup_user" -- bash -c '\
            set -e; \
            bash /opt/setup/zsh.sh; \
            bash /opt/setup/nvim.sh; \
            bash /opt/setup/tmux.sh; \
            bash /opt/setup/python.sh' \
        || exit 1; \
    done \
    && chown -R containeruser:containeruser /home/containeruser

# Ensure the final locale is en_IE.
RUN sed -i 's/^# *en_IE.UTF-8 UTF-8/en_IE.UTF-8 UTF-8/' /etc/locale.gen \
    && locale-gen && update-locale LANG=en_IE.UTF-8

ENV LANG=en_IE.UTF-8

RUN npm install -g @openai/codex && codex --version && npm cache clean --force
RUN chsh -s /usr/bin/zsh root && rm -rf /opt/setup /var/lib/apt/lists/*

ARG SSH_PUBLIC_KEY

RUN test -n "$SSH_PUBLIC_KEY" \
    && install -d -m 700 -o containeruser -g containeruser /home/containeruser/.ssh \
    && printf '%s\n' "$SSH_PUBLIC_KEY" \
       > /home/containeruser/.ssh/authorized_keys \
    && chown containeruser:containeruser /home/containeruser/.ssh/authorized_keys \
    && chmod 600 /home/containeruser/.ssh/authorized_keys

RUN printf '%s\n' \
    'PubkeyAuthentication yes' \
    'PasswordAuthentication no' \
    'KbdInteractiveAuthentication no' \
    'PermitRootLogin no' \
    > /etc/ssh/sshd_config.d/00-container.conf

# Generate separate server keys when each container first starts.
RUN rm -f /etc/ssh/ssh_host_*

ENV SHELL=/usr/bin/zsh
WORKDIR /home/containeruser
EXPOSE 22

CMD ["/bin/sh", "-c", "mkdir -p /run/sshd && ssh-keygen -A && exec /usr/sbin/sshd -D -e"]

#------------------------------------------------------------------------------
