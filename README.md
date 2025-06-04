# A playground for exploring Nextflow and nf-core

This repository is a place to explore Nextflow and nf-core functions in the Devcontainer/Codespaces or local environment.

The [Devcontainer](https://containers.dev/) environment (a docker container) comes installed with:
- Git
- Docker
- Apptainer
- Conda
- Nextflow
- nf-core
- nf-test

The [Dockerfile](https://github.com/nf-core/tools/blob/master/nf_core/gitpod/gitpod.Dockerfile) for this environment lives on nf-core/tools.

Alternatively, you can use [Pixi](https://pixi.sh/) to run Nextflow in a local conda-like environment. You'll need to install a container platform or conda yourself to run workflows with a package manager.

## Explore

<details>
<summary>Explore shell commands in a process:</summary>

  ```nextflow
  workflow {
      TASK( Channel.of( 1..3 ) )
          .view()
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
      Channel.of( 'A' )
          // Convert channel entry to Map
          .map { it -> [ letter: it ] }
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
      path "versions.txt"
      path "versions.yml"
  }
  ```

  ```nextflow
  // Try excluding versions.yml from output - Failed
  process.publishDir = [ path: "results", pattern: "{!versions.yml}" ]
  ```
</details>
<details>
<summary>Explore using Groovy in Nextflow:</summary>

  ```nextflow
  // Can I use subMap on a key not present - yes
  println ( [ id: 'test' ].subMap( ['id','sample'] ) )

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
