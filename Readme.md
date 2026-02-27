# Техническое задание: WorkerGroupClaim Operator

## 1. Общее описание

Kubernetes-оператор, управляющий жизненным циклом Worker Group для ClusterAPI. Оператор принимает декларативный набор переменных через `WorkerGroupClaim`, рендерит их через внешние шаблоны (`WGBootstrapTemplate`, `WGMachineTemplate`) и создаёт итоговые ClusterAPI-ресурсы.

### 1.1. Проблема

Текущая схема через Crossplane Composition:
- Не поддерживает гранулярную стратегию обновления immutable-шаблонов (BegetMachineTemplate, KubeadmConfigTemplate).
- Требует ручного контроля за удалением устаревших шаблонов.
- Не отслеживает завершение rolling-update перед удалением старых ресурсов.
- Сложна в отладке из-за промежуточных XR/XRD слоёв.
- Шаблоны зашиты в Composition, изменение структуры шаблона требует обновления Composition.

### 1.2. Решение

Dedicated-оператор с тремя CRD:

| CRD | Scope | Роль |
|-----|-------|------|
| `WGBootstrapTemplate` | **Cluster** | Go-template для KubeadmConfigTemplate. Содержит шаблон с `{{ .переменные }}` |
| `WGMachineTemplate` | **Cluster** | Go-template для BegetMachineTemplate. Содержит шаблон с `{{ .переменные }}` |
| `WorkerGroupClaim` | Namespaced | Набор плоских переменных + параметры MachineDeployment. Ссылается на оба шаблона |

Оператор:
- Берёт переменные из `WorkerGroupClaim.spec.bootstrap` → рендерит через `WGBootstrapTemplate` → создаёт `KubeadmConfigTemplate`.
- Берёт переменные из `WorkerGroupClaim.spec.infrastructure` → рендерит через `WGMachineTemplate` → создаёт `BegetMachineTemplate`.
- При изменении переменных — создаёт новую ревизию шаблона, обновляет ссылку в `MachineDeployment`, удаляет старую ревизию **только после** успешного завершения rollout.

---

## 2. CRD: WGBootstrapTemplate

**Cluster-scoped** шаблон для генерации `KubeadmConfigTemplate`. Содержит Go-template в поле `value`. Один шаблон может использоваться из любого namespace множеством `WorkerGroupClaim`.

### 2.1. API

```
apiVersion: workergroup.cluster.x-k8s.io/v1alpha1
kind: WGBootstrapTemplate
```

### 2.2. Спецификация

```yaml
apiVersion: workergroup.cluster.x-k8s.io/v1alpha1
kind: WGBootstrapTemplate
metadata:
  name: default-bootstrap
  # cluster-scoped — без namespace
spec:
  value: |
    apiVersion: bootstrap.cluster.x-k8s.io/v1beta2
    kind: KubeadmConfigTemplate
    spec:
      template:
        spec:
          format: cloud-config
          files:
            - path: /etc/containerd/config.toml
              owner: root:root
              permissions: "0644"
              content: |
                version = 2
                imports = ["/etc/containerd/conf.d/*.toml"]

            - path: /etc/default/containerd/download.env
              owner: root:root
              permissions: "0644"
              content: |
                COMPONENT_VERSION="{{ .containerdVersion }}"
                REPOSITORY="https://github.com/containerd/containerd/releases/download"

            - path: /etc/default/containerd/download-script.sh
              owner: root:root
              permissions: "0755"
              content: |
                #!/bin/bash
                set -Eeuo pipefail
                COMPONENT_VERSION="${COMPONENT_VERSION:-{{ .containerdVersion }}}"
                REPOSITORY="${REPOSITORY:-https://github.com/containerd/containerd/releases/download}"
                # ... остальной скрипт установки ...

            - path: /etc/default/runc/download.env
              owner: root:root
              permissions: "0644"
              content: |
                COMPONENT_VERSION="{{ .runcVersion }}"
                REPOSITORY="https://github.com/opencontainers/runc/releases/download"

            - path: /etc/default/crictl/download.env
              owner: root:root
              permissions: "0644"
              content: |
                COMPONENT_VERSION="{{ .crictlVersion }}"
                REPOSITORY="https://github.com/kubernetes-sigs/cri-tools/releases/download"

            - path: /etc/default/kubeadm/download.env
              owner: root:root
              permissions: "0644"
              content: |
                COMPONENT_VERSION="{{ .kubeadmVersion }}"
                REPOSITORY="https://dl.k8s.io"

            - path: /etc/default/kubectl/download.env
              owner: root:root
              permissions: "0644"
              content: |
                COMPONENT_VERSION="{{ .kubectlVersion }}"
                REPOSITORY="https://dl.k8s.io"

            - path: /etc/default/kubelet/download.env
              owner: root:root
              permissions: "0644"
              content: |
                COMPONENT_VERSION="{{ .kubeletVersion }}"
                REPOSITORY="https://dl.k8s.io"

            # ... systemd units (статические, без переменных) ...

            - path: /etc/default/kubelet/extra-args.env
              owner: root:root
              permissions: "0644"
              content: |
                KUBELET_EXTRA_ARGS="--provider-id=beget:///{{ "{{" }} ds.meta_data.instance_id.split(':')[0] {{ "}}" }}"

            - path: /etc/containerd/certs.d/docker.io/hosts.toml
              owner: root:root
              permissions: "0644"
              content: |
                server = "https://docker.io"
                [host."https://{{ .registryMirrorAddress }}/repository/registry-1-docker-io"]
                  capabilities = ["pull", "resolve"]
                  priority = 1.0
                  skip_verify = false
                [host."https://registry-1.docker.io"]
                  capabilities = ["pull", "resolve"]
                  priority = 2.0
                  skip_verify = false

            - path: /etc/containerd/certs.d/registry.k8s.io/hosts.toml
              owner: root:root
              permissions: "0644"
              content: |
                server = "https://registry.k8s.io"
                [host."https://{{ .registryMirrorAddress }}/repository/registry-k8s-io"]
                  capabilities = ["pull", "resolve"]
                  priority = 1.0
                  skip_verify = false
                [host."https://registry.k8s.io"]
                  capabilities = ["pull", "resolve"]
                  priority = 2.0
                  skip_verify = false

            # ... аналогично для gcr.io, ghcr.io, quay.io, и т.д. ...

          joinConfiguration:
            nodeRegistration:
              imagePullPolicy: IfNotPresent
              kubeletExtraArgs:
                - name: cloud-provider
                  value: external
                - name: cluster-dns
                  value: "{{ .clusterDNS }}"
                - name: cluster-domain
                  value: "{{ .clusterDomain }}"
                - name: config
                  value: /var/lib/kubelet/config-custom.yaml
                - name: node-labels
                  value: "{{ .nodeLabels }}"
              taints: []

          preKubeadmCommands:
            - apt install -y wget tree net-tools conntrack socat jq
            - export KUBEADM_CONFIG_FILE=$(find /var/run/kubeadm/*.yaml)
            - export ADVERTISE_ADDRESS=$(ip -j addr show eth1 | jq -r '.[].addr_info[] | select(.family == "inet") | .local')
            - envsubst < ${KUBEADM_CONFIG_FILE} > ${KUBEADM_CONFIG_FILE}.tmp && mv ${KUBEADM_CONFIG_FILE}.tmp ${KUBEADM_CONFIG_FILE}
            - modprobe overlay
            - modprobe br_netfilter
            - sysctl --system
            - systemctl restart containerd-install.service
            - systemctl enable runc-install
            - systemctl start runc-install
            - systemctl enable crictl-install
            - systemctl start crictl-install
            - systemctl enable kubectl-install
            - systemctl start kubectl-install
            - systemctl enable kubeadm-install
            - systemctl start kubeadm-install
            - systemctl enable kubelet
            - systemctl enable kubelet-install
            - systemctl start kubelet-install
            - systemctl enable containerd
            - systemctl enable containerd-install
            - systemctl start containerd
            - systemctl restart systemd-resolved

          users:
            - name: capv
              shell: /bin/bash
              sudo: "ALL=(ALL) NOPASSWD:ALL"
              sshAuthorizedKeys:
              {{ .sshAuthorizedKeys | toYamlList | indent 14 }}
```

Шаблон **не содержит** `metadata.name`, `metadata.namespace`, `metadata.labels`, `metadata.ownerReferences` — это оператор добавит сам при создании итогового ресурса.

---

## 3. CRD: WGMachineTemplate

**Cluster-scoped** шаблон для генерации `BegetMachineTemplate`. Аналогичная структура. Один шаблон может использоваться из любого namespace множеством `WorkerGroupClaim`.

### 3.1. API

```
apiVersion: workergroup.cluster.x-k8s.io/v1alpha1
kind: WGMachineTemplate
```

### 3.2. Спецификация

```yaml
apiVersion: workergroup.cluster.x-k8s.io/v1alpha1
kind: WGMachineTemplate
metadata:
  name: default-machine
  # cluster-scoped — без namespace
spec:
  value: |
    apiVersion: infrastructure.cluster.x-k8s.io/v1beta2
    kind: BegetMachineTemplate
    spec:
      template:
        spec:
          configuration:
            cpuCount: {{ .cpuCount }}
            diskSize: {{ .diskSize }}
            memory: {{ .memory }}
          image: "{{ .image }}"
          managedBy: system
          networkTag: "{{ .networkTag }}"
          providerID: ""
          serverName: ""
          usePrivateNetwork: {{ .usePrivateNetwork }}
```

---

## 4. CRD: WorkerGroupClaim

### 4.1. API

```
apiVersion: workergroup.cluster.x-k8s.io/v1alpha1
kind: WorkerGroupClaim
```

### 4.2. Спецификация (spec)

Блоки `infrastructure` и `bootstrap` — **плоский `map[string]string`**, без вложенности. Каждый ключ маппится 1:1 на `{{ .ключ }}` в соответствующем шаблоне. Набор ключей произвольный — CRD не фиксирует конкретные имена переменных.

```yaml
apiVersion: workergroup.cluster.x-k8s.io/v1alpha1
kind: WorkerGroupClaim
metadata:
  name: c5ce2e
  namespace: godjee
  labels:
    beget.com/display-name: godjee3000
spec:
  clusterName: c9b2e5-client
  replicas: 1
  version: v1.30.4

  # Ссылка на шаблон для BegetMachineTemplate
  machineTemplateRef:
    name: default-machine

  # Ссылка на шаблон для KubeadmConfigTemplate
  bootstrapTemplateRef:
    name: default-bootstrap

  # Плоский набор переменных → WGMachineTemplate → BegetMachineTemplate
  # Каждый ключ = {{ .ключ }} в шаблоне. Произвольный набор.
  infrastructure:
    cpuCount: "4"
    memory: "4096"
    diskSize: "30720"
    image: "k8s-customer:latest"
    usePrivateNetwork: "true"
    networkTag: "vps"
    sshKeyIds:
    - @dobry_kot
    - @shynie42
    - @Mistrikoff
    - @godjee"

  # Плоский набор переменных → WGBootstrapTemplate → KubeadmConfigTemplate
  # Каждый ключ = {{ .ключ }} в шаблоне. Произвольный набор.
  bootstrap:
    containerdVersion: "1.7.19"
    runcVersion: "v1.1.12"
    crictlVersion: "v1.30.0"
    kubeadmVersion: "v1.30.4"
    kubectlVersion: "v1.30.4"
    kubeletVersion: "v1.30.4"
    clusterDNS: "29.64.0.10"
    clusterDomain: "cluster.local"
    registryMirrorAddress: "100.87.0.13"

  # Taints на нодах (передаются в MachineDeployment напрямую, без шаблонизации)
  taints:
    - key: testkey
      value: testvalue
      effect: PreferNoSchedule
      propagation: Always

  # Labels на нодах (передаются в MachineDeployment.spec.template.metadata.labels)
  nodeLabels:
    environment: production
    workload-type: general

  rollout:
    strategy:
      type: RollingUpdate
      rollingUpdate:
        maxSurge: 1
        maxUnavailable: 1

  nodeDrainTimeout: 1m
```

### 4.3. Важные свойства `infrastructure` и `bootstrap`

| Свойство | Описание |
|----------|----------|
| Тип | `map[string]string` |
| Вложенность | Запрещена. Все значения — строки |
| Набор ключей | Произвольный. CRD не ограничивает имена |
| Маппинг | 1:1 — ключ `foo` становится `{{ .foo }}` в шаблоне |
| Хеш | SHA256 от **всего содержимого** map (каноническая сериализация) |
| Валидация | Оператор при рендеринге проверяет, что все `{{ .* }}` в шаблоне имеют значение |

### 4.4. Статус (status)

```yaml
status:
  phase: Ready | Provisioning | Updating | Deleting | Failed

  currentTemplates:
    begetMachineTemplate: "c9b2e5-client-c5ce2e-bmt-a3f8c1d2"
    kubeadmConfigTemplate: "c9b2e5-client-c5ce2e-kct-dae26c58"

  # Результат последнего рендеринга — для отладки
  lastRendered:
    infrastructureHash: "a3f8c1d2"
    bootstrapHash: "dae26c58"
    # Ошибки рендеринга, если есть
    errors: []

  pendingDeletion:
    - kind: BegetMachineTemplate
      name: "...-bmt-old12345"
    - kind: KubeadmConfigTemplate
      name: "...-kct-old67890"

  machineDeploymentStatus:
    name: "c9b2e5-client-c5ce2e"
    desiredReplicas: 1
    readyReplicas: 1
    upToDateReplicas: 1
    conditions: [...]

  conditions:
    - type: Ready
      status: "True"
      reason: AllResourcesReady
    - type: TemplatesRendered
      status: "True"
    - type: RolloutComplete
      status: "True"
```

---

## 5. Процесс рендеринга

### 5.1. Пайплайн

```
┌──────────────────┐     ┌───────────────────┐     ┌────────────────────┐
│ WorkerGroupClaim │     │ WGMachineTemplate  │     │ WGBootstrapTemplate│
│                  │     │                    │     │                    │
│ infrastructure:  │     │ spec.value: |      │     │ spec.value: |      │
│   cpuCount: "4"  │     │   ...              │     │   ...              │
│   memory: "4096" │     │   {{ .cpuCount }}  │     │   {{ .clusterDNS }}│
│                  │     │   {{ .memory }}    │     │   ...              │
│ bootstrap:       │     │                    │     │                    │
│   clusterDNS:... │     │                    │     │                    │
└────────┬─────────┘     └────────┬───────────┘     └────────┬───────────┘
         │                        │                          │
         │  infrastructure vars   │                          │
         ├───────────────────────►│                          │
         │                        │                          │
         │               ┌────────▼──────────┐              │
         │               │ Go template.Execute│              │
         │               │ (vars → template)  │              │
         │               └────────┬──────────┘              │
         │                        │                          │
         │                        ▼                          │
         │               BegetMachineTemplate                │
         │               (rendered YAML)                     │
         │                                                   │
         │  bootstrap vars                                   │
         ├──────────────────────────────────────────────────►│
         │                                          ┌────────▼──────────┐
         │                                          │ Go template.Execute│
         │                                          │ (vars → template)  │
         │                                          └────────┬──────────┘
         │                                                   │
         │                                                   ▼
         │                                          KubeadmConfigTemplate
         │                                          (rendered YAML)
         │
         │  + metadata (name с hash, namespace, ownerRef, labels)
         │  + MachineDeployment (replicas, version, taints, labels, refs)
         ▼
    Apply to cluster
```

### 5.2. Шаги рендеринга

1. **Загрузить шаблоны** — по `spec.machineTemplateRef` и `spec.bootstrapTemplateRef`.
2. **Подготовить переменные** — взять `spec.infrastructure` (map[string]string) и `spec.bootstrap` (map[string]string).
3. **Выполнить Go template** — `template.Execute(wgMachineTemplate.spec.value, infrastructure)` → получить rendered YAML для BegetMachineTemplate.
4. **Выполнить Go template** — `template.Execute(wgBootstrapTemplate.spec.value, bootstrap)` → получить rendered YAML для KubeadmConfigTemplate.
5. **Валидация** — проверить, что все placeholder'ы в шаблоне получили значение. Если нет — записать ошибку в `status.lastRendered.errors`, установить condition `TemplatesRendered=False`.
6. **Вычислить hash** — `SHA256(rendered YAML)[:8]`.
7. **Обернуть в metadata** — добавить `name` (с hash), `namespace`, `labels`, `ownerReferences`.
8. **Сравнить hash с текущим** — если совпадает → ничего не делать. Если отличается → создать новый ресурс, обновить ref в MachineDeployment.

### 5.3. Доступные template-функции

Помимо стандартных Go template функций, оператор предоставляет:

| Функция | Описание | Пример |
|---------|----------|--------|
| `toYamlList` | Преобразует comma-separated строку в YAML list | `{{ .sshKeys \| toYamlList }}` |
| `indent N` | Добавляет отступ в N пробелов | `{{ .block \| indent 8 }}` |
| `quote` | Оборачивает в кавычки | `{{ .val \| quote }}` |
| `default` | Значение по умолчанию | `{{ .val \| default "fallback" }}` |
| `b64enc` | Base64 encode | `{{ .cert \| b64enc }}` |

### 5.4. Экранирование Go-template внутри cloud-init

KubeadmConfigTemplate содержит cloud-init Jinja-шаблоны (напр. `{{ ds.meta_data.instance_id }}`), которые **не должны** интерпретироваться Go template engine. Для этого используется экранирование:

```yaml
# В WGBootstrapTemplate:
content: |
  KUBELET_EXTRA_ARGS="--provider-id=beget:///{{ "{{" }} ds.meta_data.instance_id.split(':')[0] {{ "}}" }}"

# После рендеринга Go template:
content: |
  KUBELET_EXTRA_ARGS="--provider-id=beget:///{{ ds.meta_data.instance_id.split(':')[0] }}"
```

---

## 6. Полный пример: от Claim до результата

### 6.1. Входные данные

**WGMachineTemplate** `default-machine`:

```yaml
spec:
  value: |
    apiVersion: infrastructure.cluster.x-k8s.io/v1beta2
    kind: BegetMachineTemplate
    spec:
      template:
        spec:
          configuration:
            cpuCount: {{ .cpuCount }}
            diskSize: {{ .diskSize }}
            memory: {{ .memory }}
          image: "{{ .image }}"
          managedBy: system
          networkTag: "{{ .networkTag }}"
          providerID: ""
          serverName: ""
          usePrivateNetwork: {{ .usePrivateNetwork }}
```

**WorkerGroupClaim** `c5ce2e`:

```yaml
spec:
  clusterName: c9b2e5-client
  replicas: 1
  version: v1.30.4
  machineTemplateRef:
    name: default-machine
  bootstrapTemplateRef:
    name: default-bootstrap
  infrastructure:
    cpuCount: "4"
    memory: "4096"
    diskSize: "30720"
    image: "k8s-customer:latest"
    usePrivateNetwork: "true"
    networkTag: "vps"
```

### 6.2. Результат рендеринга

Оператор выполняет `template.Execute(value, infrastructure)` и получает:

```yaml
apiVersion: infrastructure.cluster.x-k8s.io/v1beta2
kind: BegetMachineTemplate
metadata:
  # ── добавляется оператором ──
  name: c9b2e5-client-c5ce2e-bmt-897131eb
  namespace: godjee
  labels:
    cluster.x-k8s.io/cluster-name: c9b2e5-client
    workergroup.cluster.x-k8s.io/claim-name: c5ce2e
  ownerReferences:
    - apiVersion: workergroup.cluster.x-k8s.io/v1alpha1
      kind: WorkerGroupClaim
      name: c5ce2e
      uid: 0599a254-5535-4594-befc-2500a22b5a4d
spec:
  # ── из рендеринга шаблона ──
  template:
    spec:
      configuration:
        cpuCount: 4
        diskSize: 30720
        memory: 4096
      image: "k8s-customer:latest"
      managedBy: system
      networkTag: "vps"
      providerID: ""
      serverName: ""
      usePrivateNetwork: true
```

### 6.3. MachineDeployment (формируется оператором напрямую, без шаблона)

```yaml
apiVersion: cluster.x-k8s.io/v1beta2
kind: MachineDeployment
metadata:
  name: c9b2e5-client-c5ce2e
  namespace: godjee
  labels:
    cluster.x-k8s.io/cluster-name: c9b2e5-client
    cluster.x-k8s.io/deployment-name: c9b2e5-client-c5ce2e
    workergroup.cluster.x-k8s.io/claim-name: c5ce2e
  ownerReferences:
    - apiVersion: workergroup.cluster.x-k8s.io/v1alpha1
      kind: WorkerGroupClaim
      name: c5ce2e
      uid: {claimUID}
spec:
  clusterName: c9b2e5-client
  replicas: 1                                    # ← spec.replicas
  rollout:                                       # ← spec.rollout
    strategy:
      type: RollingUpdate
      rollingUpdate:
        maxSurge: 1
        maxUnavailable: 1
  selector:
    matchLabels:
      cluster.x-k8s.io/cluster-name: c9b2e5-client
  template:
    metadata:
      labels:
        cluster.x-k8s.io/cluster-name: c9b2e5-client
        node-group.beget.com/name: c9b2e5-client-c5ce2e
        environment: production                  # ← spec.labels
        workload-type: general                   # ← spec.labels
    spec:
      bootstrap:
        configRef:
          apiGroup: bootstrap.cluster.x-k8s.io
          kind: KubeadmConfigTemplate
          name: c9b2e5-client-c5ce2e-kct-dae26c58  # ← текущий rendered KCT
      clusterName: c9b2e5-client
      infrastructureRef:
        apiGroup: infrastructure.cluster.x-k8s.io
        kind: BegetMachineTemplate
        name: c9b2e5-client-c5ce2e-bmt-897131eb    # ← текущий rendered BMT
      nodeDrainTimeout: 1m                       # ← spec.nodeDrainTimeout
      taints:                                    # ← spec.taints
        - key: testkey
          value: testvalue
          effect: PreferNoSchedule
          propagation: Always
      version: v1.30.4                           # ← spec.version
```

---

## 7. Управляемые ресурсы

| Ресурс | Источник | Immutable | Стратегия обновления |
|--------|----------|-----------|---------------------|
| `BegetMachineTemplate` | Рендер `WGMachineTemplate` + `infrastructure` vars | **Да** | Create-new → update-ref → delete-old |
| `KubeadmConfigTemplate` | Рендер `WGBootstrapTemplate` + `bootstrap` vars | **Да** | Create-new → update-ref → delete-old |
| `MachineDeployment` | Формируется оператором напрямую | Нет | In-place update |

### 7.1. Именование

```
MachineDeployment:      {clusterName}-{claimName}
BegetMachineTemplate:   {clusterName}-{claimName}-bmt-{hash8}
KubeadmConfigTemplate:  {clusterName}-{claimName}-kct-{hash8}
```

`{hash8}` — первые 8 символов SHA-256 от **rendered YAML** (результат template.Execute). Это обеспечивает:
- Уникальность при изменении переменных **или** шаблона.
- Идемпотентность — одинаковые переменные + шаблон = одинаковый hash.

### 7.2. Owner References

Все rendered-ресурсы получают `ownerReference` на `WorkerGroupClaim`.
`WGBootstrapTemplate` и `WGMachineTemplate` — **не owned**, это cluster-scoped разделяемые ресурсы.

---

## 8. Логика reconcile

### 8.1. Основной цикл

```
┌───────────────────────────────────────────────────────┐
│              WorkerGroupClaim (spec changed)           │
└──────────────────────┬────────────────────────────────┘
                       │
         ┌─────────────▼─────────────┐
         │  Загрузить WGMachineTemplate │
         │  и WGBootstrapTemplate       │
         └─────────────┬─────────────┘
                       │
         ┌─────────────▼─────────────┐
         │  Render infrastructure     │
         │  vars → WGMachineTemplate  │
         │  = rendered BMT YAML       │
         │                            │
         │  Render bootstrap          │
         │  vars → WGBootstrapTemplate│
         │  = rendered KCT YAML       │
         └─────────────┬─────────────┘
                       │
         ┌─────────────▼─────────────┐
         │  Hash rendered BMT YAML    │
         │  Hash rendered KCT YAML    │
         │  Compare with current      │
         └──────┬──────┬──────┬──────┘
                │      │      │
     ┌──────────▼┐ ┌───▼────┐ ┌▼──────────────┐
     │BMT hash   │ │KCT hash│ │MD fields      │
     │changed?   │ │changed?│ │changed?        │
     └─────┬─────┘ └───┬────┘ │(replicas,taints│
           │            │      │ labels,version)│
    ┌──────▼─────┐ ┌────▼────┐ └───┬───────────┘
    │Create new  │ │Create   │     │
    │BMT resource│ │new KCT  │     │
    │with hash   │ │resource │     │
    └──────┬─────┘ └────┬────┘     │
           │            │          │
           └──────┬─────┘          │
                  │                │
    ┌─────────────▼────────────────▼────┐
    │  Update MachineDeployment:        │
    │  - infrastructureRef (if changed) │
    │  - bootstrap.configRef (if changed)│
    │  - replicas, version, taints,     │
    │    labels, rollout                │
    └──────────────┬────────────────────┘
                   │
    ┌──────────────▼────────────────┐
    │  Запомнить old templates в    │
    │  status.pendingDeletion       │
    │  phase = Updating             │
    └──────────────┬────────────────┘
                   │
    ┌──────────────▼────────────────┐
    │  Ждать rollout complete:      │
    │  RollingOut=False AND         │
    │  upToDateReplicas=replicas    │
    └──────────────┬────────────────┘
                   │
    ┌──────────────▼────────────────┐
    │  Удалить pendingDeletion      │
    │  phase = Ready                │
    └───────────────────────────────┘
```

### 8.2. Вычисление hash

Hash вычисляется от **rendered YAML** (результат template.Execute), а не от входных переменных. Это значит:
- Изменение переменных → новый rendered YAML → новый hash → новый ресурс.
- Изменение шаблона (WGBootstrapTemplate/WGMachineTemplate) → новый rendered YAML → новый hash → новый ресурс.
- Оба триггера обрабатываются единообразно.

```
hash = SHA256(rendered_yaml_string)[:8]
```

### 8.3. Watch-стратегия

Оператор watch'ит:
- `WorkerGroupClaim` — основной триггер.
- `WGBootstrapTemplate` — при изменении шаблона пересчитать все Claim'ы, которые на него ссылаются.
- `WGMachineTemplate` — аналогично.
- `MachineDeployment` — для отслеживания статуса rollout и проброса в status Claim.

### 8.4. Условия обновления

| Что изменилось | BMT | KCT | MD |
|---------------|-----|-----|----|
| `infrastructure.*` (любая переменная) | NEW | — | update ref |
| `bootstrap.*` (любая переменная) | — | NEW | update ref |
| `WGMachineTemplate.spec.value` | NEW | — | update ref |
| `WGBootstrapTemplate.spec.value` | — | NEW | update ref |
| `replicas` | — | — | in-place update |
| `version` | — | — | in-place update |
| `taints` | — | — | in-place update |
| `labels` | — | — | in-place update |
| `rollout` | — | — | in-place update |

### 8.5. Обработка удаления (Finalizer)

При удалении `WorkerGroupClaim`:
1. `phase: Deleting`.
2. Удалить `MachineDeployment` (ClusterAPI удалит Machine → Node).
3. Удалить текущие BMT и KCT.
4. Удалить ресурсы из `pendingDeletion`.
5. Снять finalizer.

---

## 9. Обработка ошибок и edge-cases

### 9.1. Ошибка рендеринга шаблона

Если шаблон содержит `{{ .foo }}`, а в `infrastructure`/`bootstrap` нет ключа `foo`:
- Рендеринг падает.
- `status.lastRendered.errors` = `["template: missing variable 'foo' in infrastructure"]`.
- Condition `TemplatesRendered=False`.
- Ресурсы **не создаются/не обновляются**.
- Предыдущее рабочее состояние сохраняется.

### 9.2. Rollout зависает

Если `MachineDeployment.spec.progressDeadlineSeconds` (default 300s) превышен:
- Оператор **не** удаляет старые шаблоны.
- Condition `RolloutComplete=False`, reason `ProgressDeadlineExceeded`.
- Пользователь может откатить, вернув старые переменные.

### 9.3. Повторное изменение во время rollout

1. Создать новый шаблон с актуальными переменными.
2. Обновить ref в MachineDeployment (перезаписать rollout).
3. Добавить предыдущий шаблон в `pendingDeletion`.
4. После завершения rollout — удалить всё из `pendingDeletion`.

### 9.4. Оператор перезапустился

При старте:
1. Перечитать все `WorkerGroupClaim`.
2. По `status.currentTemplates` и `status.pendingDeletion` восстановить состояние.
3. Проверить, завершился ли rollout, и подчистить `pendingDeletion`.

### 9.5. Orphaned templates

Периодический reconcile (каждые 5 минут) ищет BMT/KCT с label `workergroup.cluster.x-k8s.io/claim-name`, не упоминаемые ни в `currentTemplates`, ни в `pendingDeletion`, старше 10 минут. Удаляет как orphans.

### 9.6. Шаблон удалён или не найден

Если `WGBootstrapTemplate` или `WGMachineTemplate` не найден:
- Condition `TemplatesRendered=False`, reason `TemplateNotFound`.
- Ресурсы **не обновляются**.
- Предыдущее рабочее состояние сохраняется.

---

## 10. Наблюдаемость

### 10.1. Events

| Event | Type | Reason | Когда |
|-------|------|--------|-------|
| Шаблон отрендерен | Normal | TemplateRendered | Успешный render |
| Создан BMT | Normal | InfrastructureTemplateCreated | Новый BegetMachineTemplate |
| Создан KCT | Normal | BootstrapTemplateCreated | Новый KubeadmConfigTemplate |
| Обновлён MD | Normal | MachineDeploymentUpdated | Обновлены ссылки/параметры |
| Rollout начат | Normal | RolloutStarted | MD начал rolling update |
| Rollout завершён | Normal | RolloutComplete | MD завершил rolling update |
| Удалён старый шаблон | Normal | StaleTemplateDeleted | Очистка после rollout |
| Ошибка рендеринга | Warning | RenderError | Шаблон не отрендерился |
| Шаблон не найден | Warning | TemplateNotFound | Ref указывает на несуществующий ресурс |
| Rollout timeout | Warning | RolloutTimeout | Превышен progressDeadline |



## 12. Диаграмма взаимосвязей

```
                         Cluster-scoped (без namespace)
          ┌─────────────────────────────────────────────────────┐
          │                                                     │
          │  ┌─────────────────────┐  ┌──────────────────────┐  │
          │  │  WGMachineTemplate  │  │ WGBootstrapTemplate  │  │
          │  │  name: default-     │  │ name: default-       │  │
          │  │        machine      │  │       bootstrap      │  │
          │  │                     │  │                      │  │
          │  │  spec.value: |      │  │ spec.value: |        │  │
          │  │    {{ .cpuCount }}  │  │   {{ .clusterDNS }}  │  │
          │  │    {{ .memory }}    │  │   {{ .runcVersion }} │  │
          │  │    ...              │  │   ...                │  │
          │  └──────────┬──────────┘  └──────────┬───────────┘  │
          │             │                        │              │
          └─────────────┼────────────────────────┼──────────────┘
                        │ machineTemplateRef      │ bootstrapTemplateRef
                        │                        │
          ┌──────────▼──────────────────────────────▼───────────┐
          │                 WorkerGroupClaim                     │
          │  spec:                                              │
          │    clusterName, replicas, version                   │
          │    infrastructure: {cpuCount: "4", memory: "4096"} │
          │    bootstrap: {clusterDNS: "29.64.0.10", ...}      │
          │    taints, labels, rollout                          │
          └──────┬──────────────┬───────────────┬──────────────┘
                 │              │               │
          owns   │       owns   │        owns   │
                 ▼              ▼               ▼
     ┌───────────────┐ ┌────────────────┐ ┌─────────────────┐
     │ BegetMachine  │ │ KubeadmConfig  │ │ MachineDeployment│
     │ Template      │ │ Template       │ │                  │
     │ (rendered,    │ │ (rendered,     │ │ infrastructureRef ──► BMT
     │  immutable)   │ │  immutable)    │ │ bootstrap.configRef──► KCT
     │               │ │                │ │                  │
     │ hash: abc123  │ │ hash: def456   │ │ replicas, version│
     └───────────────┘ └────────────────┘ │ taints, labels   │
                                          └────────┬─────────┘
                                                   │ manages
                                                   │ (ClusterAPI)
                                                   ▼
                                          ┌────────────────┐
                                          │  MachineSet    │
                                          │  → Machine     │
                                          │  → Node        │
                                          └────────────────┘
```

---

## 13. Сценарии обновления

### 13.1. Изменение переменной infrastructure

```
Пользователь: spec.infrastructure.memory: "4096" → "8192"

Оператор:
  1. Загрузить WGMachineTemplate
  2. Render(template, {cpuCount:"4", memory:"8192", ...})
  3. Hash нового rendered YAML ≠ текущий → создать новый BMT
  4. Обновить MD.spec.template.spec.infrastructureRef.name
  5. Ждать rollout → удалить старый BMT
```

### 13.2. Изменение переменной bootstrap

```
Пользователь: spec.bootstrap.containerdVersion: "1.7.19" → "1.7.25"

Оператор:
  1. Загрузить WGBootstrapTemplate
  2. Render(template, {containerdVersion:"1.7.25", ...})
  3. Hash ≠ текущий → создать новый KCT
  4. Обновить MD.spec.template.spec.bootstrap.configRef.name
  5. Ждать rollout → удалить старый KCT
```

### 13.3. Изменение самого шаблона WGBootstrapTemplate

```
Платформенный инженер: обновил WGBootstrapTemplate.spec.value (добавил новый файл)

Оператор (через watch на WGBootstrapTemplate):
  1. Найти все WorkerGroupClaim, ссылающиеся на этот шаблон
  2. Для каждого: re-render → новый hash → создать новый KCT
  3. Обновить ref в MD → rollout → удалить старый
```

### 13.4. Изменение replicas/taints/labels

```
Пользователь: spec.replicas: 1 → 3

Оператор:
  1. Обновить MD.spec.replicas = 3
  2. Шаблоны НЕ пересоздаются
```

### 13.5. Добавление новой переменной

```
Платформенный инженер:
  1. Добавил {{ .newVar }} в WGBootstrapTemplate
  2. Добавил newVar: "value" в WorkerGroupClaim.spec.bootstrap

Оператор:
  1. Re-render шаблона → новый KCT с новым hash
  2. Rollout
```

---

## 17. Открытые вопросы

1. **Версионирование шаблонов** — нужен ли механизм pinning версии шаблона в Claim? Сейчас Claim всегда использует текущее состояние шаблона.

2. **Webhook-валидация** — ValidatingWebhook для проверки: шаблон парсится, все переменные имеют значения.

3. **Defaulting** — MutatingWebhook для значений по умолчанию (rollout strategy, nodeDrainTimeout).

---

## 18. Механизм Pause

Аннотация на `WorkerGroupClaim` для приостановки reconcile:

```yaml
metadata:
  annotations:
    workergroup.cluster.x-k8s.io/paused: "true"
```

### 18.1. Поведение при paused=true

- Оператор **пропускает** весь reconcile loop для этого Claim.
- Никакие ресурсы не создаются, не обновляются, не удаляются.
- `pendingDeletion` не обрабатывается — старые шаблоны сохраняются.
- Condition `Paused=True` устанавливается в status.
- Event `Normal` / `Paused` — при переходе в paused-состояние.

### 18.2. Поведение при снятии pause

- Оператор выполняет полный reconcile: загружает шаблоны, рендерит, сравнивает hash.
- Если за время паузы переменные или шаблоны изменились — создаёт новые ресурсы, запускает rollout.
- Обрабатывает накопленные `pendingDeletion`.
- Event `Normal` / `Resumed`.

### 18.3. Сценарии использования

- **Экстренная остановка** — при проблемах с rollout, пауза предотвращает дальнейшие изменения.
- **Batch-обновление** — поставить на паузу, изменить несколько переменных, снять паузу — один rollout вместо нескольких.
- **Отладка** — исследовать состояние без вмешательства оператора.
