{{- define "workergroups.extraResources.cluster" -}}
- name: "cluster-observed"
  base:
    apiVersion: kubernetes.crossplane.io/v1alpha2
    kind: Object
    metadata:
      name: 
      annotations:
        uptest.upbound.io/timeout: "60"
    spec:
      deletionPolicy: Orphan
      managementPolicies:
        - Observe
      forProvider:
        manifest:
          apiVersion: cluster.x-k8s.io/v1beta2
          kind: Cluster
          metadata:
            name:
            namespace:
  patches:
    {{- include "workergroups.extraResources.patches.cluster" . | nindent 4 }}
{{- end -}}