# A playground for exploring Nextflow and nf-core

This repository is a place to explore Nextflow and nf-core functions in the Devcontainer/Codespaces or local environment. It also hosts two reference documents (below) used when building real pipelines.

## Getting started

### Devcontainer / Codespaces

Open this repository in the [Devcontainer](https://containers.dev/) (VS Code or GitHub Codespaces). Its [Dockerfile](.devcontainer/Dockerfile) is local to this repo and provides:
- Git
- Docker (via the `docker-in-docker` devcontainer feature)
- Apptainer
- Conda (Miniforge)
- [Pixi](https://pixi.sh/), which in turn installs and manages the Nextflow toolchain (see [`pixi.toml`](pixi.toml) for exact versions):
  - Nextflow
  - nf-core
  - nf-test
  - GitHub CLI (`gh`)

### Local, without the devcontainer

Install [Pixi](https://pixi.sh/), then run `pixi install` to get the same Nextflow toolchain. You'll need to install a container platform (Docker or Apptainer) or Conda yourself, since the devcontainer's Dockerfile doesn't run outside the container.

### Running things

```bash
pixi run test        # runs `nextflow run main.nf`
pixi run clean-work   # cleans up to the last run
pixi run clean-all    # discards uncommitted changes and removes all untracked/ignored files (except the Pixi environment)
```

## Reference documents

- [`Implementation_patterns.md`](Implementation_patterns.md) — a reference for idiomatic Nextflow/DSL2 syntax, Groovy patterns, and common pitfalls.
- [`Pipeline_building_instructions.md`](Pipeline_building_instructions.md) — a development protocol for scaffolding and building nf-core-style pipelines, from initial audit through final assembly. Written for use with an LLM coding assistant (e.g. Claude Code) as well as human developers.

## Explore

Each snippet below is a self-contained thing to try — paste it into `main.nf` in place of the existing workflow/process, then run `pixi run test` (or `nextflow run main.nf`) to see it in action.

<details>
<summary>Explore shell commands in a process:</summary>

  ```nextflow
  workflow {
      def ch_in = channel.of( 1..3 )
      def prc_task = TASK( ch_in )
      prc_task.view()
  }

  process TASK {
      input:
      val num

      script:
      """
      echo "Num: $num"
      """

      output:
      stdout
  }
  ```
</details>
<details>
<summary>Explore channel operator output:</summary>

  ```nextflow
  workflow {
      def ch_in = channel.of( 'A' )
      ch_in
          // Convert channel entry to Map
          .map { entry -> [ letter: entry ] }
          .view()
      // TASK()
  }

  // process TASK {
      // input:

      // script:
      // """
      // """

      // output:
  // }
  ```
</details>
<details>
<summary>Explore configuration settings:</summary>

  ```nextflow
  workflow {
      TASK()
  }

  process TASK {
      input:

      script:
      """
      touch versions.{txt,yml}
      """

      output:
      path "versions.txt", emit: txt
      path "versions.yml", emit: yml
  }
  ```

  ```nextflow
  // Attempt to exclude versions.yml from output via a negated glob — failed
  process.publishDir = [ path: "results", pattern: "{!versions.yml}" ]
  ```
</details>
<details>
<summary>Explore using Groovy in Nextflow:</summary>

  ```nextflow
  // Does subMap work on a key that isn't present? Yes.
  println ( [ id: 'test' ].subMap( ['id', 'sample'] ) )

  // workflow {
      // TASK()
  // }

  // process TASK {
      // input:

      // script:
      // """
      // """

      // output:
  // }
  ```
</details>
