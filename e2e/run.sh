#!/usr/bin/env bash
# Tests e2e : vérifie que Kyverno, installé dans un vrai cluster, bloque
# les manifests dangereux et laisse passer l'application conforme.
# Prérequis : kubectl pointe vers un cluster où Kyverno est installé.
set -euo pipefail
cd "$(dirname "$0")/.."

failures=0
pass() { printf '  \033[32m✔\033[0m %s\n' "$1"; }
fail() { printf '  \033[31m✘\033[0m %s\n' "$1"; failures=$((failures + 1)); }

echo "==> Application des policies"
kubectl apply -R -f policies/
kubectl wait --for=condition=Ready clusterpolicy --all --timeout=180s

echo "==> Génération : NetworkPolicy default-deny dans un nouveau namespace"
kubectl create namespace e2e --dry-run=client -o yaml | kubectl apply -f -
for _ in $(seq 1 30); do
  kubectl get networkpolicy default-deny-ingress -n e2e >/dev/null 2>&1 && break
  sleep 2
done
if kubectl get networkpolicy default-deny-ingress -n e2e >/dev/null 2>&1; then
  pass "NetworkPolicy default-deny-ingress générée dans e2e"
else
  fail "NetworkPolicy default-deny-ingress absente du namespace e2e"
fi

echo "==> Admission : chaque manifest non conforme doit être refusé"
for manifest in e2e/denied/*.yaml; do
  expected=$(sed -n 's/^# expect: //p' "$manifest")
  description=$(head -n 1 "$manifest" | sed 's/^# //')
  if output=$(kubectl apply --dry-run=server -f "$manifest" 2>&1); then
    fail "$description : accepté alors qu'il devait être bloqué par $expected"
  elif grep -q "$expected" <<<"$output"; then
    pass "$description → bloqué par $expected"
    grep -v '^\s*$' <<<"$output" | sed 's/^/      /'
  else
    fail "$description : refusé, mais pas par $expected"
    echo "$output" | sed 's/^/      /'
  fi
done

echo "==> Mutation : un Pod sans profil seccomp reçoit RuntimeDefault"
seccomp=$(kubectl run mutate-check -n e2e --dry-run=server -o jsonpath='{.spec.securityContext.seccompProfile.type}' \
  --image=registry.k8s.io/pause:3.10 \
  --labels=app.kubernetes.io/name=mutate-check,app.kubernetes.io/part-of=e2e \
  --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":65532},"containers":[{"name":"mutate-check","image":"registry.k8s.io/pause:3.10","securityContext":{"allowPrivilegeEscalation":false,"readOnlyRootFilesystem":true,"capabilities":{"drop":["ALL"]}},"resources":{"requests":{"cpu":"10m","memory":"16Mi"},"limits":{"memory":"32Mi"}}}]}}')
if [[ "$seccomp" == "RuntimeDefault" ]]; then
  pass "seccompProfile RuntimeDefault ajouté automatiquement"
else
  fail "seccompProfile attendu RuntimeDefault, obtenu '${seccomp}'"
fi

echo "==> Application conforme : déploiement réel"
kubectl apply -f examples/secure-app/namespace.yaml -f examples/secure-app/deployment.yaml
if kubectl rollout status deployment/web -n secure-app --timeout=180s; then
  pass "examples/secure-app déployée et Ready"
else
  fail "examples/secure-app ne démarre pas"
  kubectl describe pods -n secure-app || true
fi

echo
if ((failures > 0)); then
  echo "$failures test(s) en échec"
  exit 1
fi
echo "Tous les tests e2e sont passés."
