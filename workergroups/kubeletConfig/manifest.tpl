{{- define "workergroups.kubeletConfig.manifest" -}}
{{ printf `
{{- $name                        := index .observed.composite.resource.metadata.labels "crossplane.io/claim-name"  }}
{{- $namespace                   := index .observed.composite.resource.metadata.labels "crossplane.io/claim-namespace"  }}
{{- $clusterName                 := index .observed.composite.resource.spec.parameters "clusterName" }}
{{- $obs                         := (get .observed.resources "cluster-observed" | default (dict)) -}}

{{- $kubeletConfigObjectExists   := false }}
{{- $kubeletConfigurationExists  := false }}
{{- $kubeletConfigNameObject     := printf "%%s-kubeletconfig" $name }}
{{- $kubeletConfigName           := printf "%%s-%%s-kubeletconfig" $clusterName $name | lower }}

{{- $clusterUid                  := "" }}

{{ if hasKey .observed.resources (printf "%%s-kubeletconfig" $name) }}
  {{- $kubeletConfigObjectExists = true }}
{{- end }}

{{ if hasKey .observed.composite.resource.spec.parameters "kubeletConfiguration" }}
  {{- $kubeletConfigurationExists = true }}
{{- end }}

{{- $clusterUid = dig "resource" "status" "atProvider" "manifest" "metadata" "uid" "" $obs -}}

{{- if or $kubeletConfigObjectExists $kubeletConfigurationExists }}
---
apiVersion: kubernetes.crossplane.io/v1alpha2
kind: Object
metadata:
  name: {{ $kubeletConfigNameObject }}
  annotations:
    gotemplating.fn.crossplane.io/composition-resource-name: {{ $kubeletConfigNameObject }}
    gotemplating.fn.crossplane.io/ready: "True"
spec:
  forProvider:
    manifest:
      apiVersion: kubelet.cluster.x-k8s.io/v1beta1
      kind: KubeletConfig
      metadata:
        name: {{ $kubeletConfigName }}
        namespace: {{ $namespace }}
        labels:
          cluster.x-k8s.io/cluster-name: {{ $clusterName }}
        {{- if $clusterUid }}
        ownerReferences:
          - apiVersion: cluster.x-k8s.io/v1beta2
            kind: Cluster
            name: {{ $clusterName }}
            uid: {{ $clusterUid }}
            controller: true
            blockOwnerDeletion: true
        {{- end }}
      spec:
        kubeletConfiguration:
        {{- with .observed.composite.resource.spec.parameters.kubeletConfiguration }}
          {{ toYaml . | nindent 10 }}
        {{- end }}
{{- end }}



` }}
{{- end -}}
