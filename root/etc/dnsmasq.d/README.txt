Any files added here with a .conf extension will be pulled in by dnsmasq. 

You can do `docker exec <container name> reload-dnsmasq` to cause dnsmasq to reload and pull in the changes. Or restart the container, but that will have downtime. 