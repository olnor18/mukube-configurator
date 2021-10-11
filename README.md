# mukube-configurator

## About

This is the repository for the configuration of a bare metal high available kubernetes cluster with load-balancing services supported. Outputs a tarball that can should be unpacked in the root of a linux filesystem. The cluster assumes a systemd cgroups are used as well as CRIO as the container runtime.

## Structure
The entry point for the project is the make file in the root folder, which reads a config file for a full cluster setup.

### [config](docs/config.md)

### image_requirements.txt
All container images listed in this file will be downloaded and packed into the tarball. Used for offline setups, so that the images does not need to be pulled when the cluster is bootstrapping.

### helm_requirements.txt
All helm charts repos listed in this file will be downloaded and packed into the tarball. The charts will then be installed by the node that creates the cluster. Each line in the file should contain 3 things, seperated by a `%`: First the release name, second the namespace and lastly the url of the repo.


### Dependencies
A user in the docker group
Use this command to add the current user to docker and reboot.
`sudo usermod -aG docker $USER`

`e2fsprogs` is required for creating the ext4 filesystem.
