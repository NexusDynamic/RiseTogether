# adapted from https://github.com/matsp/docker-flutter/blob/master/dev/Dockerfile

# The "platform" flag is needed to build on Apple Silicon (M1 etc)
# also requires the corresponting platform key in the docker compose file
FROM --platform=linux/arm64/v8 ubuntu:24.04 AS basebuild
ENV UID=1001
ENV GID=1001
ENV USER="developer"
ENV FLUTTER_CHANNEL="main"
ENV FLUTTER_VERSION="3.37.0-0.0.pre"
ENV FLUTTER_URL="https://storage.googleapis.com/flutter_infra_release/releases/$FLUTTER_CHANNEL/linux-arm64/flutter_linux_$FLUTTER_VERSION-$FLUTTER_CHANNEL.tar.xz"
ENV FLUTTER_HOME="/home/$USER/flutter"
ENV FLUTTER_WEB_PORT="8090"
ENV FLUTTER_DEBUG_PORT="42000"
ENV PATH="$FLUTTER_HOME/bin:$PATH"


# install all dependencies
ENV DEBIAN_FRONTEND="noninteractive"
ENV RUNLEVEL="5"
RUN apt-get update \
  && apt-get install --yes --no-install-recommends \
     curl unzip zip sed git bash xz-utils \
     libglvnd0 ssh xauth x11-xserver-utils \
     libpulse0 libxcomposite1 sudo \
      clang cmake ninja-build pkg-config \
      libgtk-3-dev liblzma-dev mesa-utils \
      libstdc++-12-dev ca-certificates \
      xvfb freeglut3-dev libglu1-mesa \
      dbus-daemon whoopsie at-spi2-core \
      dconf-cli apt-utils dbus-x11 \
      xserver-xorg-video-fbdev \
      clang-18 lld-18 llvm-18 libc++-18-dev \
      dbus network-manager at-spi2-core \
      libc++abi-18-dev clang-tools-18 llvm-18-runtime

RUN dpkg --add-architecture amd64
COPY apt-sources-multiarch.sources /etc/apt/sources.list.d/ubuntu.sources
RUN apt-get update
RUN apt-get install --yes --no-install-recommends gcc-x86-64-linux-gnu binutils-x86-64-linux-gnu \
    && rm -rf /var/lib/{apt,dpkg,cache,log}
# create user
RUN groupadd --gid $GID $USER \
  && useradd -s /bin/bash --uid $UID --gid $GID -m $USER \
  && echo $USER ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USER \
  && chmod 0440 /etc/sudoers.d/$USER
RUN dbus-uuidgen | tee /var/lib/dbus/machine-id
RUN mkdir -p /var/run/dbus
RUN chown $USER:$USER /var/run/dbus
RUN chown -R $USER:$USER /home/$USER
# RUN echo 1 > /proc/sys/net/ipv4/ip_forward
# RUN echo 1 > /proc/sys/net/ipv4/conf/all/mc_forwarding
# RUN route add -net 224.0.0.0 netmask 240.0.0.0 dev eth0

USER $USER
WORKDIR /home/$USER


FROM basebuild AS flutter
# flutter
# RUN curl -o flutter.tar.xz $FLUTTER_URL \
#   && mkdir -p $FLUTTER_HOME \
#   && tar xf flutter.tar.xz -C /home/$USER \
#   && rm flutter.tar.xz \
#   && flutter config \
#       --no-analytics \
#       --no-enable-web \
#       --no-enable-ios --no-enable-fuchsia \
#       --no-enable-macos-desktop \
#       --no-enable-windows-desktop \
#       --no-enable-android \
#       --enable-linux-desktop \
#   && flutter precache \
#   && flutter doctor \
#   && flutter update-packages
ENV PATH="$FLUTTER_HOME/bin:$PATH"
RUN git clone -b main https://github.com/flutter/flutter.git $FLUTTER_HOME
# RUN mkdir -p $FLUTTER_HOME/bin/cache
# RUN git -C $FLUTTER_HOME checkout $FLUTTER_CHANNEL
# RUN ls -la $FLUTTER_HOME/bin && false
# RUN flutter --version
# RUN sudo apt-get -y install apt-transport-https gpg wget
# RUN wget -qO- https://dl-ssl.google.com/linux/linux_signing_key.pub \
#   | sudo gpg  --dearmor -o /usr/share/keyrings/dart.gpg

# # download dart sdk and install to flutter cache
# RUN wget -q -O /home/$USER/dart-sdk.deb https://storage.googleapis.com/dart-archive/channels/dev/release/3.10.0-186.0.dev/linux_packages/dart_3.10.0-186.0.dev-1_arm64.deb \
#     && sudo dpkg -i /home/$USER/dart-sdk.deb \
#     && rm /home/$USER/dart-sdk.deb

ENV FLUTTER_ROOT="$FLUTTER_HOME"
# RUN cat flutter/bin/internal/shared.sh && false
# RUN flutter -v channel main
# RUN ls -la $FLUTTER_HOME/bin/cache/dart-sdk/bin && false
RUN flutter -v config \
      --no-analytics \
      --no-enable-web \
      --no-enable-ios --no-enable-fuchsia \
      --no-enable-macos-desktop \
      --no-enable-windows-desktop \
      --no-enable-android \
      --enable-linux-desktop
RUN flutter -v --disable-analytics
RUN flutter -v precache
RUN flutter -v doctor \
  && flutter -v update-packages

FROM flutter AS final
COPY entrypoint.sh /usr/local/bin/
RUN sudo chmod +x /usr/local/bin/entrypoint.sh
RUN mkdir /home/$USER/project
WORKDIR /home/$USER/project
RUN git clone https://github.com/NexusDynamic/RiseTogether.git .
RUN git clone --recursive https://github.com/NexusDynamic/liblsl.dart ../liblsl.dart
RUN mkdir -p /home/$USER/.local/share/com.zeyus.rise_together/logs/app/
RUN mkdir -p /home/$USER/.local/share/com.zeyus.rise_together/logs/data/
RUN sudo chown -R $USER:$USER /home/$USER/.local

RUN flutter pub get
ENTRYPOINT [ "/usr/local/bin/entrypoint.sh" ]
