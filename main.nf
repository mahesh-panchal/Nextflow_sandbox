workflow {
    TASK(1).view()
}

process TASK {
    input:
    val num

    script:
    """
    echo ${num}
    """

    output:
    stdout
}
