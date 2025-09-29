![BloodHound CE running in a Virtual Machine](https://github.com/redteamronin/dev-random/BloodHoundCE/images/BloodHoundCE.png)

# BloodHound CE

I've been embracing BloodHound more and more. Sometimes setting it up can get in the way.
SpecterOps has a quality guide on how to set up BloodHound CE. One of the prerequistes is Docker Desktop.
I run BloodHound in a VM on VirtualBox. I'm well aware there are other virtualization software out there
that would alleviate my pain. I'm sometimes stubborn in where I'll invest my time throubleshooting.

In VirtualBox or Docker Desktop isn't it. I'm only offering what I found to work and that's all.

With that: let me explain.

## Docker Desktop

Regardless of OS, I've consistently run into the issue with Docker Destkop and the virtualization not jiving
between what I set with VBoxManage and inside the OS.

SpecterOps outlines at #1 to install Docker Desktop - this is where I hit my head the first time
- https://bloodhound.specterops.io/get-started/quickstart/community-edition-quickstart#install-bloodhound-ce

Docker Desktop will install but won't start in a VM because of the lack of virtualization support.

## Bypassing Docker Desktop

If we use just the install guide for Docker on Linux, we get the brief commands below:
- https://docs.docker.com/engine/install/ubuntu/#install-using-the-repository

```
# Add Docker's official GPG key:
sudo apt-get update
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
```

Then install our components:
```
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

Lastly add our account to the docker usergroup:
```
sudo usermod -aG docker mrbishop
```
- I logoff and back on

## Bloodhound CE

Back to the SpecterOps Bloodhound CE install guide: https://bloodhound.specterops.io/get-started/quickstart/community-edition-quickstart#install-bloodhound-ce

The process is you curl, unpack, the use the downloaded file to `install`. This will complain if you didn't
install Docker Desktop. It will say the deamon isn't running and for me, that is where I also pivot to a 
different plan to start up my bloodhound CE environment:
- https://github.com/SpecterOps/BloodHound/blob/main/examples/docker-compose/docker-compose.yml

Bloodhound is kind of doing this anyway. We are just going to do it in a way that feels a bit dated (like 5 years ago).

```
curl -L https://github.com/SpecterOps/BloodHound/blob/main/examples/docker-compose/docker-compose.yml -o docker-compose.yml
docker compose pull & docker compose up
```
- docker compose will look for a docker-compose.yml file in the working directory
- check the output of the terminal, the initial password to login to the web interface will be in there

## Accessing BloodHound CE:

After a bit, you should be able to get to `http://localhost:8080` - you should be redirected to the login page

## FIN:

This is what I do to use Bloodhound CE in a VM that I can throw away pretty easily. Just my preference.
