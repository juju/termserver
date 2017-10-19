BASE=ubuntu:lts
LXC=/snap/bin/lxc
INSTANCE=termserver-$(shell date +'%s')
IMAGE=build/termserver.tar.gz

DEBS=python3-pip python3-setuptools python3-tornado python3-wheel
REMOVEDEBS=python3-pip python3-setuptools python3-wheel

default: dev


$(LXC):
	snap install lxd


$(IMAGE): $(LXC)
# Starting the LXC instance.
	$(LXC) launch $(BASE) $(INSTANCE)

	sleep 10 # Wait for the network to be ready (we can do better than sleep).

# Configuring the LXC instance.
	$(LXC) exec $(INSTANCE) -- apt update
	$(LXC) exec $(INSTANCE) -- apt install --no-install-recommends -y $(DEBS)
	$(LXC) exec $(INSTANCE) -- pip3 install terminado
	$(LXC) exec $(INSTANCE) -- apt remove -y $(REMOVEDEBS)
	$(LXC) exec $(INSTANCE) -- apt autoremove -y

# Setting up the internal service.
	$(LXC) file push ./files/termserver.service $(INSTANCE)/etc/systemd/system/
	$(LXC) file push -p -r src/* $(INSTANCE)/opt/termserver
	$(LXC) exec $(INSTANCE) -- systemctl enable termserver

# Set up juju
	$(LXC) file push ./files/juju $(INSTANCE)/usr/bin/

# Disable unnecessary services
	$(LXC) file push ./files/setup-systemd.sh $(INSTANCE)/tmp/
	$(LXC) exec $(INSTANCE) /tmp/setup-systemd.sh

# Saving the instance as an image.
	$(LXC) stop $(INSTANCE)
	$(LXC) publish $(INSTANCE) --alias $(INSTANCE)
	mkdir -p build
	$(LXC) image export $(INSTANCE) $(IMAGE)

# Cleaning up.
	$(LXC) delete $(INSTANCE)
	$(LXC) image delete $(INSTANCE)

	@echo "----------------------------- success -----------------------------"
	@echo "new image is ready at $(IMAGE)"
	@echo "to import it:  lxc image import $(IMAGE) --alias termserver"
	@echo "to publish it: charm attach ~yellow/jujushell termserver=$(IMAGE)"


.PHONY: image
image: $(IMAGE)


.PHONY: clean
clean:
	rm -rf build/* devenv


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
	$(LXC) launch termserver-image-test termserver-test
	$(LXC) image delete termserver-image-test
	sleep 10 # Wait for the network to be ready (we can do better than sleep).

	@echo "----------------------------- results -----------------------------"
	@echo "delete the instance in case of failure: lxc delete -f termserver-test"
	./files/check.sh termserver-test
	$(LXC) delete -f termserver-test
