# devolutions-server-helm

Helm chart for deploying [Devolutions Server](https://devolutions.net/server/) on Kubernetes.

## Chart Documentation

See [chart/README.md](chart/README.md) for full installation instructions, values reference, and upgrade procedures.

## Development

### Prerequisites

- [Helm](https://helm.sh/docs/intro/install/) 3.x

### Lint

```bash
helm lint chart/
```

### Template rendering

```bash
helm template test chart/ \
  --set dvls.hostname=test.example.com \
  --set database.host=db.example.com \
  --set database.name=testdb \
  --set certificate.issuerName=letsencrypt
```

## Releasing

Releases are automated via GitHub Actions. Trigger the `release` workflow to:

1. Create a GitHub release tagged with the chart version from `chart/Chart.yaml`
2. Package and publish the chart to the [Devolutions Helm repository](https://devolutions.github.io/helm-charts)

## License

Copyright 2026 Devolutions Inc.

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at

<http://www.apache.org/licenses/LICENSE-2.0>

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.
