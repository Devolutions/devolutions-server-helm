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

Releases are automated via GitHub Actions. When `chart/Chart.yaml` is updated on `master`, the `release` workflow:

1. Creates a GitHub release tagged with the chart version
2. Detects the release type (Beta, Stable, LTS) from the commit message
3. For Beta releases, appends a `-beta` suffix to the chart version and marks the GitHub release as a prerelease
4. Packages and publishes the chart to the [Devolutions Helm repository](https://devolutions.github.io/helm-charts)

Beta chart versions use a SemVer pre-release identifier (e.g., `2026.1.3-beta`), so Helm only shows them when using `--devel`. See [chart/README.md](chart/README.md#release-channels) for details.

## License

Copyright 2026 Devolutions Inc.

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at

<http://www.apache.org/licenses/LICENSE-2.0>

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.
