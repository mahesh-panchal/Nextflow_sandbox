# A playground for exploring Nextflow and nf-core

This repository is a place to explore Nextflow and nf-core functions in the Gitpod environment.

[![Open in Gitpod](https://gitpod.io/button/open-in-gitpod.svg)](https://gitpod.io/#https://github.com/mahesh-panchal/Nextflow_sandbox)

This [Gitpod](https://www.gitpod.io/) environment (a docker container) comes installed with:
- Git
- Docker
- Apptainer
- Conda
- Pixi
- Nextflow
- nf-core
- nf-test

The [Dockerfile](https://github.com/nf-core/tools/blob/master/nf_core/gitpod/gitpod.Dockerfile) for this environment lives on nf-core/tools.

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
