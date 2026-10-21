# Démo

## 1. Vérifier un manifest sans cluster

La CLI Kyverno applique les policies en local, idéal en pre-commit ou dans la CI d'une
équipe applicative. Un Deployment qui tire `nginx` depuis Docker Hub :

```console
$ kyverno apply policies/ --resource e2e/denied/10-restrict-image-registries.yaml
policy restrict-image-registries -> resource e2e/Deployment/bad-10 failed:
1 - autogen-allowed-registries validation error: Image refusée : seuls registry.k8s.io/*,
    cgr.dev/chainguard/* et ghcr.io/voidsponge/* sont autorisés.
    rule autogen-allowed-registries failed at path /spec/template/spec/containers/0/image/

pass: 13, fail: 1, warn: 0, error: 0, skip: 1
```

La policy est écrite pour les Pods, mais la règle `autogen-…` montre que Kyverno l'a
traduite automatiquement pour le Deployment.

## 2. Les tests unitaires

```console
$ make test
...
Test Summary: 72 tests passed and 0 tests failed
```

## 3. Sur un vrai cluster

```console
$ make cluster   # kind + Kyverno via Helm
$ make e2e
```

Le script applique les policies, puis tente de déployer chaque manifest de `e2e/denied/` :
chacun doit être refusé par la policy annoncée dans son en-tête. Il vérifie ensuite la
mutation (seccomp ajouté), la génération (NetworkPolicy dans un nouveau namespace) et
déploie l'application conforme jusqu'à ce qu'elle soit `Ready`.

## 4. Essayer soi-même

```console
$ kubectl create deployment pirate --image=nginx
error: failed to create deployment: admission webhook "validate.kyverno.svc-fail" denied the request: ...
```

Puis corriger le manifest en s'inspirant de `examples/secure-app/deployment.yaml` jusqu'à ce
qu'il passe.
