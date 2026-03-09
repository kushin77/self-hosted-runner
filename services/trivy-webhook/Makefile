IMAGE=ghcr.io/kushin77/trivy-webhook
TAG=$(shell git rev-parse --short HEAD)

.PHONY: build push run

build:
	docker build -t $(IMAGE):$(TAG) .

push: build
	docker push $(IMAGE):$(TAG)

run:
	docker run --rm -p 8080:8080 \
	  -e GITHUB_TOKEN=$$GITHUB_TOKEN \
	  -e TRIVY_WEBHOOK_SECRET=shh \
	  $(IMAGE):$(TAG)
