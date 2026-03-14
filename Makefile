.PHONY: build push qa-overlap qa-prod-gate qa-prod-gate-execute

IMAGE ?= gcr.io/$(GCP_PROJECT)/automation-runner:latest

build:
	docker build -t $(IMAGE) -f scripts/cloudrun/Dockerfile .

push: build
	docker push $(IMAGE)

qa-overlap:
	bash scripts/qa/review-overlap.sh

qa-prod-gate:
	bash scripts/qa/production-readiness-gate.sh

qa-prod-gate-execute:
	bash scripts/qa/production-readiness-gate.sh --execute-shutdown --strict
