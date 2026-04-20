# Nextflow Implementation Patterns

<!-- Author: Mahesh Binzer-Panchal -->

A collection of implementation patterns for Nextflow pipelines following DSL2 Strict Syntax and nf-core ecosystem guidelines.

<!-- This callout is placed at the top intentionally: LLMs weight early context more heavily,
     and if context windows are truncated, the bottom is cut first. Human readers can skip to
     the Table of Contents below. -->

> [!important] For LLMs Generating Nextflow Code
> If you are an LLM generating Nextflow code, pay special attention to:
> - Dynamic directives need closure braces: `memory { 8.GB * task.attempt }` NOT `memory 8.GB * task.attempt`
> - Double quotes for interpolation: `"${meta.id}"` interpolates; `'${meta.id}'` is a literal string
> - Always use `def` for local variables in closures and script blocks
> - `$` is Nextflow interpolation in `"""` blocks; bash variables need `\$`
> - `path` inputs can be a single file or a list — use arity to enforce
> - Groovy falsy values: `0`, `""`, `[]`, and `null` are all falsy — check with `!= null` if `0` is valid
> - `channel.of()` spreads arguments; `channel.fromList()` takes a single list
> - `collect()` gathers items into a list; `collectFile()` writes items to a file
> - `shell:` is deprecated — always use `script:`
> - `getBaseName()` only strips one extension — use `getBaseName(2)` for `.ext.gz` files
> - Prepare for static typing: Use standard assignments, avoid `set`, `tap`, `|`, `&`, `.out`, `each`, implicit `it`
> - Never create or reference channels inside operator closures (`.map`, `.filter`, etc.)
> - No `for` loops in workflow scope — use channel operators
> - Use `if` blocks or channel operators for conditional execution — not the `when:` directive
> - Two or more queue channel inputs to a process must be synchronized with `join` or `combine`
> - Never use `System.exit()` — it skips Nextflow's cleanup phase
> - `ifEmpty` closures emit their return value — always follow with `.filter { item -> item != null }` if log is used in the closure

---

## 🧭 Table of Contents

- [[#Documentation Quick Reference|Documentation Quick Reference]]
- [[#Common Pitfalls|Common Pitfalls]]
- [[#Common Mistakes|Common Mistakes]]
- [[#Preparing for Static Typing|Preparing for Static Typing]]
- [[#Joins and Data Merging|Joins and Data Merging]]
- [[#Fault Tolerance & Fallbacks|Fault Tolerance & Fallbacks]]
- [[#Modern DSL2 Syntax|Modern DSL2 Syntax]]
- [[#Module Conventions|Module Conventions]]
- [[#Groovy Patterns in Nextflow|Groovy Patterns in Nextflow]]
- [[#Helper Functions|Helper Functions]]
- [[#Architectural Patterns|Architectural Patterns]]
- [[#Validation & Testing|Validation & Testing]]
- [[#Resource Management|Resource Management]]
- [[#Publication Patterns|Publication Patterns]]
- [[#Configuration Patterns|Configuration Patterns]]
- [[#Debugging|Debugging]]
- [[#Best Practices Checklist|Best Practices Checklist]]
- [[#Quick Migration Examples|Quick Migration Examples]]
- [[#Additional Resources|Additional Resources]]

---

## 📚 Documentation Quick Reference

These commands fetch the latest Nextflow and plugin documentation directly from the official sources. Useful for verifying operator signatures, config options, or process directives.

### Fetch Latest Nextflow Docs via CLI

```bash
curl -sL https://docs.seqera.io/nextflow/reference/operator
curl -sL https://docs.seqera.io/nextflow/reference/channel
curl -sL https://docs.seqera.io/nextflow/reference/config
curl -sL https://docs.seqera.io/nextflow/reference/process
curl -sL https://docs.seqera.io/nextflow/reference/workflow
curl -sL https://docs.seqera.io/nextflow/reference/process#resourcelimits
curl -sL https://docs.seqera.io/nextflow/reference/process#eval
curl -sL https://docs.seqera.io/nextflow/reference/channel#topic
```

### Plugins

```bash
curl -sL https://nextflow-io.github.io/nf-schema/
curl -sL https://www.nf-test.com/docs/getting-started/
```

---

## ⚠️ Common Pitfalls

These are tricky behaviors that catch even experienced Nextflow developers. Each entry describes the problem, shows the broken pattern, and demonstrates the fix.

### Queue vs Value Channel Semantics

`💡 Convention` — Queue channels are implicitly forked in DSL2, and consume values to make inputs. **value channels** can be reused for every downstream consumer.
The `channel.value(file(...))` pattern is a `🎨 Preference` for single reference files. For globbing multiple files (e.g., `channel.fromPath('data/*.fastq.gz')`),
`fromPath` is the preferred approach.

```nextflow
// 👁️ channel.value() creates a value channel — safe to reuse across processes
ch_reference = channel.value(file(params.reference, checkIfExists: true))

PROCESS_A(ch_input, ch_reference)
PROCESS_B(ch_output, ch_reference)
```

Also note the distinction between `of()` and `fromList()`:

```nextflow
// 👁️ of() spreads each argument as a separate emission
ch_fixed   = channel.of('A', 'B', 'C')        // emits: 'A', 'B', 'C'

// 👁️ fromList() takes a single list and emits each element
ch_dynamic = channel.fromList(['A', 'B', 'C']) // emits: 'A', 'B', 'C'

// The difference matters when the list is a variable:
def items = ['A', 'B', 'C']
channel.of(items)        // emits: ['A', 'B', 'C']  ← one emission (the list itself)
channel.fromList(items)  // emits: 'A', 'B', 'C'    ← three emissions
```

### Closure Braces for Dynamic Directives

`⚠️ Bug` — Without braces, the expression is evaluated **once** at process definition time — not re-evaluated on retry. This means resource escalation silently fails.

```nextflow
// 👁️ Braces make this a closure — re-evaluated on each retry attempt
memory { 8.GB * task.attempt }

// ❌ No braces — evaluated once, task.attempt is always 1
memory 8.GB * task.attempt
```

### String Interpolation: Single vs Double Quotes

`⚠️ Bug` — In Nextflow (Groovy), only **double-quoted** strings interpolate variables. Single-quoted strings are literal.

```nextflow
def name = "sample_1"
println "Processing ${name}"    // → "Processing sample_1"
println 'Processing ${name}'    // → "Processing ${name}" (literal!)
```

Inside `script:` blocks, `$` is Nextflow interpolation by default. To use **bash** variables, escape the dollar sign:

```nextflow
script:
"""
echo "${meta.id}"           // 👁️ Nextflow resolves meta.id before bash sees it
echo "\${PWD}"              // 👁️ \$ escapes Nextflow — bash resolves PWD at runtime
"""
```

### Always Use `def` for Local Variables

`⚠️ Bug` — Without `def`, variables leak into global scope causing **race conditions** between concurrent tasks. This creates intermittent, hard-to-reproduce bugs.

```nextflow
// ✅
.map { meta, files ->
    def new_meta = meta + [processed: true]   // 👁️ def = local to this closure
    [new_meta, files]
}

// ❌ Variable bleeds between concurrent tasks
.map { meta, files ->
    new_meta = meta + [processed: true]       // 👁️ no def = global scope!
    [new_meta, files]
}
```

### Groovy Truthy Edge Cases

`⚠️ Bug` — Groovy's truthiness rules differ from most languages. `0`, `0.0`, `""`, `[]`, and `null` are **all falsy**. This means a valid value of `0` is silently treated as "missing."

```nextflow
// ✅ Safe when value could be 0
def threshold = meta.threshold != null ? "--cutoff ${meta.threshold}" : ""

// ❌ Skips the flag when meta.threshold == 0 (valid value!)
def threshold = meta.threshold ? "--cutoff ${meta.threshold}" : ""
```

### Input Cardinality and Arity

`💡 Convention` — The `arity` qualifier enforces how many files a `path` input accepts. Without it, `path` can be a single `Path` or a `List<Path>` depending on what the channel emits, leading to subtle type errors.

The arity value is always a **string** (not an integer). It controls the type of the variable in the process:

```nextflow
input:
// 👁️ arity: '1' → variable is a single Path object
tuple val(meta), path(files, arity: '1')

// 👁️ arity: '2' → exactly 2 files; variable is a List<Path> of size 2
tuple val(meta), path(files, arity: '2')

// 👁️ arity: '1..*' → one or more files; variable is always a List<Path>
//    (even if only one file is provided)
path('many_*.txt', arity: '1..*')

// 👁️ arity: '0..*' → zero or more files; variable is always a List<Path>
//    (empty list when no files match)
path('optional_*.txt', arity: '0..*')
```

The range syntax follows the pattern `'min..max'` where `*` means unlimited.

### Getting File Base Names (Stripping Extensions)

`⚠️ Bug` — `getBaseName()` only strips **one** extension. For double extensions like `.csv.gz`, you need `getBaseName(2)`.

```nextflow
file("data.csv").getBaseName()        // → "data"        ← correct
file("data.csv.gz").getBaseName()     // → "data.csv"    ← wrong! Only stripped .gz
file("data.csv.gz").getBaseName(2)    // → "data"        ← correct

// 👁️ Auto-detect: strip 2 extensions if gzipped, 1 otherwise
def basename = myfile.getBaseName(myfile.name.endsWith('.gz') ? 2 : 1)
```

### Native Processes with `exec:`

`💡 Convention` — For API calls, metadata transforms, or file manipulation that don't need tools installed in a container, use `exec:` blocks. These run in the **Nextflow JVM** directly.

```nextflow
process API_LOOKUP {
    tag "ID: ${entity_id}"
    label 'process_single'

    input:
    val(entity_id)

    output:
    val(result),                              emit: data
    path("${entity_id}_lookup.json"),         emit: json_file

    when:
    task.ext.when == null || task.ext.when

    exec:
    // 👁️ exec: runs Groovy code in the JVM — no container, no bash
    def response  = new URL("https://api.example.com/v2/entities?id=${entity_id}").text
    def lazy_json = new groovy.json.JsonSlurper().parseText(response)
    result = [
        name   : lazy_json.entities[0]?.name ?: "Unknown",
        type   : lazy_json.entities[0]?.type,
        status : lazy_json.entities[0]?.status,
    ]
    def jsonBuilder = new groovy.json.JsonBuilder(lazy_json)
    file("${task.workDir}/${entity_id}_lookup.json").text = jsonBuilder.toPrettyString()
}
```

### `collect()` vs `collectFile()`

`💡 Convention` — These do very different things despite similar names. `collect()` gathers channel items into a **list**. `collectFile()` writes channel items to a **file**.

```nextflow
ch_all_items   = ch_items.collect()
// → emits: [[item1, item2, item3]]  (one emission: a list)

ch_version_txt = ch_versions.collectFile(name: 'versions.txt', newLine: true)
// → emits: path('versions.txt')  (one emission: a file path)
```

> [!tip] Use a native process instead of `collectFile`
> Native processes (exec:) can be used in place of `collectFile` and are more flexible. 
> For example meta maps can be propagated with the file.

### `collect()` vs `toList()`

`💡 Convention` - These both produce list outputs. The difference in output is when data has nested list, or the channel is empty.

```nextflow
ch_empty = channel.empty()
ch_empty.collect() // No emission
ch_empty.toList() // One emission - []

ch_nested = channel.of(['A', 'B'],[1, 2])
ch_nested.collect() // emits a flattened list - ['A', 'B', 1, 2]
ch_nested.toList() // emits a nested list - [['A', 'B'],[1, 2]]
```

### `multiMap` for Splitting a Channel

`💡 Convention` — When nf-core modules expect inputs split across **separate channels** (e.g., data on one input, index on another), use `multiMap` to create named sub-channels from a single source.

```nextflow
ch_split = ch_input
    .multiMap { meta, data, index, config ->
        data:   [meta, data]       // 👁️ Each branch becomes a separate channel
        index:  [meta, index]
        config: [meta, config]
    }

result = MULTI_INPUT_PROCESS(ch_records, ch_split.data, ch_split.index, ch_split.config)
```

### `-resume` and Cache Invalidation

`💡 Convention` — Understanding what does and doesn't invalidate the Nextflow cache prevents wasted computation and mysterious re-runs.

**Invalidates cache:** Changing `script:` content, `container`, `conda`, input files/values

**Does NOT invalidate cache:** Changing `publishDir`, output definitions, `tag`, `label`

`storeDir` bypasses normal caching — skips the task entirely if the output already exists.

Never use `beforeScript`/`afterScript` — they run outside the container context and can cause irreproducible behavior.

### Config Selector Precedence

`💡 Convention` — When both `withName` and `withLabel` set the same directive, `withName` wins. This is important when you need to override a label-level default for a specific process.

```nextflow
process {
    withLabel: process_high { ext.args = '--fast' }
    withName: MY_PROCESS    { ext.args = '--sensitive' }   // 👁️ This wins
}
```

### Subworkflow vs Process Input Type Handling

`💡 Convention` — Objects passed to **subworkflows** pass through as-is with no type conversion. This is important because it preserves types: param submaps, plain lists, and non-channel objects arrive in the subworkflow exactly as sent.

Objects passed to **processes**, however, are **implicitly converted to value channel inputs** if they aren't already channels. This means a bare file path or a map passed directly to a process becomes a value channel automatically.

```nextflow
// 👁️ Subworkflow: objects pass through unchanged — types preserved
MY_SUBWORKFLOW(ch_reads, params.options)  // params.options arrives as a Map, not a channel

// 👁️ Process: non-channel objects are implicitly wrapped in channel.value()
MY_PROCESS(ch_reads, file(params.reference, checkIfExists: true))    // params.reference becomes channel.value(file(params.reference, checkIfExists: true))
```

This distinction matters when passing param submaps through subworkflows to processes — the subworkflow sees the raw object, while the process receives it as a value channel.

---

## 🚫 Common Mistakes

### Mistake: Modifying Input Files In-Place

`⚠️ Bug` — Input files in work directories are typically **symlinks** back to the original or a cached copy. In-place edits (`sed -i`, `sort -o same_file`) corrupt the **original** file and break `-resume` for every task that shares it.

```bash
# ❌ Corrupts the source file through the symlink
sed -i 's/old/new/g' ${input}

# ✅ Always write to a new file
sed 's/old/new/g' ${input} > ${prefix}_fixed.txt
```

### Mistake: Using `val()` for File Paths Instead of `path()`

`⚠️ Bug` — Files passed as `val` are **not staged** into the work directory. The process receives a raw string path that may not exist inside containers or on cloud executors (S3, GCS).

```nextflow
// ❌ File is not staged — breaks in containers/cloud
input: val(my_file)

// ✅ File is staged into the work directory
input: path(my_file)   // 👁️ path() = staged, val() = just a string
```

### Mistake: Assuming Sequential Process Execution

`⚠️ Bug` — Nextflow is **dataflow-driven**. Processes execute when their input channels have data, not in the order they appear in the script. The only ordering guarantee comes from channel dependencies.

```nextflow
step_a_out = STEP_A(ch_input)
step_b_out = STEP_B(step_a_out.results)   // 👁️ Dependency on step_a_out creates ordering
step_c_out = STEP_C(ch_input)             // 👁️ No dependency — runs in parallel with STEP_A
```

### Mistake: Writing Directly to `params.outdir`

`💡 Convention` — Writing to `params.outdir` from inside a process script bypasses Nextflow's file tracking, breaks caching, and **fails on cloud executors** (S3, GCS). Use `publish:` blocks and `output {}` instead.

```bash
# ❌ Breaks portability and caching
cp output.txt ${params.outdir}/

# ✅ Let Nextflow handle publishing via output {} blocks
```

### Mistake: Referencing Files Outside the Work Directory

`⚠️ Bug` — Each task runs in an **isolated work directory**. Absolute host paths (`/home/user/data/...`) and relative traversals (`../other_task/...`) don't exist inside containers and aren't portable to cloud executors. All inter-process data must flow through channels.

```nextflow
// ❌ Fragile, not portable
script: "cat /home/user/data/reference.txt"

// ✅ Pass through channels — file is staged into the work dir
input: path(reference)
script: "cat ${reference}"
```

### Mistake: Unguarded `ifEmpty` Causing Null Downstream

`⚠️ Bug` — `.ifEmpty()` can be used to display errors or log warnings, but its closure's **return value is emitted** when the channel is empty. `log.warn()` returns `null`, which flows downstream and potentially causes `NullPointerException`. `error()` should halt the pipeline before null can propagate, but a null filter is still good defensive practice for consistency and future refactoring.

```nextflow
// ❌ log.warn returns null → NullPointerException in .map
ch_results
    .ifEmpty { log.warn "No results found" }
    .map { item -> item.toString() }

// ✅ error() halts the pipeline; null filter is defensive
ch_results
    .ifEmpty { error "No results produced" }
    .filter { item -> item != null }                // 👁️ Always follow ifEmpty

// ✅ Warning path: explicit null, then filter
ch_results
    .ifEmpty { log.warn "No results — continuing"; null }
    .filter { item -> item != null }                // 👁️ Removes the null emission
```

### Mistake: Creating Channels Inside Processes or Operator Closures

`⚠️ Bug` — Channel factories (`channel.of()`, `channel.fromPath()`) must be called in **workflow blocks** only. Inside process definitions they are ignored. Inside operator closures (`.map`, `.filter`, `.flatMap`, `.branch`) they produce undefined behavior — closures run synchronously but channels are asynchronous.

```nextflow
// ❌ Cannot create channels inside a process
process BAD {
    script:
    ch = channel.of(1, 2, 3)  // Silently ignored
}

// ❌ Channel inside a map closure — undefined behavior
ch_input.map { meta, file ->
    def extra = channel.fromPath("${meta.id}/*.txt")  // 👁️ NEVER do this
    [meta, file, extra]
}

// ✅ Create channels in workflow blocks, merge with operators
workflow {
    ch = channel.of(1, 2, 3)
    MY_PROCESS(ch)
}

// ✅ Merge data outside closures
ch_extra    = channel.fromPath("data/*.txt")
ch_combined = ch_input.combine(ch_extra)
```

### Mistake: Using `params` Directly in Process Scripts

`💡 Convention` — Makes processes non-reusable, breaks module isolation, and causes **subtle caching issues**: changing a param doesn't invalidate the cache if it's not declared as an input.

```nextflow
// ❌ Coupled to params — cache won't invalidate when params.reference changes
process BAD {
    input: tuple val(meta), path(input_file)
    script: "tool --ref ${params.reference} ${input_file}"   // 👁️ params = invisible to cache
}

// ✅ Pass everything through inputs — cache tracks changes correctly
process GOOD {
    input:
    tuple val(meta), path(input_file)
    path(reference)                                          // 👁️ Declared input = cache-aware

    script:
    "tool --ref ${reference} ${input_file}"
}
```

### Mistake: Not Understanding Container Isolation

`⚠️ Bug` — Tools on the host system aren't guaranteed to be available. Every dependency must come from `conda`, `container`, or scripts in `bin/`.

```nextflow
// ❌ Assumes 'jq' exists — fails if host system doesn't have it installed
process BAD {
    script: "jq '.results' ${input}"
}

// ✅ Declare the container/conda that provides the tool
process GOOD {
    conda "conda-forge::jq=1.7"                             // 👁️ Declares the dependency
    container "community.wave.seqera.io/library/jq:1.7--abc123"
    script: "jq '.results' ${input}"
}
```

### Mistake: Using `println` Instead of `log`

`💡 Convention` — `println` goes to stdout and can be interleaved with process output. `log.info`, `log.warn`, `log.error` are timestamped and go to stderr.

```nextflow
// ❌
println "Starting analysis for ${params.input}"

// ✅
log.info  "Starting analysis for ${params.input}"
log.warn  "Parameter 'skip_qc' is deprecated — use 'qc_skip' instead"
log.error "Reference file not found: ${params.reference}"
```

### Mistake: Using `System.exit()` to Abort a Pipeline

`⚠️ Bug` — `System.exit()` immediately terminates the JVM **without cleanup**. Nextflow's shutdown hooks never run, so execution metadata isn't written to the run database (`.nextflow/history`, `.nextflow/cache`), outputs aren't published, and the trace isn't recorded. Subsequent `-resume` runs may behave unpredictably.

```nextflow
// ❌ Kills the JVM — corrupts run database, breaks -resume
if (!params.input) {
    System.exit(1)                    // 👁️ NEVER use System.exit()
}

// ✅ error() throws an exception Nextflow catches → graceful shutdown
if (!params.input) {
    error "Parameter 'input' is required"
}

// ✅ Validation via nf-schema — errors are reported cleanly
validateParameters()
```

### Mistake: Using `when:` for Conditional Process Execution

`💡 Convention` — The `when:` directive seems natural for conditionally skipping a process, but is unofficially deprecated.

Use workflow-level `if` blocks or channel operators (`filter`, `branch`) instead.

```nextflow
// ❌ Process is in the DAG, tasks are scheduled, then skipped
process QC {
    when: params.run_qc                // 👁️ Don't use when: for conditional logic
    script: "qctool ${input}"
}

// ✅ Workflow-level if: process is entirely excluded from the DAG
workflow {
    ch_qc = channel.empty()
    if (params.run_qc) {               // 👁️ if = process removed from DAG entirely
        qc_out = QC(ch_input)
        ch_qc  = qc_out.reports
    }
}

// ✅ Channel filter: process stays in DAG but only receives matching items
workflow {
    ch_needs_qc = ch_input.filter { meta, _files -> meta.needs_qc }
    qc_out = QC(ch_needs_qc)          // 👁️ filter = process in DAG, 0 tasks if nothing matches
}

// ✅ Branch: multi-way routing
workflow {
    ch_routed = ch_input.branch { meta, _files ->
        needs_qc: meta.needs_qc
        skip_qc:  true
    }
    qc_out = QC(ch_routed.needs_qc)
    ch_all = qc_out.results.mix(ch_routed.skip_qc)
}
```

> [!tip] Understanding `if` vs `filter`/`branch`
> These have fundamentally different effects on the pipeline DAG:
>
> | Mechanism | DAG effect | When to use |
> |---|---|---|
> | `if` block | Process **completely removed** from DAG. No trace entry, no scheduler overhead. | Global on/off switches from `params` (evaluated once at startup). |
> | `filter` / `branch` | Process **stays in DAG** with 0 tasks if nothing matches. Appears in trace. | Per-sample routing by metadata, type, or quality. |

> [!note] **`when: task.ext.when` in nf-core modules**
> The `when: task.ext.when == null || task.ext.when` guard in nf-core module definitions exists for an uncommon but practical workaround: **skipping individual failed samples from config when resuming**. If a sample fails and the workflow lacks built-in skip logic, a user can set `ext.when = { meta.id != 'failed_sample' }` in `modules.config` and re-run with `-resume`.
>
> **Do not use `ext.when` for general conditional logic.** Ideally, workflows should handle sample failures gracefully via `errorStrategy`, metadata flags, or channel filtering — making this workaround unnecessary.

### Mistake: Using `for` Loops in Workflow Scope

`⚠️ Bug` — Nextflow workflows are dataflow-driven and asynchronous. `for` loops execute **synchronously** and cannot properly interact with channels.

```nextflow
// ❌ Synchronous loop — not supported
workflow {
    for (s in ['A', 'B', 'C']) {
        PROCESS(s)                     // 👁️ Linting error
    }
}

// ✅ Channel-driven: each item flows through independently
workflow {
    ch_samples = channel.of('A', 'B', 'C')
    process_out = PROCESS(ch_samples)   // All three run in parallel
}

// ✅ Structured data: use fromList
workflow {
    ch_configs = channel.fromList([
        [id: 'A', mode: 'fast'],
        [id: 'B', mode: 'thorough'],
        [id: 'C', mode: 'fast'],
    ])
    process_out = PROCESS(ch_configs)
}
```

### Mistake: Unsynchronized Queue Channel Inputs

`⚠️ Bug` — When a process receives two or more **queue channels**, Nextflow pairs items by **emission order** (like a zip). If the channels emit in different orders — which is common when items come from different upstream processes with varying runtimes — outputs become **silently mismatched**. This produces wrong results without any error.

```nextflow
// ❌ DANGEROUS: Two queue channels paired by emission order
workflow {
    data_out  = PREPARE_DATA(ch_input)
    index_out = BUILD_INDEX(ch_input)
    // 👁️ If sample_B finishes before sample_A in one process but not the other,
    //    the pairs are WRONG — no error, just wrong results
    QUERY(data_out.results, index_out.idx)
}

// ✅ SAFE: Join by meta key guarantees correct pairing
workflow {
    data_out  = PREPARE_DATA(ch_input)
    index_out = BUILD_INDEX(ch_input)
    ch_synced = data_out.results.join(index_out.idx)   // 👁️ join = matched by key
    QUERY(ch_synced)
}

// ✅ SAFE: Value channel replays for every queue item (no ordering issue)
workflow {
    ch_shared_index = channel.value(file(params.index, checkIfExists: true))
    QUERY(data_out.results, ch_shared_index)           // 👁️ Value channel = always safe
}
```

> [!warning] This applies any time a process has two or more **queue channel** inputs — whether separate `input:` lines or separate `tuple` declarations. If both carry sample-specific data, they **must** be synchronized with `join` (by key) or `combine` (for cross-product). A single `tuple` input from one joined/combined channel is the safest pattern.

---

## 🔑 Preparing for Static Typing

Nextflow 26.04 enables strict syntax by default. Static typing can be adopted progressively, but many legacy patterns are incompatible. Use `nextflow lint` to verify compliance.

### Use Standard Assignments (Avoid `set` and `tap`)

`💡 Convention` — `set` and `tap` are not supported in statically typed workflows.

```nextflow
// ✅ Standard assignment
ch_data = channel.of(1, 2, 3)

// ❌ Not supported in typed workflows
channel.of(1, 2, 3).set { ch_data }
channel.of(1, 2, 3).tap { ch_data }
```

### Use Method Calls (Avoid `|` and `&` Operators)

`💡 Convention` — Pipe and ampersand operators are not supported in statically typed workflows.

```nextflow
// ✅
ch_input = channel.of('Hello', 'Hola', 'Ciao')
greet_out = greet(ch_input)
greet_out.map { v -> v.toUpperCase() }.view()

// ❌
channel.of('Hello', 'Hola', 'Ciao') | greet | map { v -> v.toUpperCase() } | view
```

### Assign Process/Workflow Outputs (Avoid `.out`)

`💡 Convention` — Accessing outputs via `.out` on an unassigned process call is not supported.

```nextflow
// ✅ Standard assignment
my_out = MY_WORKFLOW()
my_out.foo.view()

// ❌ Not supported in typed workflows
MY_WORKFLOW()
MY_WORKFLOW.out.foo.view()
```

### Use `combine` (Avoid `each` Input Qualifier)

`💡 Convention` — The `each` input qualifier is deprecated. Use `combine` in the workflow block to create all pairings, then pass a single tuple to the process.

```nextflow
process ANALYZE {
    input:
    tuple path(data), val(method)        // 👁️ Single tuple input, not each

    script:
    """
    analyze --input ${data} --method ${method} > result
    """
}

workflow {
    datasets = channel.fromPath('*.dat')
    methods  = channel.of('fast', 'standard', 'thorough')
    ANALYZE(datasets.combine(methods))   // 👁️ combine creates all pairs in the workflow
}
```

### Replace Legacy Operators with Typed Alternatives

`💡 Convention` — Some channel operators (like `splitCsv`) are not statically typed. Use `flatMap` with the equivalent Path method instead.

```nextflow
// ✅ Typed: flatMap with Path method
channel.fromPath('samplesheet.csv')
    .flatMap { csv -> csv.splitCsv(sep: ',') }   // 👁️ Method on the Path object

// ❌ Legacy: splitCsv operator not statically typed
channel.fromPath('samplesheet.csv').splitCsv(sep: ',')
```

### Avoid All Deprecated Patterns

This example shows three deprecated patterns in one line: `Channel.from` (use `channel.of`), uppercase `Channel` (use lowercase `channel`), and implicit `it` (name the parameter).

```nextflow
// ❌ Three deprecated patterns
Channel.from(1, 2, 3).map { it * 2 }

// ✅ All three fixed
channel.of(1, 2, 3).map { num -> num * 2 }
```

---

## 🔗 Joins and Data Merging

Common patterns for combining data from multiple channels. These are essential when different processes produce outputs that need to be matched back together by sample key.

### Left Join (Inclusive Join)

Keep all items from the left channel, even if they have no match on the right. Filter with `!= null` (not Groovy truthiness) to handle values like `0` or `""`.

```nextflow
ch_left = channel.of(
    ['key_A', 'data1'], ['key_B', 'data2'], ['key_C', 'data3']
)
ch_right = channel.of(
    ['key_A', 'meta1'], ['key_B', 'meta2']
)

ch_left_join = ch_left
    .join(ch_right, remainder: true)                    // 👁️ remainder: true = keep unmatched
    .filter { _id, left, _right -> left != null }       // 👁️ != null, not truthy check
```

### Right Join

Keep all items from the right channel, even if they have no match on the left.

```nextflow
ch_right_join = ch_left
    .join(ch_right, remainder: true)
    .filter { _id, _left, right -> right != null }
```

### Anti-Join (Set Difference / Exclusion)

Keep items from `ch_data` whose keys are **not** in `ch_exclude`. This works by mixing a sentinel value into the excluded keys, grouping by key, and filtering out groups that contain the sentinel.

> [!note] This operation must wait for all entries before emitting (because of `groupTuple`).

```nextflow
ch_data    = channel.of([1, "A", "f1"], [2, "B", "f2"], [3, "C", "f3"], [4, "D", "f4"])
ch_exclude = channel.of(1, 3, 5)

ch_filtered = ch_data
    // Step 1: Tag excluded keys with sentinel value 1
    .mix(ch_exclude.map { key -> [key, 1] })
    // ch now has: [1,"A","f1"], [2,"B","f2"], [3,"C","f3"], [4,"D","f4"], [1,1], [3,1], [5,1]

    // Step 2: Group all values by key (first element)
    .groupTuple()
    // [1, ["A",1], ["f1"]], [2, ["B"], ["f2"]], [3, ["C",1], ["f3"]], [4, ["D"], ["f4"]], [5, [1]]

    // Step 3: Keep only groups where sentinel 1 is NOT present
    .filter { _key, values -> !(1 in values) }
    // [2, ["B"], ["f2"]], [4, ["D"], ["f4"]]

    // Step 4: Transpose back to individual tuples
    .transpose()
    // [2, "B", "f2"], [4, "D", "f4"]
```

### Cross-Product (Combine)

Every item in the first channel is paired with every item in the second.

```nextflow
ch_combinations = channel.of('S1', 'S2').combine(channel.of('RefA', 'RefB'))
// → ['S1', 'RefA'], ['S1', 'RefB'], ['S2', 'RefA'], ['S2', 'RefB']
```

### Inner Join

Only items with matching keys in both channels are emitted. This is the default behavior of `join`.

```nextflow
ch_matched = ch_input.join(ch_metadata)
```

---

## 🛡️ Fault Tolerance & Fallbacks

Patterns for handling missing files, optional inputs, and transient failures.

### Fallback Channel Pattern (Prefer First Non-Empty Channel)

When you need to prefer one channel over another — for example, using a user-provided list if available, or falling back to a default — use `collect()`, `concat()`, `first()`, and `flatten()`.

The key insight: **`collect()` on an empty channel emits nothing** (not an empty list). This means `concat()` skips past it to the next channel, and `first()` picks whichever channel actually emits.

```nextflow
// 👁️ collect() on empty channel = no emission → concat skips to next channel
ch_preferred = some_optional_channel.collect()
ch_fallback  = channel.of([])               // 👁️ Always emits — guarantees first() resolves

ch_result = ch_preferred
    .concat(ch_fallback)    // Try preferred first; if nothing, use fallback
    .first()                // Pick the first emission
    .flatten()              // Unwrap [item1, item2] → item1, item2
```

Practical example — custom entry file from params, falling back to default list:

```nextflow
ch_custom_entries = params.custom_entries
    ? channel.fromList(file(params.custom_entries, checkIfExists: true).splitCsv(header: true)).collect()
    : channel.empty()                          // 👁️ No param → empty channel, empty file → empty channel
ch_default_entries = channel.of(['GENE_A', 'GENE_B']) // 👁️ Default list

ch_filter_entries = ch_custom_entries
    .concat(ch_default_entries)
    .first()
    .flatten()
```

### Optional Inputs (Empty Value Pattern)

Pass `[]` (empty list) for optional `path` inputs and `''` for optional `val` inputs. The process script checks for emptiness and omits the corresponding flag.

```nextflow
// nf-core style: ?: '' fallbacks, defensive when: guard
process PROCESS_DATA {
    input:
    tuple val(meta), path(input_files)
    path(index)
    val(extra_args)

    when:
    task.ext.when == null || task.ext.when

    script:
    def args      = task.ext.args   ?: ''
    def prefix    = task.ext.prefix ?: "${meta.id}"
    def index_cmd = index      ? "--index ${index}" : ""     // 👁️ Empty [] is falsy → skips flag
    def extra     = extra_args ? "${extra_args}"     : ""     // 👁️ Empty '' is falsy → skips flag
    """
    tool process ${index_cmd} ${extra} ${args} ${input_files} > ${prefix}.out
    """
}

workflow {
    ch_index = params.prebuilt_index
        ? channel.value(file(params.prebuilt_index, checkIfExists: true))
        : channel.value([])                                  // 👁️ Empty list = no index

    process_out = PROCESS_DATA(ch_input, ch_index, channel.value(''))
}
```

### Error Handling with Retry

Retry tasks that fail with common out-of-memory or timeout exit codes. After 3 retries, let the task fail gracefully (don't abort the whole pipeline).

```nextflow
process HEAVY_TASK {
    errorStrategy {
        task.exitStatus in [104, 110, 137, 139, 143] && task.attempt <= 3
            ? 'retry'      // 👁️ OOM/timeout → retry with escalated resources
            : 'finish'     // 👁️ Other errors or max retries → let pipeline finish other tasks
    }
    maxRetries 3

    script:
    """
    run_heavy_task.sh --threads ${task.cpus}
    """
}
```

---

## 🏗️ Modern DSL2 Syntax

Patterns for idiomatic DSL2 code using current Nextflow features.

### Single Reference File Pattern

Wrap reference files in `channel.value()` so they can be consumed by multiple processes without being exhausted.

```nextflow
ch_reference = channel.value(file(params.reference, checkIfExists: true))
ch_config    = channel.value(file(params.config_file, checkIfExists: true))
ch_database  = channel.value(file(params.database, checkIfExists: true))
```

### Meta Map Pattern

Parse a samplesheet into a channel of `[meta, files]` tuples using nf-schema. `samplesheetToList()` reads the CSV and validates it against the JSON schema, returning a list of tuples where each tuple element corresponds to a column defined in the schema.

```nextflow
include { samplesheetToList } from 'plugin/nf-schema'

def samplesheet_to_channel(csv) {
    // 👁️ samplesheetToList returns a list of tuples: [[meta_map, file1, file2], ...]
    //    Each tuple's structure is defined by the JSON schema
    channel.fromList(samplesheetToList(csv, "${projectDir}/assets/schemas/schema_input.json"))
        .map { meta, file_1, file_2 ->
            def files    = file_2 ? [file_1, file_2] : [file_1]
            def new_meta = meta + [num_files: files.size()]
            [new_meta, files]
        }
}
```

### Parameter Validation with nf-schema

Validate all parameters against the schema **before** any process runs. This catches typos and missing required params early.

```nextflow
include { samplesheetToList; validateParameters } from 'plugin/nf-schema'

workflow {
    validateParameters()                                     // 👁️ Fails fast on bad params
    def ch_input = samplesheet_to_channel(params.input)
}
```

### Version Capture with Topic Channels

Use `eval()` to capture tool versions at runtime and `topic:` to collect them across all processes into a single channel.

```nextflow
process DATA_QC {
    tag "${meta.id}"

    input:
    tuple val(meta), path(input_files)

    output:
    tuple val(meta), path("*.html"),                                                                    emit: html
    tuple val(meta), path("*.zip"),                                                                     emit: zip
    // 👁️ eval() runs a shell command; topic: sends the result to a named topic channel
    tuple val("${task.process}"), val('qctool'), eval('qctool --version 2>&1 | head -1'), emit: versions_qctool, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    """
    qctool ${args} --threads ${task.cpus} ${input_files}
    """
}

workflow {
    qc_out = DATA_QC(ch_input)

    // 👁️ channel.topic() collects all emissions tagged with 'versions' from any process
    ch_versions = channel.topic('versions')
        .unique()
        .collectFile(name: 'software_versions.txt', newLine: true, sort: true)
}
```

---

## 📦 Module Conventions

### Module Styles

There are two common conventions for structuring Nextflow process modules. Both are valid; the choice depends on whether you're writing a reusable community module or a pipeline-specific local module.

> [!note] **Harshil Alignment** `🎨 Preference`
> The nf-core community uses a distinctive output formatting style (named after Harshil Patel) where `emit:` and `topic:` labels are right-aligned across output declarations. This improves readability when scanning long output blocks. Harshil alignment is an **nf-core community convention** — it is not a Nextflow language requirement or a general best practice for all pipelines.
>
> ```nextflow
> output:
> tuple val(meta), path("*.bam"),                                                                     emit: bam
> tuple val(meta), path("*.bai"),                                                                     emit: bai
> tuple val("${task.process}"), val('tool'), eval('tool --version | head -1'), emit: versions, topic: versions
> ```

### nf-core Module Structure `🎨 Preference`

nf-core modules use `?: ''` fallbacks for `task.ext` values (in case nothing is set in config) and a defensive `when:` guard. They assume nothing about `meta` beyond `meta.id` and declare `conda`/`container` for reproducibility.

```nextflow
process TOOL_SORT {
    tag "${meta.id}"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/xx/xxxx/data'
        : 'community.wave.seqera.io/library/tool:1.0--xxxxx'}"

    input:
    tuple val(meta), path(input_file)

    output:
    tuple val(meta), path("*.sorted.dat"),                                                                  emit: sorted
    tuple val("${task.process}"), val('tool'), eval('tool --version | head -1'), emit: versions_tool, topic: versions

    // 👁️ nf-core guard: runs unless ext.when is explicitly set to false
    when:
    task.ext.when == null || task.ext.when

    script:
    // 👁️ ?: '' fallbacks — safe when config doesn't set ext.args or ext.prefix
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    tool sort ${args} --threads ${task.cpus} -o ${prefix}.sorted.dat ${input_file}
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.sorted.dat
    """
}
```

### Mahesh Style: Local Module Structure `🎨 Preference`

Local (pipeline-specific) modules can use **Mahesh style** (named after Mahesh Binzer-Panchal), which sets `ext` defaults directly in the process directive block. This eliminates the need for `?: ''` fallbacks since default values are guaranteed. The `when: task.ext.when` guard is simpler because `ext when: true` provides the default.

Mahesh style formatting is available as a VS Code setting in the Nextflow extension, which also places `output:` after `script:` and `stub:` blocks — grouping execution logic together with structural/metadata declarations at the end. Most readers will be more familiar with output-before-script ordering, so the remaining examples in this document use the conventional order.

```nextflow
process DATA_PROCESS {
    tag "${meta.id}"
    label 'process_high'
    // 👁️ ext defaults set here — no ?: '' fallbacks needed in script block
    ext prefix: "${meta.id}", args: '', when: true

    input:
    tuple val(meta), path(input_files, arity: '1..*')
    tuple val(meta2), path(reference)
    path(index)

    // 👁️ Simplified guard: ext when: true default means always true unless overridden
    when: task.ext.when

    script:
    // 👁️ No ?: '' needed — ext defaults guarantee these are never null
    def args   = task.ext.args
    def prefix = task.ext.prefix
    """
    tool process ${args} -t ${task.cpus} ${index}/db ${input_files} \\
    | tool sort -t ${task.cpus} -o ${prefix}.out -
    """

    stub:
    def prefix = task.ext.prefix
    """
    touch ${prefix}.out
    """

    // 👁️ Mahesh style: output after script/stub (VS Code Nextflow extension setting)
    output:
    tuple val(meta), path("*.out"),                                                                             emit: results
    tuple val("${task.process}"), val('tool'), eval('tool 2>&1 | grep Version | sed "s/Version: //"'), emit: versions_tool, topic: versions
}
```

### Scripts in `bin/`

Scripts in `bin/` are automatically added to `$PATH` inside every task. Make them executable with proper shebangs and **call by name** — never by interpreter. If a script is sourced or adapted from another tool, comment the origin so you can find upstream fixes later.

```python
# bin/parse_report.py
#!/usr/bin/env python
# Source: adapted from ToolX v2.5 — github.com/toolx/toolx/blob/main/scripts/parse.py
"""Parse tool report into summary TSV."""
import argparse, csv, json, sys

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--input', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    # ... parsing logic
```

```bash
# bin/filter_results.sh
#!/usr/bin/env bash
# Source: original
set -euo pipefail
awk -F'\t' '\$5 >= 30' "\$1"
```

```bash
chmod +x bin/parse_report.py bin/filter_results.sh
```

Usage in a process — call the script by name, not by interpreter:

```nextflow
process PARSE_AND_FILTER {
    tag "${meta.id}"
    ext prefix: "${meta.id}", args: '', when: true

    input:
    tuple val(meta), path(report)

    output:
    tuple val(meta), path("*_filtered.tsv"), emit: filtered

    script:
    def prefix = task.ext.prefix
    """
    parse_report.py --input "${report}" --output "${prefix}_summary.tsv"
    filter_results.sh "${prefix}_summary.tsv" > "${prefix}_filtered.tsv"
    """
}
```

### Bash Variable Escaping

Inside `"""` script blocks, `$` is Nextflow interpolation by default. Bash variables must be escaped with `\$`. This is a common sources of bugs.

```nextflow
process EXAMPLE {
    input:
    tuple val(meta), path(input_file)

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    echo "Processing sample: ${prefix}"            # 👁️ Nextflow variable — no escape
    echo "Using ${task.cpus} CPUs"                 # 👁️ Nextflow variable — no escape

    RESULT_DIR="\${PWD}/results"                   # 👁️ Bash variable — escaped with \$
    mkdir -p "\${RESULT_DIR}"

    for FILE in *.txt; do
        BASENAME="\$(basename "\${FILE}" .txt)"    # 👁️ \$() = bash command substitution
        echo "\${BASENAME}" >> "\${RESULT_DIR}/manifest.txt"
    done

    echo "${prefix} processed at \$(date)" >> "\${RESULT_DIR}/log.txt"
    #     ^^^^^^^^ Nextflow             ^^^^^^^^ bash
    """
}
```

### Logging Best Practices

Log to **stderr** (`>&2`) inside tasks so diagnostic messages don't contaminate stdout (which may be piped to the next tool).
Use `tee` to ensure output captured as logs are still emitted to their respective streams. This prevents loss of diagnostic
information on process errors when scratch allocations are given up.

```nextflow
process ANALYZE {
    tag "${meta.id}"

    input:
    tuple val(meta), path(input)

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    echo "[TASK] Starting analysis for ${prefix}" >&2        # 👁️ >&2 = stderr
    echo "[TASK] Using ${task.cpus} CPUs and ${task.memory}" >&2

    analyze.sh ${input} > output.txt 2> >(tee -a analysis.log >&2)

    echo "[TASK] Analysis complete for ${prefix}" >&2
    """
}
```

>[!note] process.scratch
> `process.scratch` is a directive that enables the use of a local scratch directory, which is often on faster disk 
> than the shared filesystem where the work directory resides.
> These are often node local allocations which are only valid for the duration of the job. Processes are executed in
> this directory, and files are first written here before being copied to the work directory on successful completion of a
> process. If a process fails, these files are often lost when the allocation is given up by the job scheduler.

### Fetching and Caching Databases

`storeDir` bypasses normal caching — the process is skipped entirely if the output directory already contains the expected files. Useful for large databases that shouldn't be re-downloaded on every run.

```nextflow
process FETCH_DB {
    storeDir "${params.db_cachedir}/my_db"         // 👁️ storeDir = skip if output exists

    input:
    path manifest

    output:
    path("db_files/*"), emit: db

    script:
    """
    mkdir db_files
    fetch_db --outdir db_files/ ${manifest}
    """
}

workflow {
    fetch_out = FETCH_DB()
    QUERY_DB(ch_data, fetch_out.db)
}
```

---

## 🧩 Groovy Patterns in Nextflow

Useful Groovy idioms for building command strings, config files, and conditional arguments inside Nextflow scripts and config closures.

### Map-based Choice (Replaces Nested Ternary)

When a value maps to a flag string, use a Groovy `Map` instead of nested ternary operators. This is more readable and easier to extend.

```nextflow
def mode_presets = [
    fast     : '--mode fast --skip-validation',
    balanced : '--mode balanced',
    thorough : '--mode thorough --extra-checks',
    custom   : '--mode custom'
]
def preset = mode_presets[meta.processing_mode] ?: ''    // 👁️ Map lookup with fallback

// For output extension detection based on flags:
def format_map = [
    ["--output-type json", "-oj"]: "json",
    ["--output-type csv",  "-oc"]: "csv",
    ["--output-type tsv",  "-ot"]: "tsv",
    ["--output-type xml",  "-ox"]: "xml"
]
def extension = format_map
    .find { flags, _ext -> flags.any { flag -> args.contains(flag) } }
    ?.value ?: "tsv"
```

### Array-based String Construction

Build complex argument strings by collecting items into a list, removing empties, and joining. This avoids deeply nested ternaries in config closures.

Config closures (inside `ext.args = { ... }`) can reference `meta`, `task`, `params`, **and process input variable names** (like `input_file` below) because they are evaluated in the task context where all inputs are in scope.

```nextflow
process {
    withName: TOOL_PROCESS {
        ext.args = { [
            meta.data_type == "type_a" ? "--mode fast"     : "",
            meta.data_type == "type_b" ? "--mode balanced" : "",
            meta.data_type == "type_c" ? "--mode thorough" : "",
            "--validate",
            // 👁️ input_file is a process input variable name — accessible in config closures
            input_file.size() > 2.5e9
                ? ("--buffer " + Math.ceil(input_file.size() / 1e9) + "G")
                : "",
        ].minus("").join(" ") }     // 👁️ Remove empties, then join with spaces
    }
}
```

### Transpose for Parallel Pairing

Use Groovy's `transpose()` to zip multiple lists together and generate config lines. Useful when building tool configuration files from parallel arrays. These snippets are excerpts from inside a `script:` block where the variables are defined earlier.

```nextflow
script:
// source_names, index_paths, processor_types are lists defined earlier in the script block
def config_content = [source_names, index_paths, processor_types]
    .transpose()                    // 👁️ [[a,b,c],[1,2,3],[x,y,z]] → [[a,1,x],[b,2,y],[c,3,z]]
    .collect { name, idx, proc -> "SOURCE ${name} ${idx} ${proc}" }
    .join('\n    ')
"""
cat <<-END_CONFIG > tool.conf
    ${config_content}
END_CONFIG
run_tool --config tool.conf
"""
```

### Config Construction with Builders and Heredocs

For complex config formats (YAML, JSON), use Groovy's builder classes to serialize maps correctly, then inject into a heredoc. The `parameters` variable below is a process input. The heredoc also allows bash variables to be interpolated such as `\$PWD`.

```nextflow
    script:
    def task_params = [meta: meta, cpus: task.cpus, artifact_dir: "\$PWD/artifacts"] + (parameters ?: [:])
    def yamlBuilder = new groovy.yaml.YamlBuilder()
    yamlBuilder.call(task_params)
    def yaml_content = yamlBuilder.toString().tokenize('\n').join("\n    ") // 👁️ Join includes content indent
    """
    cat <<-END_YAML > params.yml
    ${yaml_content}
    END_YAML
    """
```

### Custom Config from a Map

For simple key-value config files, iterate over a map and format each entry. The `prefix`, `args`, and `input_file` variables below come from the enclosing `script:` block.

```nextflow
    script:
    def settings = [threads: task.cpus, memory_mb: task.memory.toMega(), output_format: 'csv']
    def config_lines = settings.collect { key, value -> "${key} = ${value}" }.join('\n    ') // 👁️ Join includes content indent
    """
    cat <<-END_CONF > ${prefix}.conf
    ${config_lines}
    END_CONF
    run_tool --config ${prefix}.conf ${args} ${input_file}
    """
```

---

## 🔧 Helper Functions

Define reusable functions in another file similar to modules. Annotate with Javadoc so IDE tooltips and documentation generators can pick them up.

### `deepMergeMaps`

Recursively merge two maps. Nested maps are merged; other values are replaced by the right-hand side. Keys only in `rhs` are added.

```nextflow
/**
 * Deep-merge two maps. Nested maps are merged recursively;
 * other values are replaced by rhs. Keys only in rhs are added.
 */
def deepMergeMaps(Map lhs, Map rhs) {
    lhs.collectEntries { k, v ->
        if (rhs[k] instanceof Map && v instanceof Map) {
            [(k): deepMergeMaps(v, rhs[k])]       // 👁️ Recursive merge for nested maps
        } else if (rhs.containsKey(k)) {
            [(k): rhs[k]]                          // 👁️ containsKey, not truthy — preserves 0, "", false
        } else {
            [(k): v]
        }
    } + rhs.subMap(rhs.keySet() - lhs.keySet())    // 👁️ Add keys only in rhs
}

def base    = [id: 'sample1', config: [stage: 'raw', build: 'v1']]
def overlay = [config: [stage: 'polished'], condition: 'treated']
def merged  = deepMergeMaps(base, overlay)
// → [id: 'sample1', config: [stage: 'polished', build: 'v1'], condition: 'treated']
```

### `joinByMetaKeys`

Join two channels using specific meta map keys instead of the entire first element. Supports keeping `lhs`, `rhs`, `merge`d, or `subset` meta.

```nextflow
/**
 * Join two channels using specific meta map keys.
 *
 * @param args.keySet     List of meta keys to join on (required)
 * @param args.meta       Which meta to keep: 'lhs', 'rhs', 'merge', or 'subset'
 * @param args.remainder  Pass-through to join operator
 * @param args.failOnMismatch   Pass-through to join operator
 * @param args.failOnDuplicate  Pass-through to join operator
 */
def joinByMetaKeys(Map args = [:], lhs, rhs) {
    assert args.keySet != null
    // 👁️ Build a join key from specific meta fields, prepend it to each tuple
    def join_args = args.subMap(['remainder', 'failOnMismatch', 'failOnDuplicate']) + [by: 0]
    if (args.meta == 'lhs') {
        return lhs.map { row -> [row[0].subMap(args.keySet)] + row }
            .join(join_args, rhs.map { row -> [row[0].subMap(args.keySet)] + row.tail() })
            .map { row -> row.tail() }       // 👁️ Strip the synthetic join key
    } else if (args.meta == 'rhs') {
        def restructure = { _key, clip, tail -> [tail.removeAt(clip)] + tail }
        return lhs.map { row -> [row[0].subMap(args.keySet), row.size() - 1] + row.tail() }
            .join(join_args, rhs.map { row -> [row[0].subMap(args.keySet)] + row })
            .map { tuple -> restructure.call(tuple[0], tuple[1], tuple[2..-1]) }
    } else if (args.meta == 'merge') {
        def restructure = { _key, clip, tail -> [deepMergeMaps(tail.head(), tail.removeAt(clip))] + tail.tail() }
        return lhs.map { row -> [row[0].subMap(args.keySet), row.size()] + row }
            .join(join_args, rhs.map { row -> [row[0].subMap(args.keySet)] + row })
            .map { tuple -> restructure.call(tuple[0], tuple[1], tuple[2..-1]) }
    } else if (args.meta == 'subset') {
        return lhs.map { row -> [row[0].subMap(args.keySet)] + row.tail() }
            .join(join_args, rhs.map { row -> [row[0].subMap(args.keySet)] + row.tail() })
    } else {
        assert args.meta in ['lhs', 'rhs', 'merge', 'subset']
    }
}
```

Usage examples:

```nextflow
// Join by 'id' key, keep the right channel's meta
ch_joined = joinByMetaKeys(ch_bams, ch_beds, keySet: ['id'], meta: 'rhs')

// Join by 'id' and 'sample_type', merge both metas
ch_merged = joinByMetaKeys(ch_data, ch_annotations,
    keySet: ['id', 'sample_type'], meta: 'merge')

// Join with failure on unmatched keys
ch_strict = joinByMetaKeys(ch_a, ch_b,
    keySet: ['id'], meta: 'lhs', failOnMismatch: true)
```

### `combineByMetaKeys`

Like `joinByMetaKeys`, but produces a cross-product instead of an inner join. Useful when every item from one channel should be paired with every matching item from another.

```nextflow
/**
 * Combine two channels using specific meta map keys.
 *
 * @param args.keySet  List of meta keys to combine on (required)
 * @param args.meta    Which meta to keep: 'lhs', 'rhs', 'merge', or 'subset'
 */
def combineByMetaKeys(Map args = [:], lhs, rhs) {
    assert args.keySet != null
    def combine_args = [by: 0]
    if (args.meta == 'lhs') {
        return lhs.map { row -> [row[0].subMap(args.keySet)] + row }
            .combine(combine_args, rhs.map { row -> [row[0].subMap(args.keySet)] + row.tail() })
            .map { row -> row.tail() }
    } else if (args.meta == 'rhs') {
        def restructure = { _key, clip, tail -> [tail.removeAt(clip)] + tail }
        return lhs.map { row -> [row[0].subMap(args.keySet), row.size() - 1] + row.tail() }
            .combine(combine_args, rhs.map { row -> [row[0].subMap(args.keySet)] + row })
            .map { tuple -> restructure.call(tuple[0], tuple[1], tuple[2..-1]) }
    } else if (args.meta == 'merge') {
        def restructure = { _key, clip, tail -> [deepMergeMaps(tail.head(), tail.removeAt(clip))] + tail.tail() }
        return lhs.map { row -> [row[0].subMap(args.keySet), row.size()] + row }
            .combine(combine_args, rhs.map { row -> [row[0].subMap(args.keySet)] + row })
            .map { tuple -> restructure.call(tuple[0], tuple[1], tuple[2..-1]) }
    } else if (args.meta == 'subset') {
        return lhs.map { row -> [row[0].subMap(args.keySet)] + row.tail() }
            .combine(combine_args, rhs.map { row -> [row[0].subMap(args.keySet)] + row.tail() })
    } else {
        assert args.meta in ['lhs', 'rhs', 'merge', 'subset']
    }
}
```

Usage examples:

```nextflow
// Cross-product by 'batch' key, keep left meta
ch_cross = combineByMetaKeys(ch_samples, ch_references, keySet: ['batch'], meta: 'lhs')

// Cross-product by 'id', merge metas
ch_all_pairs = combineByMetaKeys(ch_data, ch_configs, keySet: ['id'], meta: 'merge')
```

---

## 🗂️ Architectural Patterns

Patterns for organizing pipeline code into modules, subworkflows, and a root workflow.

### Project Structure

```
.
├── main.nf
├── nextflow.config
├── nextflow_schema.json
├── modules/
│   ├── local/
│   │   └── data_process.nf
│   └── nf-core/
│       ├── tool_qc/main.nf
│       └── tool_sort/main.nf
├── subworkflows/
│   ├── local/
│   │   ├── preprocessing.nf
│   │   └── analysis.nf
│   └── nf-core/
│       └── utils_nfcore_pipeline/main.nf
├── assets/schemas/schema_input.json
├── bin/
│   ├── parse_report.py
│   └── filter_results.sh
├── conf/
│   ├── base.config
│   └── modules.config
└── tests/
    ├── main.nf.test
    ├── modules/
    │   └── clean_and_process.nf.test
    └── subworkflows/
        └── preprocessing.nf.test
```

### Root `main.nf` with Staged Execution

A root workflow that validates parameters, parses the samplesheet, and conditionally executes pipeline stages based on `params.stages`. Note how `if` blocks completely remove stages from the DAG when not requested.

> [!note] The `publish:` block and `output {}` block used here are explained in detail in the [[#Publication Patterns|Publication Patterns]] section.

```nextflow
include { samplesheetToList; validateParameters } from 'plugin/nf-schema'
include { PREPROCESSING } from './subworkflows/local/preprocessing'
include { ANALYSIS      } from './subworkflows/local/analysis'

params.stages = ["preprocess", "analyze"]

workflow {

    main:
    validateParameters()
    def ch_input = samplesheet_to_channel(params.input)

    def ch_processed_index = channel.empty()
    def preprocessing_out = null
    if ("preprocess" in params.stages) {                     // 👁️ if = removes from DAG if false
        preprocessing_out = PREPROCESSING(
            ch_input,
            channel.value(file(params.reference, checkIfExists: true)),
            channel.value(file(params.index, checkIfExists: true))
        )
        ch_processed_index = preprocessing_out.processed
            .map { meta, processed -> [sample: meta.id, file: processed] }
    }

    def ch_results = channel.empty()
    if ("analyze" in params.stages) {
        def ch_analysis_input = preprocessing_out
            ? preprocessing_out.processed
            : ch_input
        analysis_out = ANALYSIS(ch_analysis_input, channel.value(file(params.reference, checkIfExists: true)))
        ch_results = analysis_out.results
    }

    publish:
    processed = ch_processed_index
    results   = ch_results
    versions  = channel.topic('versions').unique()
                    .collectFile(name: 'software_versions.txt', newLine: true, sort: true)
}

output {
    processed {
        path 'results/processed'
        index { path 'processed_files.csv'; header true; sep ',' }
    }
    results  { path 'results/analysis' }
    versions { path 'pipeline_info' }
}

def samplesheet_to_channel(csv) {
    channel.fromList(samplesheetToList(csv, "${projectDir}/assets/schemas/schema_input.json"))
        .map { meta, file_1, file_2 ->
            def files    = file_2 ? [file_1, file_2] : [file_1]
            def new_meta = meta + [num_files: files.size()]
            [new_meta, files]
        }
}
```

### Subworkflow with Mixed Modules

A subworkflow that combines local and nf-core modules. Subworkflows use `take:`/`main:`/`emit:` sections.

```nextflow
// subworkflows/local/preprocessing.nf
include { CLEAN_AND_PROCESS } from '../../modules/local/clean_and_process'
include { TOOL_DEDUP        } from '../../modules/nf-core/tool/dedup/main'

workflow PREPROCESSING {
    take:
    ch_input
    ch_reference
    ch_index

    main:
    clean_out = CLEAN_AND_PROCESS(ch_input, ch_index)
    dedup_out = TOOL_DEDUP(clean_out.processed)

    emit:
    processed = dedup_out.output
    index     = dedup_out.index
    qc        = clean_out.qc
    metrics   = dedup_out.metrics
}
```

### Bundled Process with Piping

When multiple short tools are chained via pipes, bundling them into a single process avoids the overhead of separate tasks. This is useful when intermediate files aren't needed.

```nextflow
process ETL_PIPELINE {
    tag "${meta.id}"
    label 'process_high'
    ext prefix: "${meta.id}", args: '', when: true

    input:
    tuple val(meta), path(input_files, arity: '1..*')
    path(lookup_db)

    output:
    tuple val(meta), path("*.processed.gz"), emit: processed
    tuple val(meta), path("*.idx"),          emit: index
    path("*_validation.json"),               emit: reports
    path("*.etl.log"),                       emit: etl_log
    tuple val("${task.process}"), val('cleaner'),   eval('cleaner --version 2>&1 | head -1'),   emit: versions_cleaner,   topic: versions
    tuple val("${task.process}"), val('enricher'),  eval('enricher --version 2>&1 | head -1'),  emit: versions_enricher,  topic: versions
    tuple val("${task.process}"), val('validator'), eval('validator --version 2>&1 | head -1'),  emit: versions_validator, topic: versions

    when: task.ext.when

    script:
    def args   = task.ext.args
    def prefix = task.ext.prefix
    """
    cleaner --input ${input_files.join(' ')} \\
        --stdout --threads ${task.cpus} --log ${prefix}.etl.log \\
    | enricher --threads ${task.cpus} ${args} --db ${lookup_db} - \\
    | gzip -c > ${prefix}.processed.gz

    indexer --threads ${task.cpus} ${prefix}.processed.gz
    validator --threads ${task.cpus} --report ${prefix}_validation.json ${input_files} &
    # 👁️ & backgrounds validator so it runs in parallel with indexer
    wait
    # 👁️ wait ensures all backgrounded tasks complete before the process exits
    """
}
```

### Batching Short Tasks

For tasks under a few seconds each, batch them using `xargs` or `parallel` inside a single process to reduce scheduler overhead.

```nextflow
process DATA_STATS {
    tag "${meta.id}"

    input:
    tuple val(meta), path(data_file), path(index_file)

    output:
    tuple val(meta), path("*.stats"),    emit: stats
    tuple val(meta), path("*.summary"),  emit: summary
    tuple val(meta), path("*.counts"),   emit: counts
    tuple val("${task.process}"), val('tool'), eval('tool --version 2>&1 | head -1'), emit: versions, topic: versions

    script:
    """
    tool stats   --threads ${task.cpus} ${data_file} > ${data_file}.stats
    tool summary --threads ${task.cpus} ${data_file} > ${data_file}.summary
    tool counts  ${data_file} > ${data_file}.counts
    """
}

process BATCH_GUNZIP {
    label 'process_low'

    input:
    path(archives)

    output:
    path("*.decompressed"), emit: files

    script:
    """
    printf "%s\\n" ${archives} | \\
        xargs -P ${task.cpus} -I {} \\
        bash -c 'gzip -cdf {} > \$(basename {} .gz).decompressed'
    """
}
```

---

## ✅ Validation & Testing

nf-test provides three testing scopes: `nextflow_process` for individual modules, `nextflow_workflow` for subworkflows, and `nextflow_pipeline` for end-to-end pipeline tests.

### nf-test for Local Modules

Test a single process in isolation by providing mock inputs.

```nextflow
nextflow_process {
    name "Test CLEAN_AND_PROCESS"
    script "../../modules/local/clean_and_process.nf"
    process "CLEAN_AND_PROCESS"
    tag "modules_local"

    test("Should process input data") {
        when {
            process {
                """
                input[0] = channel.of(
                    [[id: 'test_sample', num_files: 1], file("${projectDir}/tests/data/test.dat")]
                )
                input[1] = file("${projectDir}/tests/data/index/")
                """
            }
        }
        then {
            assertAll(
                { assert process.success },
                { assert process.out.processed },
                { assert process.out.qc }
            )
        }
    }
}
```

### nf-test for Subworkflows

Test a subworkflow by providing its `take:` inputs and asserting on `emit:` outputs.

```nextflow
nextflow_workflow {
    name "Test PREPROCESSING"
    script "../../subworkflows/local/preprocessing.nf"
    workflow "PREPROCESSING"
    tag "subworkflows_local"

    test("Should preprocess input data") {
        when {
            workflow {
                """
                input[0] = channel.of(
                    [[id: 'sample_A', num_files: 1], file("${projectDir}/tests/data/sample_A.dat")],
                    [[id: 'sample_B', num_files: 1], file("${projectDir}/tests/data/sample_B.dat")]
                )
                input[1] = channel.value(file("${projectDir}/tests/data/reference.dat"))
                input[2] = channel.value(file("${projectDir}/tests/data/index/"))
                """
            }
        }
        then {
            assertAll(
                { assert workflow.success },
                { assert workflow.out.processed.size() == 2 },
                { assert workflow.out.qc.size() == 2 },
                { assert workflow.out.metrics }
            )
        }
    }

    test("Should handle single sample") {
        when {
            workflow {
                """
                input[0] = channel.of(
                    [[id: 'solo_sample', num_files: 1], file("${projectDir}/tests/data/sample_A.dat")]
                )
                input[1] = channel.value(file("${projectDir}/tests/data/reference.dat"))
                input[2] = channel.value(file("${projectDir}/tests/data/index/"))
                """
            }
        }
        then {
            assertAll(
                { assert workflow.success },
                { assert workflow.out.processed.size() == 1 }
            )
        }
    }
}
```

### Pipeline E2E Tests

Test the entire pipeline from samplesheet to final outputs. Use `workflow.trace` to verify task counts.

```nextflow
nextflow_pipeline {
    name "Test full pipeline"
    script "../main.nf"

    test("Should complete successfully") {
        when {
            params {
                input     = "${projectDir}/tests/data/samplesheet.csv"
                reference = "${projectDir}/tests/data/reference.dat"
                index     = "${projectDir}/tests/data/index/"
                outdir    = "${outputDir}"
            }
        }
        then {
            assertAll(
                { assert workflow.success },
                { assert workflow.trace.succeeded().size() >= 3 },
                { assert workflow.trace.failed().size() == 0 }
            )
        }
    }

    test("Should fail gracefully with missing input") {
        when {
            params { input = "non_existent.csv" }
        }
        then {
            assert workflow.failed
            assert workflow.exitStatus != 0
        }
    }
}
```

```bash
nf-test init
nf-test test tests/**/*.nf.test --profile docker
```

---

## 🏋️ Resource Management

### Process Resource Limits

`resourceLimits` caps any process that requests more than the cluster maximum. This replaces the old `params.max_cpus` / `params.max_memory` pattern.

```nextflow
process {
    resourceLimits = [cpus: 24, memory: 128.GB, time: 72.h]   // 👁️ Cluster maximum

    withLabel: process_low    { cpus = 2;  memory = 4.GB;  time = 2.h  }
    withLabel: process_medium { cpus = 6;  memory = 16.GB; time = 8.h  }
    withLabel: process_high   { cpus = 12; memory = 64.GB; time = 24.h }
}
```

### Dynamic Retry with Resource Escalation

Multiply resources by `task.attempt` so each retry gets more resources. Combined with `errorStrategy`, this handles transient OOM/timeout failures automatically.

```nextflow
process ASSEMBLY {
    label 'process_high'
    cpus   { 8     * task.attempt }      // 👁️ Closure braces = re-evaluated on retry
    memory { 16.GB * task.attempt }
    time   { 4.h   * task.attempt }

    errorStrategy {
        task.exitStatus in [104, 110, 137, 139, 143] && task.attempt <= 3
            ? 'retry' : 'finish'
    }
    maxRetries 3
}
```

---

## 📤 Publication Patterns

Modern Nextflow uses `publish:` labels in the workflow block paired with an `output {}` block to control where files are published.
`publishDir` is still a valid pattern, especially for pipelines not yet using the `output {}` block. When using `publishDir`, configure
it in `modules.config` via `withName:` selectors — not inside the process definition itself. This keeps processes portable and publishing
decisions centralized.

### Workflow Output with Output Block

```nextflow
workflow ANALYSIS {
    take:
    ch_input

    main:
    qc_out      = QC(ch_input)
    process_out = PROCESS(ch_input)
    analyze_out = ANALYZE(process_out.output)

    emit:
    qc      = qc_out.html
    output  = process_out.output
    index   = process_out.index
    results = analyze_out.results
}

workflow {
    analysis_out = ANALYSIS(ch_input)

    publish:                                               // 👁️ Labels map to output {} targets
    output   = analysis_out.output
    results  = analysis_out.results
    versions = channel.topic('versions').unique()
                    .collectFile(name: 'software_versions.txt', newLine: true, sort: true)
}

output {                                                   // 👁️ Defines publish destinations
    output {
        path 'results/processed'
        index { path 'processed_files.csv'; header true; sep ',' }
    }
    results  { path 'results/analysis' }
    versions { path 'pipeline_info' }
}
```

>[!tip] Index files
> Publishing index files creates a samplesheet, which contains the paths of files as they appear in your publish directory,
> not your work directory. This can be leveraged to resume from intermediate stages, allowing the work directory to be
> cleaned up and save disk space.

---

## ⚙️ Configuration Patterns

### Root `nextflow.config`

The root config sets params, plugins, process.shell, includes split configs, and defines profiles. Executor configuration belongs **only in profiles** (except `executor = 'local'`).

```nextflow
// nextflow.config
params {
    input              = null
    outdir             = 'results'
    save_intermediates = false
}

plugins {
    id 'nf-schema@2.3.0'
}

// Set bash options (matches nf-core template)
process.shell = [
    "bash",
    "-C",         // No clobber - prevent output redirection from overwriting files.
    "-e",         // Exit if a tool returns a non-zero status/exit code
    "-u",         // Treat unset variables and parameters as an error
    "-o",         // Returns the status of the last command to exit..
    "pipefail"    //   ..with a non-zero status or zero if all successfully execute
]

includeConfig 'conf/base.config' // 👁️ Placed before profiles in nf-core to allow profiles to override resource labels

profiles {
    docker {
        docker.enabled    = true
        docker.runOptions = '-u $(id -u):$(id -g)'
    }
    singularity {
        singularity.enabled    = true
        singularity.autoMounts = true
    }
    conda {
        conda.enabled = true
    }
    slurm {
        executor.name      = 'slurm'           // 👁️ Executor only in profiles
        executor.queueSize = 100
    }
    sge {
        executor.name = 'sge'
    }
}

env {
    NXF_OPTS = '-Xms1g -Xmx4g'
}

includeConfig 'conf/modules.config' // 👁️ Placed at end of file in nf-core to allow nf-core test profiles to affect module configuration
```

### `conf/base.config`

Resource labels and limits are hardcoded — never use `params.max_cpus` / `params.max_memory`. `resourceLimits` automatically caps any label that exceeds the cluster maximum.

```nextflow
// conf/base.config
process {
    resourceLimits = [cpus: 24, memory: 128.GB, time: 72.h]

    withLabel: process_single { cpus = 1;  memory = 2.GB;  time = 1.h  }
    withLabel: process_low    { cpus = 2;  memory = 4.GB;  time = 2.h  }
    withLabel: process_medium { cpus = 6;  memory = 16.GB; time = 8.h  }
    withLabel: process_high   { cpus = 12; memory = 64.GB; time = 24.h }
}
```

### `conf/modules.config`

Use simple names (not fully qualified) to allow easier user configuration. Process aliases are configured by their alias name. Use `ext.args` and `ext.prefix` to control process behavior from configuration.

> [!note] **`ext.when` in config: sample-skipping workaround only**
> Do not use `ext.when` for general conditional logic — use workflow-level `if` blocks or channel operators instead. The only legitimate use of `ext.when` in config is the uncommon case of skipping individual failed samples when resuming a pipeline that lacks built-in sample-failure handling:
> ```nextflow
> // Skip a specific failed sample on -resume (workaround, not best practice)
> withName: 'HEAVY_PROCESS' {
>     ext.when = { meta.id != 'failed_sample_id' }
> }
> ```

```nextflow
// conf/modules.config
process {
    withName: 'DATA_QC' {
        ext.args = '--quiet'
    }

    withName: 'DATA_PROCESS' {
        ext.args   = '--strict'
        ext.prefix = { "${meta.id}.processed" }  // 👁️ Closure — re-evaluated per task
    }

    withName: 'TOOL_SORT' {
        ext.prefix = { "${meta.id}.sorted" }
    }

    // Process alias configuration
    // include { DATA_PROCESS as DATA_PROCESS_FIRST_PASS } from '...'
    withName: 'DATA_PROCESS_FIRST_PASS' {
        ext.args = '--strict --quality 20'
    }

    // GPU-aware process
    withName: 'GPU_PROCESS' {
        ext.use_gpu = true
        ext.args    = '--accelerated'
    }
}
```

### Configuration Precedence Rules

Understanding how configuration sources combine prevents surprises.

**Selector precedence** (same directive, same scope):
- `withName` beats `withLabel` beats unscoped `process {}`
- Later declarations in the same file override earlier ones
- Full process names (includes subworkflows) and regular expressions take precedence over simple names (process name only)

**Config source precedence** (highest to lowest):
1. Command-line flags (`--param`)
2. `-params-file` YAML/JSON
3. `-c` user config - don't use for params; use params-file instead
4. `nextflow.config` in launch dir
5. `nextflow.config` in project dir
6. `$HOME/.nextflow/config`

**Key rules:**
- `includeConfig` inserts at the point of the statement — order matters
- profiles merge on top of base config when activated
- Closures (`{ }`) in config are evaluated lazily at task time; bare values are evaluated once
- `ext.args = { ... }` closures can reference `meta`, `task`, `params`, **and process input variable names** (e.g., `reads`, `reference`) because they are evaluated in the task context where all inputs are in scope
- `ext.args = '...'` string is fixed at config parse time — none of the above are available

```nextflow
// ✅ Closure — re-evaluated per task, can see meta, task, params, and input variables
ext.args = { meta.type == 'large' ? '--high-mem' : '--low-mem' }   // 👁️ { } = closure

// ❌ Bare expression — evaluated once at config parse, meta not available
ext.args = meta.type == 'large' ? '--high-mem' : '--low-mem'       // 👁️ No { } = parse-time
```

---

## 🐛 Debugging

### Work Directory Structure

Every task gets an isolated work directory containing the script, logs, and symlinked inputs/outputs. When a task fails, inspect these files to understand what happened.

```
work/
└── ab/
    └── cdef1234567890.../
        ├── .command.sh      # The actual script executed
        ├── .command.run     # Wrapper script (env setup, file staging)
        ├── .command.err     # stderr
        ├── .command.log     # stdout
        ├── .command.out     # Alternative stdout + stderr capture
        ├── .exitcode        # Exit code
        └── (symlinked inputs and outputs)
```

To find and inspect a failed task:

```bash
# Find the work directory for recent tasks
nextflow log last -f process,status,workdir

# Inspect the error output
cat work/ab/cdef1234567890.../.command.err

# See the exact script that was executed
cat work/ab/cdef1234567890.../.command.sh

# Re-run the script manually for debugging
cd work/ab/cdef1234567890.../
bash .command.run # 👁️ run .command.sh in execution environment
```

---

## 📝 Best Practices Checklist

Markers: `⚠️` = causes bugs/failures, `💡` = convention/best practice, `🎨` = style preference

### Code Quality & Syntax

- [ ] `💡` Use `path` qualifier: Never `file`
- [ ] `💡` Check file existence: `file(params.x, checkIfExists: true)`
- [ ] `💡` Lowercase `channel`: `channel.of`, `channel.fromPath`, `channel.value`, `channel.topic`
- [ ] `💡` Value channels for single files: `channel.value(file(...))`
- [ ] `💡` Tag processes: `tag "${meta.id}"`
- [ ] `💡` Name outputs: `emit:` for all outputs
- [ ] `⚠️` Explicit closures: Never implicit `it`; name all variables
- [ ] `💡` Unused variables: Prefix with `_`
- [ ] `💡` Version tracking: `eval()` with `topic:` in outputs
- [ ] `⚠️` Escape bash variables: `\${VAR}` inside `"""` blocks
- [ ] `⚠️` Always use `def`: For all local variables
- [ ] `⚠️` Double quotes for interpolation: `"${meta.id}"` not `'${meta.id}'`
- [ ] `⚠️` Closure braces: `memory { 8.GB * task.attempt }`
- [ ] `💡` Log to stderr: `>&2` for diagnostics in tasks; `log.info`/`log.warn` in workflows
- [ ] `⚠️` `getBaseName`: `myfile.getBaseName(myfile.name.endsWith('.gz') ? 2 : 1)`

### Safeguards

- [ ] `⚠️` Never modify input files in-place: Write to new files
- [ ] `⚠️` Use `path()` for files, `val()` for strings/numbers: Never pass file paths as `val`
- [ ] `⚠️` Understand dataflow: Processes run when inputs are ready, not in script order
- [ ] `💡` Never write to `params.outdir` from scripts: Use `publish:` + `output {}`
- [ ] `⚠️` All file references through channels: No absolute paths or `../` in scripts
- [ ] `⚠️` Guard empty channels: `.ifEmpty { log.warn ... }.filter { item -> item != null }`
- [ ] `⚠️` Channels only in workflow blocks: Never inside processes or operator closures
- [ ] `💡` No `params` in process scripts: Pass everything through `input:` declarations
- [ ] `⚠️` Declare all dependencies: `conda`/`container` for every tool used in `script:`
- [ ] `💡` Use `log.info`/`log.warn`/`log.error`: Never `println` in workflow blocks
- [ ] `⚠️` Never `System.exit()`: Use `error()` for graceful shutdown with cleanup
- [ ] `💡` No `when:` for conditional logic: Use `if` blocks or `filter`/`branch` in workflow scope
- [ ] `💡` No `ext.when` in config for general logic: Only for sample-skipping workaround on `-resume`
- [ ] `⚠️` No `for` loops in workflow scope: Use channel operators
- [ ] `⚠️` Synchronize queue channel inputs: Two or more queue channels must use `join` or `combine`

### Static Typing Readiness

- [ ] `💡` Standard assignments: No `set` or `tap`
- [ ] `💡` Standard method calls: No `|` or `&` dataflow operators
- [ ] `💡` Assign process outputs: `result = PROCESS(...)` not `PROCESS.out`
- [ ] `💡` No `each` qualifier: Use `combine` instead
- [ ] `💡` No legacy operators: Replace with `flatMap` + method equivalents
- [ ] `💡` Run `nextflow lint`: Verify strict syntax compliance

### Module Conventions

- [ ] `💡` Meta access: Only `meta.id` required in modules; avoid assuming other meta keys exist
- [ ] `💡` ext in modules: May read `task.ext.args`, `.args2`, `.prefix`, `.when`, `.use_gpu`
- [ ] `💡` ext in config: Only set `.args`, `.args2`, `.prefix`, `.use_gpu` (`.when` only for sample-skipping)
- [ ] `🎨` Mahesh style (local modules): ext defaults in directives; `when: task.ext.when`, `output:` after `script:`
- [ ] `🎨` nf-core style (community modules): `?: ''` fallbacks; `when: task.ext.when == null || task.ext.when`
- [ ] `🎨` Harshil alignment: Right-aligned `emit:`/`topic:` labels (nf-core convention)
- [ ] `💡` Optional inputs: `[]` for paths, `''` for values
- [ ] `💡` Input arity: Use `arity:` (string value) to enforce file counts and type
- [ ] `💡` Never use `beforeScript`/`afterScript`
- [ ] `💡` `bin/` scripts: Executable with `#!/usr/bin/env` shebangs; call by name not interpreter
- [ ] `💡` Sourced scripts: Comment the origin URL/tool for upstream bug fixes

### Channel Operations

- [ ] `💡` Left/Right joins: `join` + `remainder: true` + filter with `!= null`
- [ ] `💡` Anti-joins: Sentinel + `groupTuple` + filter
- [ ] `⚠️` Null-safe truthy: `!= null` when `0` or `""` valid
- [ ] `💡` Fallback: `collect()` + `concat()` + `first()` + `flatten()` for channel priority
- [ ] `💡` Branch over filter: `.branch` for multi-way routing
- [ ] `💡` `multiMap`: Split channels for nf-core module inputs
- [ ] `💡` `of()` vs `fromList()`: `of` spreads; `fromList` takes list
- [ ] `💡` `collect()` vs `collectFile()`: Items to list vs items to file
- [ ] `⚠️` No channels inside closures: Never use channel factories/operators inside `.map`, `.filter`, etc.
- [ ] `⚠️` Synchronize queue inputs: `join`/`combine` before passing to processes with multiple queue inputs
- [ ] `⚠️` `ifEmpty` null guard: Always follow `.ifEmpty { ... }` with `.filter { item -> item != null }`

### Architecture

- [ ] `💡` Bundle short processes: Under ~5 minutes
- [ ] `💡` Batch short tasks: `xargs` or `parallel`
- [ ] `💡` Pipe between tools: Avoid intermediate files
- [ ] `💡` Clean temp files: `rm -rf` when piping isn't possible
- [ ] `💡` Module layout: `modules/local/`, `modules/nf-core/`
- [ ] `💡` Subworkflow layout: `subworkflows/local/`, `subworkflows/nf-core/`
- [ ] `💡` Database caching: `storeDir` with `params.db_cachedir`
- [ ] `💡` `exec:` for API calls: Native processes without containers
- [ ] `💡` Conditional execution in workflow scope: `if` blocks or `filter`/`branch`
- [ ] `⚠️` No `for` loops: Use channel operators for iteration
- [ ] `⚠️` No `System.exit()`: Use `error()` for all pipeline aborts

### Configuration

- [ ] `💡` `process.shell`: Set bash options matching nf-core template
- [ ] `💡` Config split: `base.config` + `modules.config` via `includeConfig`
- [ ] `💡` `resourceLimits`: Hardcoded in base config — no `params.max_*`
- [ ] `💡` Executor in profiles only: Never hardcode executor (except `'local'`)
- [ ] `💡` Simple names: Prefer `withName: 'TOOL'` over fully qualified names
- [ ] `⚠️` Closures for dynamic ext: `ext.args = { ... }` when referencing `meta` or `params`
- [ ] `💡` No `ext.when` in config: Except for sample-skipping workaround on `-resume`

### Publishing

- [ ] `💡` `publish:` labels + `output {}` block
- [ ] `💡` Index samplesheets: For staged execution
- [ ] `💡` No `publishDir` in process definitions: Use `output {}` block, or configure `publishDir` in `modules.config`

### Testing

- [ ] `💡` Module tests: `nextflow_process`
- [ ] `💡` Subworkflow tests: `nextflow_workflow`
- [ ] `💡` Pipeline tests: `nextflow_pipeline` with trace assertions
- [ ] `💡` Failure tests: Invalid inputs fail gracefully
- [ ] `💡` CI/CD: nf-test on every PR

---

## 🔧 Quick Migration Examples

Quick before/after patterns for the most common migrations.

### Standard assignment (static typing ready)

```nextflow
// ✅
ch_data = channel.of(1, 2, 3)
result = MY_PROCESS(ch_data)
result.output.view()

// ❌
channel.of(1, 2, 3).set { ch_data }
MY_PROCESS(ch_data)
MY_PROCESS.out.output.view()
```

### Replace `each` with `combine`

```nextflow
// ✅
ANALYZE(datasets.combine(methods))
// ❌
process ANALYZE { input: path data; each method }
```

### Replace legacy operators

```nextflow
// ✅
channel.fromPath('samplesheet.csv').flatMap { csv -> csv.splitCsv(sep: ',') }
// ❌
channel.fromPath('samplesheet.csv').splitCsv(sep: ',')
```

### Value channels for single files

```nextflow
// ✅
ch_ref = channel.value(file(params.reference, checkIfExists: true))
// ❌
ch_ref = channel.fromPath(params.reference, checkIfExists: true).collect()
```

### Mahesh style local modules (ext defaults) and output at end.

```nextflow
// ✅ ext defaults in directives — no ?: '' needed in script
// ✅ directives, inputs, when, script, output
process TASK {
    ext prefix: "${meta.id}", args: '', when: true

    input:
    tuple val(meta), path (thing)

    when: task.ext.when

    script:
    def args = task.ext.args
    def prefix = task.ext.prefix
    """
    echo "${thing} ${args}" > ${prefix}.record
    """

    output:
    stdout
}
```

### Bash escaping

```nextflow
// ✅
"""
echo "${meta.id}" ; echo "\${PWD}"
"""
// ❌
"""
OUTDIR="${PWD}/results"
"""
```

### `getBaseName` for compressed files

```nextflow
// ✅
def basename = myfile.getBaseName(myfile.name.endsWith('.gz') ? 2 : 1)
// ❌
def basename = myfile.getBaseName()
```

### Conditional execution (not `when:`)

```nextflow
// ✅ if block — removes process from DAG entirely
if (params.run_qc) {
    qc_out = QC(ch_input)
}

// ✅ branch — process in DAG, receives filtered items
ch_routed = ch_input.branch { meta, _f -> needs_qc: meta.needs_qc; skip: true }
qc_out = QC(ch_routed.needs_qc)

// ❌ when: directive — process scheduled then skipped, wastes resources
process QC { when: params.run_qc }
```

### Channel operators (not `for` loops)

```nextflow
// ✅
ch_samples = channel.of('A', 'B', 'C')
result = PROCESS(ch_samples)

// ❌
for (s in ['A', 'B', 'C']) { PROCESS(s) }
```

### Synchronize queue channel inputs

```nextflow
// ✅ Join by key before passing to process
ch_synced = ch_data.join(ch_index)
PROCESS(ch_synced)

// ❌ Two unsynchronized queue channels — silent mismatch
PROCESS(ch_data, ch_index)
```

---

## 📚 Additional Resources

### Official Documentation

- **Nextflow Docs:** https://docs.seqera.io/nextflow/
- **Operators:** https://docs.seqera.io/nextflow/reference/operator
- **Channels:** https://docs.seqera.io/nextflow/reference/channel
- **Processes:** https://docs.seqera.io/nextflow/reference/process
- **Workflows:** https://docs.seqera.io/nextflow/reference/workflow
- **Config:** https://docs.seqera.io/nextflow/reference/config
- **nf-schema Plugin:** https://nextflow-io.github.io/nf-schema/

### Community Resources

- **nf-core Guidelines:** https://nf-co.re/docs/guidelines
- **nf-test Documentation:** https://www.nf-test.com/
- **Nextflow Patterns:** https://nextflow-io.github.io/patterns/
- **Seqera Community:** https://community.seqera.io/

```bash
curl -sL https://docs.seqera.io/nextflow/reference/operator
curl -sL https://docs.seqera.io/nextflow/reference/channel
nf-test init
nf-test test tests/**/*.nf.test --profile docker
```

---

> **Last Updated:** April 18, 2026
> **Nextflow Version:** 26.04+
> **nf-core Compatible:** Yes
