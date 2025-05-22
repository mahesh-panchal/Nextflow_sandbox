workflow {
    TASK(1).view()
}

process TASK {
    input:
    val thing

    script:
    """
    echo "${thing}"
    """

    output:
    stdout
}
