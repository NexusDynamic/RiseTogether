This setup is meant to run a headless version.

Currently the VM/Container setup is only tested on macOS (apple silicon), and the architecture is hardcoded in the Dockerfile and compose.yaml.


# requirements (for fully networked setup)

**warning**: this setup is completely insecure, if your network is open to the internet, or even to a wider LAN, you should not run this setup without additional security measures (firewall rules, routing, LAN port isolateion, etc.).

- install lima: https://lima-vm.io/
- install podman (desktop): https://podman.io/getting-started/installation
- install socket_vmnet: https://lima-vm.io/docs/config/network/vmnet/

Use bridged network mode, and a rootful podman setup (see podman docs for details).

```yaml
networks:
- lima: bridged
```

rough setup guide: (all subsequent commands are assumed to be run from this `podman` directory)

```bash
limactl start --network=lima:bridged template://podman-rootful
podman system connection add lima-podman-rootful "unix:///Users/<username>/.lima/podman-rootful/sock/podman.sock"
podman system connection default lima-podman-rootful
podman.lima compose up -d --build
```

as of now this clones the repo from github, builds the flutter app in headless mode, and starts it.

it uses 1x1 pixel Xvfb to provide a virtual framebuffer for flutter to run in

*Note:* the first time it runs it will take quite a while to set up the container, but subsequent runs will be almost instant.

to stop the setup:

```bash
podman.lima compose down # stops and removes the container
```

or 

```bash
podman.lima stop # stops the container, but keeps it available
```

to start again:

```bash
podman.lima start # starts the container again
```

# accessing logs

Because the app logs are mounted as volumes, they will be available on the host system in `podman/logs`.
