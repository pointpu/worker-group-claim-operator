{{- define "workergroups.begetMachineTemplate.manifest" -}}
{{ printf `

{{- $xr                             := .observed.composite.resource -}}
{{- $p                              := $xr.spec.parameters -}}
                   
{{- $name                           := dig "metadata" "labels" "crossplane.io/claim-name" "" $xr -}}
{{- $namespace                      := dig "metadata" "labels" "crossplane.io/claim-namespace" "" $xr -}}  

{{- $clusterName                    := dig "clusterName" "" $p -}}
{{- $cpuCount                       := dig "configuration" "cpuCount" 4 $p -}}
{{- $memory                         := dig "configuration" "memory" 6144 $p -}}
{{- $diskSize                       := dig "configuration" "diskSize" 61440 $p -}}                 
{{- $image                          := dig "image" "" $p -}}
{{- $managedBy                      := dig "managedBy" "system" $p -}}
{{- $networkTag                     := dig "networkTag" "vps" $p -}}
{{- $serverName                     := dig "serverName" "" $p -}}
{{- $usePrivateNetwork              := dig "usePrivateNetwork" true $p -}}

{{- $ctxParams                      := printf "cpu=%%v;mem=%%v;disk=%%v" $cpuCount $memory $diskSize -}}
{{- $ctxParamsHash                  := (sha256sum $ctxParams | trunc 10 | lower) -}}

{{- $begetMachineTemplateName       := printf "%%s-%%s-%%s" $clusterName $name $ctxParamsHash -}}
{{- $begetMachineTemplateNameObject := printf "%%s-begetmachinetemplate" $name -}}

---
apiVersion: kubernetes.crossplane.io/v1alpha2
kind: Object
metadata:
  name: {{ $begetMachineTemplateNameObject }}
  annotations:
    gotemplating.fn.crossplane.io/composition-resource-name: begetmachinetemplate-wg
    gotemplating.fn.crossplane.io/ready: "True"
spec:
  forProvider:
    manifest:
      apiVersion: infrastructure.cluster.x-k8s.io/v1beta2
      kind: BegetMachineTemplate
      metadata:
        name: {{ $begetMachineTemplateName  }}
        namespace: {{ $namespace }}
        labels:
          cluster.x-k8s.io/cluster-name: {{ $clusterName }}
      spec:
        template:
          spec:
            configuration:
              cpuCount: {{ $cpuCount }}
              diskSize: {{ $diskSize }}
              memory: {{ $memory }}
            image: {{ $image | quote }}
            managedBy: {{ $managedBy | quote }}
            serverName: {{ $serverName | quote }}
            usePrivateNetwork: {{ $usePrivateNetwork }}
            networkTag: {{ $networkTag | quote }}
            providerID: ""

` }}
{{- end -}}
