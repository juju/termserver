BASE=ubuntu:bionic
LXC=/snap/bin/lxc
INSTANCE=termserver-$(shell date +'%s')
IMAGE=build/termserver.tar.gz
USERHOME=/home/ubuntu
PROFILE=termserver
SERVICE=./files/termserver.service

DEBS=jq python3-pip python3-setuptools python3-tornado python3-wheel
REMOVEDEBS=python3-pip python3-setuptools python3-wheel


ifdef LIMITED
	DEBS+=lshell
	SERVICE=./files/termserver-limited.service
	BASE=ubuntu:xenial
endif


default: help


$(LXC):
	snap install lxd


$(IMAGE): $(LXC) profile
# Start the LXC instance.
	$(LXC) launch $(BASE) $(INSTANCE) -p $(PROFILE)
	sleep 10 # Wait for the network to be ready (we can do better than sleep).

# Configure the LXC instance.
	$(LXC) exec $(INSTANCE) -- apt update
	$(LXC) exec $(INSTANCE) -- apt upgrade -y
	$(LXC) exec $(INSTANCE) -- apt install --no-install-recommends -y $(DEBS)
	$(LXC) exec $(INSTANCE) -- pip3 install terminado
	$(LXC) exec $(INSTANCE) -- apt remove -y $(REMOVEDEBS)
	$(LXC) exec $(INSTANCE) -- apt autoremove -y

# Set up the internal service.
	$(LXC) file push $(SERVICE) $(INSTANCE)/etc/systemd/system/termserver.service
	$(LXC) file push -p -r src/* $(INSTANCE)/opt/termserver
	$(LXC) exec $(INSTANCE) -- systemctl enable termserver
	$(LXC) exec $(INSTANCE) -- systemctl stop termserver

# Set up juju
	$(LXC) file push ./files/juju $(INSTANCE)/usr/bin/

# Set up kubectl
	$(LXC) exec $(INSTANCE) -- snap install kubectl --classic

# Set up postdeploy options
	$(LXC) exec $(INSTANCE) -- mkdir -p /home/ubuntu/bin
	$(LXC) exec $(INSTANCE) -- sh -c "echo 'PATH=$$PATH:/home/ubuntu/bin:/snap/bin' >> $(USERHOME)/.bashrc"
	$(LXC) file push ./files/k8s-postdeploy $(INSTANCE)$(USERHOME)/bin/k8s-postdeploy

# Disable unnecessary services.
	$(LXC) file push ./files/setup-systemd.sh $(INSTANCE)/tmp/
	$(LXC) exec $(INSTANCE) /tmp/setup-systemd.sh

# Set up shell customizations, like the prompt, the session manager, etc.
	$(LXC) file push ./files/jujushellrc $(INSTANCE)$(USERHOME)/.jujushellrc
	$(LXC) exec $(INSTANCE) -- sh -c "echo '. ~/.jujushellrc' >> $(USERHOME)/.bashrc"
	$(LXC) file push ./files/session.sh $(INSTANCE)$(USERHOME)/.session
	$(LXC) file push ./files/lshell.conf $(INSTANCE)/etc/lshell.conf

# Save the instance as an image.
	$(LXC) stop $(INSTANCE)
	$(LXC) publish $(INSTANCE) --alias $(INSTANCE)
	mkdir -p build
	$(LXC) image export $(INSTANCE) $(basename $(basename $(IMAGE)))

# Clean up.
	$(LXC) delete $(INSTANCE)
	$(LXC) image delete $(INSTANCE)

	@echo "----------------------------- success -----------------------------"
	@echo "new image is ready at $(IMAGE)"
	@echo "to import it:  lxc image import $(IMAGE) --alias termserver"
	@echo "to publish it: charm attach ~yellow/jujushell termserver=$(IMAGE)"


.PHONY: image
image: $(IMAGE)


.PHONY: profile
profile:
	$(LXC) profile delete $(PROFILE) 2> /dev/null || true
	$(LXC) profile create $(PROFILE)
	cat files/profile.yaml | $(LXC) profile edit $(PROFILE)


.PHONY: clean
clean:
	rm -rf build/* devenv
	$(LXC) profile delete $(PROFILE) 2> /dev/null || true


dev: devenv/bin/python


devenv/bin/python:
	virtualenv -p python3 devenv
	devenv/bin/pip install -r requirements.pip
	@echo "----------------------------- success -----------------------------"
	@echo "to run the server: devenv/bin/python src/termserver"


.PHONY: check
check: clean image
	@echo "----------------------------- testing -----------------------------"
	$(LXC) image import $(IMAGE) --alias termserver-image-test
	$(LXC) launch termserver-image-test termserver-test -p $(PROFILE)
	$(LXC) image delete termserver-image-test
	sleep 10 # Wait for the network to be ready (we can do better than sleep).

	@echo "----------------------------- results -----------------------------"
	@echo "delete the instance in case of failure: lxc delete -f termserver-test"
	./files/check.sh termserver-test
	$(LXC) delete -f termserver-test


.PHONY: help
help:
	@echo "make check - generate and test an image"
	@echo "make check LIMITED=1 - generate an image with a limited shell"
	@echo "make dev - create a development environment for the tornado app"
