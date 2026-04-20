FROM jenkins/jenkins:lts-jdk21

USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*
USER jenkins

COPY --chown=jenkins:jenkins plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

# init.groovy.d is intentionally NOT copied into the image — it is bind-mounted
# at runtime from ./init.groovy.d so edits apply with `just restart` (no rebuild).
