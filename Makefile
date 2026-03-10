.PHONY: build push

IMAGE ?= gcr.io/$(GCP_PROJECT)/automation-runner:latest

build:
	docker build -t $(IMAGE) -f scripts/cloudrun/Dockerfile .

push: build
	docker push $(IMAGE)
