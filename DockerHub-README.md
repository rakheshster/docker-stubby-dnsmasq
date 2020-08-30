# What is this?
This is a Docker image containing Stubby and Dnsmasq.

From the [Stubby documentation](https://dnsprivacy.org/wiki/display/DP/DNS+Privacy+Daemon+-+Stubby):
> Stubby is an application that acts as a local DNS Privacy stub resolver (using DNS-over-TLS). Stubby encrypts DNS queries sent from a client machine (desktop or laptop) to a DNS Privacy resolver increasing end user privacy.

As of version 0.3 Stubby also supports DNS-over-HTTPs. This Docker image contains version 0.3.

Dnsmasq is a lightweight and small footprint DHCP and DNS server. You can read more about it on its [documentation](http://www.thekelleys.org.uk/dnsmasq/doc.html) page. Dnsmasq can answer DNS queries from a local file as well as forward to an upstream server. 

This Stubby + Dnsmasq Docker image packages the two together. It sets up Stubby listening on port 8053 with Dnsmasq listening on port 53 and forwarding to Stubby port 8053.

# Versions
Version numbers are of the format `<stubby version>-<patch>` where `<patch>` will be incremented due to changes introduced by me (maybe a change to the `Dockerfile` or underlying Alpine/ s6 base).  

# Configuring
The `root` of this image has the following structure apart from the usual folders. 

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

## Dnsmasq
The `dnsmasq.d` folder is of interest if you want to configure Dnsmasq. All it currently has is a README file and the original `dnsmasq.conf` with the DNS bits removed and the DHCP bits commented out. Out of the box Dnsmasq is setup to answer DNS queries by forwarding to Stubby and does not offer DHCP or any additional DNS zones. The original `dnsmasq.conf` file too is left behind with an `.orig` extension for reference. 

Dnsmasq is set to pull in any files ending with `*.conf` from this folder into the running config. 

During runtime a new docker volume can be mapped to this location within the container. Since the new docker volume is empty upon creation, the first time the container is run the contents of `/etc/dnsmasq.d` will be copied from the container to this volume. If you then make any changes to this folder from within the container it will be stored in the docker volume. Of course, you can bind mount a folder from the host too but that will not make visible the existing contents in the image.

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

## Stubby
Stubby doesn't need any configuring but it would be a good idea to change the upstream DNS servers after downloading this repo and before building the image. 

The Stubby config file is at `/etc/stubby` and during runtime a new docker volume can be mapped to this location within the container (similar to what I do above). Since this volume is empty the first time, the contents of `/etc/stubby` will be copied over to this docker volume and any subsequent changes are stored in the docker volume. Of course, you can bind mount a folder from the host too but that will not make visible the existing contents in the image.

You can edit the config file or copy from outside the container using similar commands as above. 

# Source
The `Dockerfile` can be found in the [GitHub repository](https://github.com/rakheshster/docker-stubby-dnsmasq). 