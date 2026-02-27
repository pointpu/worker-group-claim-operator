{{- define "workergroups.extraResources.machineDeploymentObserver" -}}
- name: machineDeploymentObserver
  base:
    apiVersion: kubernetes.crossplane.io/v1alpha2
    kind: Object
    metadata:
      name: mock-md-observer
      annotations:
        crossplane.io/composition-resource-name: machineDeploymentObserver
    spec:
      deletionPolicy: Orphan
      watch: true
      managementPolicies:
        - Observe
      forProvider:
        manifest:
          apiVersion: cluster.x-k8s.io/v1beta2
          kind: MachineDeployment
          metadata:
            name:
            namespace:
  patches:
    {{- include "workergroups.extraResources.patches.machineDeploymentObserver" . | nindent 4 }}
{{- end -}}