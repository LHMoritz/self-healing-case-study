1. First install the instana agent on the cluster:

kubectl apply -f https://github.com/instana/instana-agent-operator/releases/latest/download/instana-agent-operator.yaml

2. Apply the instana agent yaml file:

kubectl apply -f instana-agent.yaml

3. Install the webhook for instana autotracing via helm. For the instana password check on the downloadkey within any installation guide on the instana dashboard for installing new agents.

helm install --create-namespace --namespace instana-autotrace-webhook instana-autotrace-webhook \
  --repo https://agents.instana.io/helm instana-autotrace-webhook \
  --set webhook.imagePullCredentials.password=<your-instana-password>

