workflow {
    def ch_in = channel.of(1)
    def prc_task = TASK(ch_in)
    prc_task.stdout.view()
}

process TASK {
    input:
    val thing

    script:
    """
    cat <<-END_FILE | tee response.txt
    content: ${thing}
    END_FILE
    """

    output:
    path "response.txt", emit: txt
    stdout emit: stdout
}
