# API Genie GitHub Action

Lint, format and detect breaking changes in your API specs, right in your pull requests.

The action installs the [API Genie](https://apigenie.pl) CLI, `apigenie`, on a GitHub Actions
runner and lints, checks the formatting of, or diffs OpenAPI, Swagger 2.0, AsyncAPI, Protobuf and
GraphQL files. Issues and changes become annotations on the files of the pull request, and a
report is added to the job summary. Lint issues can also go to GitHub code scanning, and the diff
report to a pull request comment, both of which outlive the annotations.

## Quick start

```yaml
on: pull_request
jobs:
  api:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: mykulyak/api-genie-action@v0
        with:
          command: lint
          files: api/**/*.yaml
```

## Permissions

| Permission | When |
| --- | --- |
| `contents: read` | Always (the default token has it). |
| `security-events: write` | `sarif: true`, to upload lint issues to code scanning. |
| `pull-requests: write` | `pr-comment: true` (the default) with `command: diff`, to post the report as a comment. |

## Usage

### Lint

```yaml
on: pull_request
jobs:
  api:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: mykulyak/api-genie-action@v0
        with:
          command: lint
          files: api/**/*.yaml
          config: apigenie.yaml
```

The step fails when an issue of severity `error` is reported. `fail-on: warning` also fails it on
warnings, `fail-on: never` never fails it on issues.

#### Code scanning

Annotations disappear once the files change. With `sarif: true`, the issues are also uploaded to
code scanning as SARIF: they show in the repository's Security tab and on the pull request, and
code scanning tracks them from run to run until they are fixed. The job needs the
`security-events: write` permission, and private repositories need GitHub Advanced Security:

```yaml
on: pull_request
permissions:
  contents: read
  security-events: write
jobs:
  api:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: mykulyak/api-genie-action@v0
        with:
          command: lint
          files: api/**/*.yaml
          sarif: true
```

The upload also happens when the step fails on issues. Steps that lint different files need
different `sarif-category` values, or each upload replaces the previous one. The `sarif-file`
output is the path of the file, e.g. to keep it as an artifact.

### Check the formatting

```yaml
      - uses: mykulyak/api-genie-action@v0
        with:
          command: format
          files: |
            api/openapi.yaml
            proto/*.proto
```

Runs `apigenie format --check`: nothing is written, and the step fails when a file is not
formatted. The files are listed in the summary and in the `changed-files` output. To format them
instead, install apigenie and run it yourself (see [Install only](#install-only)).

### Find breaking changes

```yaml
on: pull_request
jobs:
  api:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: mykulyak/api-genie-action@v0
        with:
          command: diff
          files: api/openapi.yaml
```

Each file is compared with its version at the base commit of the pull request (on a push: the
commit before it); set `base` to compare with another commit, branch or tag. The action fetches
the base commit when the checkout doesn't have it, which is the case with the default shallow
checkout; `fetch-depth: 0` in `actions/checkout` avoids the fetch. Files that don't exist at the
base are skipped. The step fails on breaking changes; use `fail-on: never` and the `status` output
to decide yourself:

```yaml
      - id: diff
        uses: mykulyak/api-genie-action@v0
        with:
          command: diff
          files: api/openapi.yaml
          fail-on: never
      - if: steps.diff.outputs.status == 'breaking'
        run: echo "This pull request breaks the API; bump the major version."
```

To compare two files of the tree, set `base-file` to the old one and `files` to the new one.

#### Pull request comment

On pull requests, the report is also posted as a comment, which later runs of the step update
instead of adding new ones; when a later commit reverts the changes, the comment says so. No
comment is created while there are no changes. The job needs the `pull-requests: write`
permission; without it (as for pull requests from forks, whose token is read-only), the step
only prints a warning:

```yaml
permissions:
  contents: read
  pull-requests: write
```

Each workflow job has its own comment; give steps of the same job different `pr-comment-key`
values to keep their reports apart. `pr-comment: false` turns the comment off.

### Install only

Without `command`, the action only installs apigenie and puts it on `PATH`:

```yaml
      - uses: mykulyak/api-genie-action@v0
        with:
          version: 0.9.0
      - run: apigenie bundle api/openapi.yaml --output dist/openapi.yaml
```

apigenie writes a `.apigenie.telemetry` file into its working directory (nothing is sent anywhere).
The action removes it after its own commands; when you run apigenie yourself, add the file to
`.gitignore` or remove it before committing.

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `version` | `latest` | apigenie version: `latest`, `X.Y.Z` or `cli-X.Y.Z`. `latest` is the newest release, or the newest pre-release while there is no release. 0.9.0 is the oldest version the action supports. |
| `command` | | `lint`, `format` or `diff`. Empty: only install apigenie. |
| `files` | | The files, one per line, or separated by spaces on a single line. Glob patterns such as `api/**/*.yaml` are expanded; a pattern that matches nothing is an error. |
| `config` | | The apigenie configuration file. |
| `formatter` | `unix` | The formatter of `lint` and `diff`. Only `unix` output becomes annotations and lint counts. |
| `report` | `changelog` | The report of `diff`: `status`, `changelog` or `detailed`. |
| `fail-on` | `error` | `error`: lint errors, unformatted files and breaking changes fail the step. `warning`: lint warnings too. `never`: none of them. Files apigenie can't read always fail it. |
| `base` | the pull request's base | For `diff`: the git ref to compare with. |
| `base-file` | | For `diff`: the old version of the single file of `files`. |
| `args` | | More arguments for the command, separated by spaces, e.g. `--proto-path proto`. |
| `annotations` | `true` | Whether issues and changes become annotations. |
| `summary` | `true` | Whether a report is added to the job summary. |
| `sarif` | `false` | For `lint`: whether the issues are also uploaded to code scanning. Needs `security-events: write`. |
| `sarif-category` | `apigenie` | The category of the SARIF upload. |
| `pr-comment` | `true` | For `diff` on pull requests: whether the report is posted as a comment updated in place. Needs `pull-requests: write`. |
| `pr-comment-key` | workflow/job | Tells apart the comments of several `diff` steps. |
| `github-token` | `github.token` | The token the comment is posted with. |
| `binary` | | An apigenie executable to use instead of downloading a release. |

## Outputs

| Output | Description |
| --- | --- |
| `version` | The apigenie version. |
| `path` | The path of the apigenie executable. |
| `cache-hit` | Whether apigenie was already installed by an earlier step of the job. |
| `status` | `lint`: `clean`, `warnings` or `errors`. `format`: `clean` or `changed`. `diff`: `none`, `non-breaking` or `breaking`. |
| `exit-code` | The exit status of apigenie. |
| `error-count`, `warning-count` | The lint errors and warnings (`unix` formatter). |
| `changed-files` | The files that are not formatted, one per line. |
| `sarif-file` | The path of the SARIF file (`lint` with `sarif: true`). |

## Runners

Linux x64 (`ubuntu-*`), macOS arm64 (`macos-14` and newer) and Windows x64 (`windows-*`) runners
are supported, hosted or self-hosted with bash 3.2 or newer (the bash of macOS), `curl` and
`git` (and `gh` for pull request comments). On other runners, the action fails.

GitHub shows at most 10 error and 10 warning annotations of a step on a pull request; all the
issues are in the step's log and in the job summary.

## Versions

The action is versioned like the rest of API Genie: 0.9.0 is its first published version, and
1.0.0 follows the CLI's. `mykulyak/api-genie-action@v0` moves with every 0.x release, and `@v1`
will move with every non-breaking 1.x release; pin a version (`@v0.9.0`) or a commit SHA for
reproducible workflows. The action's versions are otherwise independent of the CLI's: by default
it installs the latest CLI release, and the `version` input pins one.
Changes are listed in the [releases](https://github.com/mykulyak/api-genie-action/releases).

## Links

- [API Genie](https://apigenie.pl): the documentation of the CLI, its
  [configuration file](https://apigenie.pl/techdocs/reference/cli-configuration) and
  [this action](https://apigenie.pl/techdocs/reference/cli-github-action).
- [CLI releases](https://github.com/mykulyak/api-genie/releases), where the action downloads
  `apigenie` from.
- [Issues](https://github.com/mykulyak/api-genie-action/issues) of the action.

MIT License, see [LICENSE](LICENSE).
