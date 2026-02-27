{{- define "usages.workerGroupClient" -}}
- name: "usage-client-wg-cluster"
  {{ include "base.usages.default" . | nindent 2 }}
  patches:
    - toFieldPath: spec.of.resourceRef.name
      fromFieldPath: spec.parameters.clusterName
      transforms:
        - type: string
          string:
              type: Format
              fmt: "%s-cluster"
      policy:
        fromFieldPath: Required
    - toFieldPath: spec.by.resourceRef.name
      fromFieldPath: metadata.labels["crossplane.io/claim-name"]
      transforms:
        - type: string
          string:
              type: Format
              fmt: "%s-machinedeployment"
      policy:
        fromFieldPath: Required
{{- end -}}