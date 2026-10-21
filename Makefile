KYVERNO_CHART_VERSION ?= 3.8.1
CLUSTER ?= policy-lab

.PHONY: test lint cluster e2e clean

## Tests unitaires des policies (CLI Kyverno, sans cluster)
test:
	kyverno test tests/

lint:
	yamllint --strict .

## Cluster kind local avec Kyverno installé
cluster:
	kind create cluster --name $(CLUSTER)
	helm repo add kyverno https://kyverno.github.io/kyverno/ --force-update
	helm install kyverno kyverno/kyverno --version $(KYVERNO_CHART_VERSION) \
		--namespace kyverno --create-namespace --wait --timeout 5m

## Tests e2e sur le cluster courant
e2e:
	./e2e/run.sh

clean:
	kind delete cluster --name $(CLUSTER)
