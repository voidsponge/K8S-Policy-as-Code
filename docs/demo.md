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

Extrait réel d'un run GitHub Actions, sur un cluster kind avec Kyverno v1.18.1 :

```console
==> Admission : chaque manifest non conforme doit être refusé
  ✔ Image Docker Hub non approuvée → bloqué par restrict-image-registries
      Error from server: error when creating "e2e/denied/10-restrict-image-registries.yaml":
      admission webhook "validate.kyverno.svc-fail" denied the request:
      resource Deployment/e2e/bad-10 was blocked due to the following policies
      restrict-image-registries:
        autogen-allowed-registries: 'validation error: Image refusée : seuls registry.k8s.io/*,
          cgr.dev/chainguard/* et ghcr.io/voidsponge/* sont autorisés. rule autogen-allowed-registries
          failed at path /spec/template/spec/containers/0/image/'
  ...
==> Mutation : un Pod sans profil seccomp reçoit RuntimeDefault
  ✔ seccompProfile RuntimeDefault ajouté automatiquement
==> Application conforme : déploiement réel
deployment "web" successfully rolled out
  ✔ examples/secure-app déployée et Ready

Tous les tests e2e sont passés.
```

Le refus arrive **avant** que la ressource n'existe : aucun Pod n'est créé, et le message
indique au développeur la règle, la raison et le champ exact à corriger.

## 4. Essayer soi-même

Sur le cluster de `make cluster`, avec les policies appliquées :

```console
$ kubectl create namespace sandbox
$ kubectl create deployment pirate --image=nginx -n sandbox
```

Le Deployment est refusé par plusieurs policies à la fois (registre, tag, root, ressources…).
Corriger le manifest en s'inspirant de `examples/secure-app/deployment.yaml` jusqu'à ce qu'il
passe, puis vérifier que le namespace a bien reçu sa NetworkPolicy :

```console
$ kubectl get networkpolicy -n sandbox
NAME                   POD-SELECTOR   AGE
default-deny-ingress   <none>         10s
```
