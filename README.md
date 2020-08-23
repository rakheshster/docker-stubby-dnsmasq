# Stubby + Dnsmasq + Docker
## What is this?
This is a Docker image containing Stubby and Dnsmasq.

From the [Stubby documentation](https://dnsprivacy.org/wiki/display/DP/DNS+Privacy+Daemon+-+Stubby):
> Stubby is an application that acts as a local DNS Privacy stub resolver (using DNS-over-TLS). Stubby encrypts DNS queries sent from a client machine (desktop or laptop) to a DNS Privacy resolver increasing end user privacy.

As of version 0.3 Stubby also supports DNS-over-HTTPs. This Docker image contains version 0.3.

Dnsmasq is a lightweight and small footprint DHCP and DNS server. You can read more about it on its [documentation](http://www.thekelleys.org.uk/dnsmasq/doc.html) page. Dnsmasq can answer DNS queries from a local file as well as forward to an upstream server. 

This Stubby + Dnsmasq Docker image packages the two together. It sets up Stubby listening on port 8053 with Dnsmasq listening on port 53 and forwarding to Stubby port 8053. I use NextDNS, so the Stubby config points to NextDNS currently but you can change it (_and should do so as it currently uses my configuration ID_).

## s6-overlay
I also took the opportunity to setup an [s6-overlay](https://github.com/just-containers/s6-overlay). I like their philosophy of a Docker container being “one thing” rather than “one process per container”. This is why I chose to create one image for both Stubby & Docker instead of separate images. It was surprisingly easy to setup.

The `etc` folder contains a `services.d` folder that holds the service definitions for Stubby and Dnsmasq. Dnsmasq is set to depend on Stubby via a `dependencies` file so they start in the correct order. The config files and service definitions are intentionally set to run Stubby and Dnsmasq in the foreground. That’s because s6 expects them to run in the foreground. Moreover, each service runs under a separate non-root user account.

## Configuring
The `root` folder has the following structure.

```
root
├── etc
│   ├── dnsmasq
│   │   └── dnsmasq.conf
│   ├── dnsmasq.d
│   │   ├── dnsmasq.conf
│   │   ├── dnsmasq.conf.orig
│   │   └── README.txt
│   ├── services.d
│   │   ├── dnsmasq
│   │   │   ├── dependencies
│   │   │   └── run
│   │   └── stubby
│   │       └── run
│   └── stubby
│       ├── stubby.orig.yml
│       └── stubby.yml
└── usr
    └── sbin
        └── dnsmasq-reload
```

### Dnsmasq
The `dnsmasq.d` folder is of interest if you want to tweak the Dnsmasq config or add zones etc. All it currently has is a README file and the original  `dnsmasq.conf`  zone file.  Out of the box Dnsmasq is setup to answer DNS queries by forwarding to Stubby and does not offer DHCP or any additional DNS zones. 

When the image is built the contents of this folder are copied into it at `/etc/dnsmasq.d`, but during runtime a new docker volume and mapped to this location *within the container*. Since the new docker volume is empty upon creation, the first time the container is run the contents of `/etc/dnsmasq.d` are copied from the container to this volume. If you then make any changes to this folder from within the container it will be stored in the docker volume.

Dnsmasq is set to pull in any files ending with `*.conf` from this folder into the running config.

You can edit the file via `docker exec` like thus:
```
docker exec -it stubby-dnsmasq vi /etc/dnsmasq.d/somefile.conf
```

Or you copy a file from outside the container to it:
```
docker cp somefile.conf stubby-dnsmasq:/etc/dnsmasq.d/
```

After making changes reload unload so it pulls in this config. The `/usr/sbin/dnsmasq-reload` script does that. Run it thus:
```
docker exec stubby-dnsmasq dnsmasq-reload
```

### Stubby
Stubby doesn't need any configuring but it would be a good idea to change the upstream DNS servers after downloading this repo and before building the image. 

When the image is built the `stubby` folder is copied into it as `/etc/stubby`, but during runtime a new docker volume is created and mapped to this location within the container (similar to what I do above). Since this volume is empty the first time, the contents of `/etc/stubby` are copied over to this docker volume but any subsequent changes its contents are stored in the docker volume. 

You can edit the config file or copy from outside the container using similar commands as above. 

## Building & Running
The quickest way to get started after cloning/ downloading this repo is to use the `./buildimage.sh` file. It takes two arguments - the architecture you are building for, and the name you want to give the image (this is optional, defaults to `rakheshster/docker-stubby-dnsmasq`). The architecture matters because the s6 binaries are per architecture.

This script builds the image, which involves compiling the stubby sources and installing the dnsmasq package… all of it on an Alpine Linux base with a topping of s6-overlay. There’s probably fancier ways of doing this than a shell script, but this is what suited me. You could skip the script and do a `docker build` too -  the script is just a wrapper to run this command with some checks of the architecture and cleaning up of the intermediate images.

After the image is built you can run it manually via `docker run` or you use the `./createcontainer.sh` script which takes the image name and container name as mandatory parameters and optionally the IP address and network of the container. I tend to use a macvlan network to run this so the container has its own IP address on my network.

### Systemd integration
The `./createcontainer.sh` script doesn’t run the container. It creates the container and also creates a systemd service unit file along with some instructions on what to do with it. This way you have systemd managing the container so it always starts after a system reboot. The unit file and systemd integration is optional of course; I wanted the container to always start after a reboot as it provides DNS for my home lab and is critical, that’s why I went through this extra effort.

Note: The service unit file is set to only restart if the service is aborted. This is intentional in case you want to `docker stop` the container sometime.

## Notes
This is my second Docker image. If it's of interest, I have a similar [Stubby + Unbound](https://github.com/rakheshster/docker-stubby-unbound) image. 

While creating this Stubby + Dnsmasq image I spent some time setting up multistage builds and thinking about how to store data. Again, nothing fancy but all of this was a learning experience for me so I am quite pleased. These learnings are now incorporated in the [Stubby + Unbound](https://github.com/rakheshster/docker-stubby-unbound) image too. 

I have since updated both images with other things I've picked up (e.g. multi-arch builds). 
